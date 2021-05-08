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

    /// Emit the API baseline file and return its path.
    func emitAPIBaseline() throws -> AbsolutePath {
        let apiDiffDir = inputBuildParameters.apiDiff
        let sdkJSON = apiDiffDir.appending(component: baselineTreeish + ".json")

        // We're done if the baseline already exists on disk.
        if localFileSystem.exists(sdkJSON) {
            return sdkJSON
        }

        // Setup a temporary directory where we can checkout and build the baseline treeish.
        let baselinePackageRoot = apiDiffDir.appending(component: baselineTreeish)
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
        try apiDigesterTool.emitAPIBaseline(
            to: sdkJSON,
            modules: graph.apiDigesterModules,
            additionalArgs: buildOp.buildPlan!.createAPIToolCommonArgs(includeLibrarySearchPaths: false)
        )

        return sdkJSON
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
        modules: [String],
        additionalArgs: [String]
    ) throws {
        var args = ["-dump-sdk"]
        args += additionalArgs
        args += modules.flatMap { ["-module", $0] }
        args += ["-o", outputPath.pathString]
        try localFileSystem.createDirectory(outputPath.parentDirectory, recursive: true)

        try runTool(args)

        // FIXME: The tool doesn't exit with 1 if it fails.
        if !localFileSystem.exists(outputPath) {
            throw Diagnostics.fatalError
        }
    }

    /// Compare the current package API to a provided baseline file.
    public func compareAPIToBaseline(
        at baselinePath: AbsolutePath,
        apiToolArgs: [String],
        modules: [String]
    ) throws -> ComparisonResult {
        var args = [
            "-diagnose-sdk",
            "-baseline-path", baselinePath.pathString,
        ]
        args.append(contentsOf: apiToolArgs)
        for module in modules {
            args.append(contentsOf: ["-module", module])
        }
        return try withTemporaryFile(deleteOnClose: false) { file in
            args.append(contentsOf: ["-serialize-diagnostics-path", file.path.pathString])
            try runTool(args)
            let contents = try localFileSystem.readFileContents(file.path)
            let serializedDiagnostics = try SerializedDiagnostics(bytes: contents)
            let apiDigesterCategory = "api-digester-breaking-change"
            let apiBreakingChanges = serializedDiagnostics.diagnostics.filter { $0.category == apiDigesterCategory }
            let otherDiagnostics = serializedDiagnostics.diagnostics.filter { $0.category != apiDigesterCategory }
            return ComparisonResult(apiBreakingChanges: apiBreakingChanges,
                                    otherDiagnostics: otherDiagnostics)
        }
    }

    private func runTool(_ args: [String]) throws {
        let arguments = [tool.pathString] + args
        let process = Process(
            arguments: arguments,
            outputRedirection: .none,
            verbose: verbosity != .concise
        )
        try process.launch()
        try process.waitUntilExit()
    }
}

extension SwiftAPIDigester {
    /// The result of comparing a module's API to a provided baseline.
    public struct ComparisonResult {
        /// Breaking changes made to the API since the baseline was generated.
        var apiBreakingChanges: [SerializedDiagnostics.Diagnostic]
        /// Other diagnostics emitted while comparing the current API to the baseline.
        var otherDiagnostics: [SerializedDiagnostics.Diagnostic]

        /// `true` if the comparison succeeded and no breaking changes were found, otherwise `false`.
        var isSuccessful: Bool {
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
            .flatMap { $0.targets }
            .filter { $0.type == .library }
            .filter { $0.underlyingTarget is SwiftTarget }
            .map { $0.c99name }
    }
}

extension SerializedDiagnostics.SourceLocation: DiagnosticLocation {
    public var description: String {
        guard let file = filename else { return "<unknown>" }
        return "\(file):\(line):\(column)"
    }
}
