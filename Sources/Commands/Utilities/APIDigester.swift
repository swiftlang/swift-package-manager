//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Dispatch
import Foundation

import SPMBuildCore
import Basics
import CoreCommands
import PackageGraph
import PackageModel
import SourceControl
import Workspace

import protocol TSCBasic.DiagnosticLocation
import class TSCBasic.Process
import struct TSCBasic.ProcessResult
import func TSCBasic.withTemporaryFile

import enum TSCUtility.Diagnostics
import struct TSCUtility.SerializedDiagnostics
import var TSCUtility.verbosity

/// Helper for emitting a JSON API baseline for a module.
struct APIDigesterBaselineDumper {

    /// The revision to emit a baseline for.
    let baselineRevision: Revision

    /// The root package path.
    let packageRoot: AbsolutePath

    /// Parameters used when building end products.
    let productsBuildParameters: BuildParameters

    /// Parameters used when building tools (plugins and macros).
    let toolsBuildParameters: BuildParameters

    /// The API digester tool.
    let apiDigesterTool: SwiftAPIDigester

    /// The observabilityScope for emitting errors/warnings.
    let observabilityScope: ObservabilityScope

    init(
        baselineRevision: Revision,
        packageRoot: AbsolutePath,
        productsBuildParameters: BuildParameters,
        toolsBuildParameters: BuildParameters,
        apiDigesterTool: SwiftAPIDigester,
        observabilityScope: ObservabilityScope
    ) {
        self.baselineRevision = baselineRevision
        self.packageRoot = packageRoot
        self.productsBuildParameters = productsBuildParameters
        self.toolsBuildParameters = toolsBuildParameters
        self.apiDigesterTool = apiDigesterTool
        self.observabilityScope = observabilityScope
    }

    /// Emit the API baseline files and return the path to their directory.
    func emitAPIBaseline(
        for modulesToDiffInCurrentRevision: IdentifiableSet<ResolvedModule>,
        at baselineDir: AbsolutePath?,
        force: Bool,
        logLevel: Basics.Diagnostic.Severity,
        swiftCommandState: SwiftCommandState
    ) throws -> AbsolutePath {
        var modulesToDiffInCurrentRevision = modulesToDiffInCurrentRevision
        let apiDiffDir = productsBuildParameters.apiDiff
        let baselineDir = (baselineDir ?? apiDiffDir).appending(component: baselineRevision.identifier)
        let baselinePath: (ResolvedModule) -> AbsolutePath = { module in
            baselineDir.appending(component: module.c99name + ".json")
        }

        if !force {
            // Baselines which already exist don't need to be regenerated.
            modulesToDiffInCurrentRevision = modulesToDiffInCurrentRevision.filter {
                !swiftCommandState.fileSystem.exists(baselinePath($0))
            }
        }

        guard !modulesToDiffInCurrentRevision.isEmpty else {
            // If none of the baselines need to be regenerated, return.
            return baselineDir
        }

        // Setup a temporary directory where we can checkout and build the baseline treeish.
        let baselinePackageRoot = apiDiffDir.appending("\(baselineRevision.identifier)-checkout")
        if swiftCommandState.fileSystem.exists(baselinePackageRoot) {
            try swiftCommandState.fileSystem.removeFileTree(baselinePackageRoot)
        }

        // Clone the current package in a sandbox and checkout the baseline revision.
        let repositoryProvider = GitRepositoryProvider()
        let specifier = RepositorySpecifier(path: baselinePackageRoot)
        let workingCopy = try repositoryProvider.createWorkingCopy(
            repository: specifier,
            sourcePath: packageRoot,
            at: baselinePackageRoot,
            editable: false
        )

        try workingCopy.checkout(revision: baselineRevision)

        // Create the workspace for this package.
        let workspace = try Workspace(
            forRootPackage: baselinePackageRoot,
            cancellator: swiftCommandState.cancellator
        )

        let graph = try workspace.loadPackageGraph(
            rootPath: baselinePackageRoot,
            observabilityScope: self.observabilityScope
        )

        // FIXME: Indicate modules added or removed instead of ignoring
        // Only emit a baseline for modules that exists both in the previous
        // revision and the current revision of the package.
        let modulesToDiffInCurrentRevisionC99Names = Set(modulesToDiffInCurrentRevision.map(\.c99name))
        let modulesInPreviousRevision = graph.apiDigesterModules
        let modulesToDiff = modulesInPreviousRevision.filter {
            modulesToDiffInCurrentRevisionC99Names.contains($0.c99name)
        }

        // Abort if we weren't able to load the package graph.
        if observabilityScope.errorsReported {
            throw Diagnostics.fatalError
        }

        // Update the data path input build parameters so it's built in the sandbox.
        var productsBuildParameters = productsBuildParameters
        productsBuildParameters.dataPath = workspace.location.scratchDirectory

        // Build the baseline module.
        // FIXME: We need to implement the build tool invocation closure here so that build tool plugins work with the APIDigester. rdar://86112934
        let buildSystem = try swiftCommandState.createBuildSystem(
            explicitBuildSystem: .native,
            cacheBuildManifest: false,
            productsBuildParameters: productsBuildParameters,
            toolsBuildParameters: toolsBuildParameters,
            packageGraphLoader: { graph }
        )
        try buildSystem.build()

        // Dump the SDK JSON.
        try swiftCommandState.fileSystem.createDirectory(baselineDir, recursive: true)
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: Int(productsBuildParameters.workers))
        let errors = ThreadSafeArrayStore<Swift.Error>()
        for module in modulesToDiff {
            semaphore.wait()
            DispatchQueue.sharedConcurrent.async(group: group) {
                do {
                    try apiDigesterTool.emitAPIBaseline(
                        to: baselinePath(module),
                        for: module,
                        buildPlan: buildSystem.buildPlan
                    )
                } catch {
                    errors.append(error)
                }
                semaphore.signal()
            }
        }
        group.wait()

        for error in errors.get() {
            observabilityScope.emit(error)
        }
        if observabilityScope.errorsReported {
            throw Diagnostics.fatalError
        }

        return baselineDir
    }
}

/// A wrapper for the swift-api-digester tool.
public struct SwiftAPIDigester {
    /// The file system to use
    let fileSystem: FileSystem

    /// The absolute path to `swift-api-digester` in the toolchain.
    let tool: AbsolutePath

    init(fileSystem: FileSystem, tool: AbsolutePath) {
        self.fileSystem = fileSystem
        self.tool = tool
    }

    /// Emit an API baseline file for the specified module at the specified location.
    public func emitAPIBaseline(
        to outputPath: AbsolutePath,
        for module: ResolvedModule,
        buildPlan: BuildPlan
    ) throws {
        var args = [String]()
        args += try buildPlan.apiDigesterEmitBaselineArguments(for: module)

        // FIXME: everything here should be in apiDigesterEmitBaselineArguments
        args += ["-dump-sdk", "-compiler-style-diags"]
        args += ["-module", module.c99name, "-o", outputPath.pathString]

        let result = try runTool(args)

        if !self.fileSystem.exists(outputPath) {
            throw Error.failedToGenerateBaseline(module: module)
        }

        try self.fileSystem.readFileContents(outputPath).withData { data in
            if let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String:Any] {
                guard let abiRoot = jsonObject["ABIRoot"] as? [String:Any] else {
                    throw Error.failedToValidateBaseline(module: module)
                }

                guard let symbols = abiRoot["children"] as? NSArray, symbols.count > 0 else {
                    throw Error.noSymbolsInBaseline(module: module, toolOutput: try result.utf8Output())
                }
            }
        }

    }

    /// Compare the current package API to a provided baseline file.
    public func compareAPIToBaseline(
        at baselinePath: AbsolutePath,
        for module: ResolvedModule,
        buildPlan: SPMBuildCore.BuildPlan,
        except breakageAllowlistPath: AbsolutePath?
    ) throws -> ComparisonResult? {
        var args = [String]()
        args += try buildPlan.apiDigesterCompareBaselineArguments(for: module)

        // FIXME: everything here should be in apiDigesterCompareBaselineArguments
        args += [
            "-diagnose-sdk",
            "-baseline-path", baselinePath.pathString,
            "-module", module.c99name
        ]
        if let breakageAllowlistPath {
            args.append(contentsOf: ["-breakage-allowlist-path", breakageAllowlistPath.pathString])
        }

        return try? withTemporaryFile(deleteOnClose: false) { file in
            args.append(contentsOf: ["-serialize-diagnostics-path", file.path.pathString])
            try runTool(args)
            let contents = try self.fileSystem.readFileContents(file.path)
            guard contents.count > 0 else {
                return nil
            }
            let serializedDiagnostics = try SerializedDiagnostics(bytes: contents)
            let apiDigesterCategory = "api-digester-breaking-change"
            let apiBreakingChanges = serializedDiagnostics.diagnostics.filter { $0.category == apiDigesterCategory }
            let otherDiagnostics = serializedDiagnostics.diagnostics.filter { $0.category != apiDigesterCategory }
            return ComparisonResult(
                module: module,
                apiBreakingChanges: apiBreakingChanges,
                otherDiagnostics: otherDiagnostics)
        }
    }

    @discardableResult private func runTool(_ args: [String]) throws -> ProcessResult {
        let arguments = [tool.pathString] + args
        let process = TSCBasic.Process(
            arguments: arguments,
            outputRedirection: .collect(redirectStderr: true)
        )
        try process.launch()
        return try process.waitUntilExit()
    }
}

extension SwiftAPIDigester {
    public enum Error: Swift.Error, CustomStringConvertible {
        case failedToGenerateBaseline(module: ResolvedModule)
        case failedToValidateBaseline(module: ResolvedModule)
        case noSymbolsInBaseline(module: ResolvedModule, toolOutput: String)

        public var description: String {
            switch self {
            case .failedToGenerateBaseline(let module):
                return "failed to generate baseline for \(module.c99name)"
            case .failedToValidateBaseline(let module):
                return "failed to validate baseline for \(module.c99name)"
            case .noSymbolsInBaseline(let module, let toolOutput):
                return "baseline for \(module.c99name) contains no symbols, swift-api-digester output: \(toolOutput)"
            }
        }
    }
}

extension SwiftAPIDigester {
    /// The result of comparing a module's API to a provided baseline.
    public struct ComparisonResult {
        /// The module being diffed.
        var module: ResolvedModule
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
        dataPath.appending("apidiff")
    }
}

extension ModulesGraph {
    /// The list of modules that should be used as an input to the API digester.
    var apiDigesterModules: IdentifiableSet<ResolvedModule> {
        self.rootPackages
            .flatMap(\.products)
            .filter { $0.type.isLibrary }
            .flatMap(\.targets)
            // FIXME: this should be runnable on ClangTargets
            .filter { $0.underlying is SwiftTarget }
            .reduce(into: .init()) { $0.insert($1) }
    }
}

extension SerializedDiagnostics.SourceLocation {
    public var description: String {
        return "\(filename):\(line):\(column)"
    }
}

#if compiler(<6.0)
extension SerializedDiagnostics.SourceLocation: DiagnosticLocation {}
#else
extension SerializedDiagnostics.SourceLocation: @retroactive DiagnosticLocation {}
#endif
