/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import TSCUtility

import SPMBuildCore
import Build
import PackageGraph
import PackageModel
import SourceControl
import Workspace

/// Helper for emitting a JSON API baseline for a module.
struct APIDigesterBaselineDumper {

    /// The git treeish to emit a baseline for.
    let baselineTreeish: String

    /// The root package path.
    let packageRoot: AbsolutePath

    /// The input build parameters.
    let inputBuildParameters: BuildParameters

    /// The manifest loader.
    let manifestLoader: ManifestLoaderProtocol

    /// The repository manager.
    let repositoryManager: RepositoryManager

    /// The API digester tool.
    let apiDigesterTool: SwiftAPIDigester

    /// The diagnostics engine for emitting errors/warnings.
    let diags: DiagnosticsEngine

    init(
        baselineTreeish: String,
        packageRoot: AbsolutePath,
        buildParameters: BuildParameters,
        manifestLoader: ManifestLoaderProtocol,
        repositoryManager: RepositoryManager,
        apiDigesterTool: SwiftAPIDigester,
        diags: DiagnosticsEngine
    ) {
        self.baselineTreeish = baselineTreeish
        self.packageRoot = packageRoot
        self.inputBuildParameters = buildParameters
        self.manifestLoader = manifestLoader
        self.repositoryManager = repositoryManager
        self.apiDigesterTool = apiDigesterTool
        self.diags = diags
    }

    /// Emit the API baseline files and return the path to their directory.
    func emitAPIBaseline(for modulesToDiff: Set<String>) throws -> AbsolutePath {
        var modulesToDiff = modulesToDiff
        let apiDiffDir = inputBuildParameters.apiDiff
        let baselineDir = apiDiffDir.appending(component: baselineTreeish)
        let baselinePath: (String)->AbsolutePath = { module in
            baselineDir.appending(component: module + ".json")
        }

        for module in modulesToDiff {
            if localFileSystem.exists(baselinePath(module)) {
                // If this baseline already exists, we don't need to regenerate it.
                modulesToDiff.remove(module)
            }
        }

        guard !modulesToDiff.isEmpty else {
            // If none of the baselines need to be regenerated, return.
            return baselineDir
        }

        // Setup a temporary directory where we can checkout and build the baseline treeish.
        let baselinePackageRoot = apiDiffDir.appending(component: "\(baselineTreeish)-checkout")
        if localFileSystem.exists(baselinePackageRoot) {
            try localFileSystem.removeFileTree(baselinePackageRoot)
        }

        // Clone the current package in a sandbox and checkout the baseline revision.
        let specifier = RepositorySpecifier(url: baselinePackageRoot.pathString)
        let workingCopy = try repositoryManager.provider.createWorkingCopy(
            repository: specifier,
            sourcePath: packageRoot,
            at: baselinePackageRoot,
            editable: false
        )

        try workingCopy.checkout(revision: Revision(identifier: baselineTreeish))

        // Create the workspace for this package.
        let workspace = Workspace.create(
            forRootPackage: baselinePackageRoot,
            manifestLoader: manifestLoader,
            repositoryManager: repositoryManager
        )

        let graph = try workspace.loadPackageGraph(
            rootPath: baselinePackageRoot, diagnostics: diags)

        // Don't emit a baseline for a module that didn't exist yet in this revision.
        modulesToDiff.formIntersection(graph.apiDigesterModules)

        // Abort if we weren't able to load the package graph.
        if diags.hasErrors {
            throw Diagnostics.fatalError
        }

        // Update the data path input build parameters so it's built in the sandbox.
        var buildParameters = inputBuildParameters
        buildParameters.dataPath = workspace.dataPath

        // Build the baseline module.
        let buildOp = BuildOperation(
            buildParameters: buildParameters,
            cacheBuildManifest: false,
            packageGraphLoader: { graph },
            pluginInvoker: { _ in [:] },
            diagnostics: diags,
            stdoutStream: stdoutStream
        )

        try buildOp.build()

        // Dump the SDK JSON.
        for module in modulesToDiff {
            try apiDigesterTool.emitAPIBaseline(
                to: baselinePath(module),
                for: module,
                buildPlan: buildOp.buildPlan!,
                diagnosticsEngine: diags
            )
        }

        return baselineDir
    }
}

/// A wrapper for the swift-api-digester tool.
public struct SwiftAPIDigester {

    /// The absolute path to `swift-api-digester` in the toolchain.
    let tool: AbsolutePath

    init(tool: AbsolutePath) {
        self.tool = tool
    }

    /// Emit an API baseline file for the specified module at the specified location.
    public func emitAPIBaseline(
        to outputPath: AbsolutePath,
        for module: String,
        buildPlan: BuildPlan,
        diagnosticsEngine: DiagnosticsEngine
    ) throws {
        var args = ["-dump-sdk"]
        args += buildPlan.createAPIToolCommonArgs(includeLibrarySearchPaths: false)
        args += ["-module", module, "-o", outputPath.pathString]
        try localFileSystem.createDirectory(outputPath.parentDirectory, recursive: true)

        try runTool(args)

        if !localFileSystem.exists(outputPath) {
            diagnosticsEngine.emit(error: "failed to generate baseline for \(module)")
            throw Diagnostics.fatalError
        }
    }

    /// Compare the current package API to a provided baseline file.
    public func compareAPIToBaseline(
        at baselinePath: AbsolutePath,
        for module: String,
        buildPlan: BuildPlan
    ) -> ComparisonResult? {
        var args = [
            "-diagnose-sdk",
            "-baseline-path", baselinePath.pathString,
            "-module", module
        ]
        args.append(contentsOf: buildPlan.createAPIToolCommonArgs(includeLibrarySearchPaths: false))

        return try? withTemporaryFile(deleteOnClose: false) { file in
            args.append(contentsOf: ["-serialize-diagnostics-path", file.path.pathString])
            try runTool(args)
            let contents = try localFileSystem.readFileContents(file.path)
            guard contents.count > 0 else {
                return nil
            }
            let serializedDiagnostics = try SerializedDiagnostics(bytes: contents)
            let apiDigesterCategory = "api-digester-breaking-change"
            let apiBreakingChanges = serializedDiagnostics.diagnostics.filter { $0.category == apiDigesterCategory }
            let otherDiagnostics = serializedDiagnostics.diagnostics.filter { $0.category != apiDigesterCategory }
            return ComparisonResult(moduleName: module,
                                    apiBreakingChanges: apiBreakingChanges,
                                    otherDiagnostics: otherDiagnostics)
        }
    }

    private func runTool(_ args: [String]) throws {
        let arguments = [tool.pathString] + args
        let process = Process(
            arguments: arguments,
            outputRedirection: .collect,
            verbose: verbosity != .concise
        )
        try process.launch()
        try process.waitUntilExit()
    }
}

extension SwiftAPIDigester {
    /// The result of comparing a module's API to a provided baseline.
    public struct ComparisonResult {
        /// The name of the module being diffed.
        var moduleName: String
        /// Breaking changes made to the API since the baseline was generated.
        var apiBreakingChanges: [SerializedDiagnostics.Diagnostic]
        /// Other diagnostics emitted while comparing the current API to the baseline.
        var otherDiagnostics: [SerializedDiagnostics.Diagnostic]

        /// `true` if the comparison succeeded and no breaking changes were found, otherwise `false`.
        var hasNoAPIBreakingChanges: Bool {
            apiBreakingChanges.isEmpty && otherDiagnostics.filter { [.fatal, .error].contains($0.level) }.isEmpty
        }
    }
}

extension BuildParameters {
    /// The directory containing artifacts for API diffing operations.
    var apiDiff: AbsolutePath {
        dataPath.appending(component: "apidiff")
    }
}

extension PackageGraph {
    /// The list of modules that should be used as an input to the API digester.
    var apiDigesterModules: [String] {
        self.rootPackages
            .flatMap(\.products)
            .filter { $0.type.isLibrary }
            .flatMap(\.targets)
            .filter { $0.underlyingTarget is SwiftTarget }
            .map { $0.c99name }
    }
}

extension SerializedDiagnostics.SourceLocation: DiagnosticLocation {
    public var description: String {
        return "\(filename):\(line):\(column)"
    }
}
