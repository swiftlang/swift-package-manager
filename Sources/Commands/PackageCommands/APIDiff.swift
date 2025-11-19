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

import ArgumentParser
import Basics
import CoreCommands
import Dispatch
import PackageGraph
import PackageModel
import SourceControl
import SPMBuildCore
import TSCBasic
import TSCUtility
import _Concurrency
import Workspace

struct DeprecatedAPIDiff: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "experimental-api-diff",
        abstract: "Deprecated - use `swift package diagnose-api-breaking-changes` instead",
        shouldDisplay: false,
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
    )

    @Argument(parsing: .captureForPassthrough)
    var args: [String] = []

    func run() throws {
        print("`swift package experimental-api-diff` has been renamed to `swift package diagnose-api-breaking-changes`")
        throw ExitCode.failure
    }
}

struct APIDiff: AsyncSwiftCommand {
    static let configuration = CommandConfiguration(
        commandName: "diagnose-api-breaking-changes",
        abstract: "Diagnose API-breaking changes to Swift modules in a package.",
        discussion: """
            The diagnose-api-breaking-changes command can be used to compare the Swift API of \
            a package to a baseline revision, diagnosing any breaking changes which have \
            been introduced. By default, it compares every Swift module from the baseline \
            revision which is part of a library product. For packages with many targets, this \
            behavior may be undesirable as the comparison can be slow. \
            The `--products` and `--targets` options may be used to restrict the scope of \
            the comparison.
            """,
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
    )

    @OptionGroup(visibility: .hidden)
    var globalOptions: GlobalOptions

    @Option(
        help: """
            The path to a text file containing breaking changes which should be ignored by the API comparison. \
            Each ignored breaking change in the file should appear on its own line and contain the exact message \
            to be ignored (e.g. 'API breakage: func foo() has been removed').
            """
    )
    var breakageAllowlistPath: Basics.AbsolutePath?

    @Argument(help: "The baseline treeish to compare to (for example, a commit hash, branch name, tag, and so on).")
    var treeish: String

    @Option(
        parsing: .upToNextOption,
        help: "One or more products to include in the API comparison. If present, only the specified products (and any targets specified using `--targets`) will be compared."
    )
    var products: [String] = []

    @Option(
        parsing: .upToNextOption,
        help: "One or more targets to include in the API comparison. If present, only the specified targets (and any products specified using `--products`) will be compared."
    )
    var targets: [String] = []

    @Option(
        name: .customLong("baseline-dir"),
        help: "The path to a directory used to store API baseline files. If unspecified, a temporary directory will be used."
    )
    var overrideBaselineDir: Basics.AbsolutePath?

    @Flag(help: "Regenerate the API baseline, even if an existing one is available.")
    var regenerateBaseline: Bool = false

    func run(_ swiftCommandState: SwiftCommandState) async throws {
        let packageRoot = try globalOptions.locations.packageDirectory ?? swiftCommandState.getPackageRoot()
        let repository = GitRepository(path: packageRoot)
        let baselineRevision = try repository.resolveRevision(identifier: treeish)

        let baselineDir = try overrideBaselineDir?.appending(component: baselineRevision.identifier) ?? swiftCommandState.productsBuildParameters.apiDiff.appending(component: "\(baselineRevision.identifier)-baselines")
        let packageGraph = try await swiftCommandState.loadPackageGraph()
        let modulesToDiff = try Self.determineModulesToDiff(
            packageGraph: packageGraph,
            productNames: products,
            targetNames: targets,
            observabilityScope: swiftCommandState.observabilityScope,
            diagnoseMissingNames: true,
        )

        if swiftCommandState.options.build.buildSystem == .swiftbuild {
            try await runWithIntegratedAPIDigesterSupport(
                swiftCommandState,
                baselineRevision: baselineRevision,
                baselineDir: baselineDir,
                modulesToDiff: modulesToDiff
            )
        } else {
            let buildSystem = try await swiftCommandState.createBuildSystem(
                cacheBuildManifest: false,
            )
            try await runWithSwiftPMCoordinatedDiffing(
                swiftCommandState,
                buildSystem: buildSystem,
                baselineRevision: baselineRevision,
                modulesToDiff: modulesToDiff
            )
        }
    }

    private func runWithSwiftPMCoordinatedDiffing(_ swiftCommandState: SwiftCommandState, buildSystem: any BuildSystem, baselineRevision: Revision, modulesToDiff: Set<String>) async throws {
        let apiDigesterPath = try swiftCommandState.getTargetToolchain().getSwiftAPIDigester()
        let apiDigesterTool = SwiftAPIDigester(fileSystem: swiftCommandState.fileSystem, tool: apiDigesterPath)

        // Build the current package.
        let buildResult = try await buildSystem.build(subset: .allExcludingTests, buildOutputs: [.buildPlan])
        guard let buildPlan = buildResult.buildPlan else {
            throw ExitCode.failure
        }

        // Dump JSON for the baseline package.
        let baselineDumper = try APIDigesterBaselineDumper(
            baselineRevision: baselineRevision,
            packageRoot: swiftCommandState.getPackageRoot(),
            productsBuildParameters: buildPlan.destinationBuildParameters,
            toolsBuildParameters: buildPlan.toolsBuildParameters,
            apiDigesterTool: apiDigesterTool,
            observabilityScope: swiftCommandState.observabilityScope
        )

        let baselineDir = try await baselineDumper.emitAPIBaseline(
            for: modulesToDiff,
            at: overrideBaselineDir,
            force: regenerateBaseline,
            logLevel: swiftCommandState.logLevel,
            swiftCommandState: swiftCommandState
        )

        var skippedModules: Set<String> = []

        let results = await withTaskGroup(of: SwiftAPIDigester.ComparisonResult?.self, returning: [SwiftAPIDigester.ComparisonResult].self) { taskGroup in

            for module in modulesToDiff {
                let moduleBaselinePath = baselineDir.appending("\(module).json")
                guard swiftCommandState.fileSystem.exists(moduleBaselinePath) else {
                    print("\nSkipping \(module) because it does not exist in the baseline")
                    skippedModules.insert(module)
                    continue
                }
                taskGroup.addTask {
                    do {
                        if let comparisonResult = try apiDigesterTool.compareAPIToBaseline(
                            at: moduleBaselinePath,
                            for: module,
                            buildPlan: buildPlan,
                            except: breakageAllowlistPath
                        ) {
                            return comparisonResult
                        }
                    } catch {
                        swiftCommandState.observabilityScope.emit(error: "failed to compare API to baseline", underlyingError: error)
                    }
                    return nil
                }
            }
            var results = [SwiftAPIDigester.ComparisonResult]()
            for await result in taskGroup {
                guard let result else { continue }
                results.append(result)
            }
            return results
        }

        let failedModules =
            modulesToDiff
            .subtracting(skippedModules)
            .subtracting(results.map(\.moduleName))
        for failedModule in failedModules {
            swiftCommandState.observabilityScope.emit(error: "failed to read API digester output for \(failedModule)")
        }

        for result in results {
            try self.printComparisonResult(result, observabilityScope: swiftCommandState.observabilityScope)
        }

        guard failedModules.isEmpty && results.allSatisfy(\.hasNoAPIBreakingChanges) else {
            throw ExitCode.failure
        }
    }

    private func runWithIntegratedAPIDigesterSupport(_ swiftCommandState: SwiftCommandState, baselineRevision: Revision, baselineDir: Basics.AbsolutePath, modulesToDiff: Set<String>) async throws {
        // Build the baseline revision to generate baseline files.
        let modulesWithBaselines = try await generateAPIBaselineUsingIntegratedAPIDigesterSupport(swiftCommandState, baselineRevision: baselineRevision, baselineDir: baselineDir, modulesNeedingBaselines: modulesToDiff)

        // Build the package and run a comparison agains the baselines.
        var productsBuildParameters = try swiftCommandState.productsBuildParameters
        productsBuildParameters.apiDigesterMode = .compareToBaselines(
            baselinesDirectory: baselineDir,
            modulesToCompare: modulesWithBaselines,
            breakageAllowListPath: breakageAllowlistPath
        )
        let delegate = DiagnosticsCapturingBuildSystemDelegate()
        let buildSystem = try await swiftCommandState.createBuildSystem(
            cacheBuildManifest: false,
            productsBuildParameters: productsBuildParameters,
            delegate: delegate
        )
        try await buildSystem.build()

        // Report the results of the comparison.
        var comparisonResults: [SwiftAPIDigester.ComparisonResult] = []
        for (targetName, diagnosticPaths) in delegate.serializedDiagnosticsPathsByTarget {
            guard let targetName, !diagnosticPaths.isEmpty else {
                continue
            }
            var apiBreakingChanges: [SerializedDiagnostics.Diagnostic] = []
            var otherDiagnostics: [SerializedDiagnostics.Diagnostic] = []
            for path in diagnosticPaths {
                let contents = try swiftCommandState.fileSystem.readFileContents(path)
                guard contents.count > 0 else {
                    continue
                }
                let serializedDiagnostics = try SerializedDiagnostics(bytes: contents)
                let apiDigesterCategory = "api-digester-breaking-change"
                apiBreakingChanges.append(contentsOf: serializedDiagnostics.diagnostics.filter { $0.category == apiDigesterCategory })
                otherDiagnostics.append(contentsOf: serializedDiagnostics.diagnostics.filter { $0.category != apiDigesterCategory })
            }
            let result = SwiftAPIDigester.ComparisonResult(
                moduleName: targetName,
                apiBreakingChanges: apiBreakingChanges,
                otherDiagnostics: otherDiagnostics
            )
            comparisonResults.append(result)
        }

        var detectedBreakingChange = false
        for result in comparisonResults.sorted(by: { $0.moduleName < $1.moduleName }) {
            if result.hasNoAPIBreakingChanges && !modulesToDiff.contains(result.moduleName) {
                continue
            }
            try printComparisonResult(result, observabilityScope: swiftCommandState.observabilityScope)
            detectedBreakingChange = detectedBreakingChange || !result.hasNoAPIBreakingChanges
        }

        for module in modulesToDiff.subtracting(modulesWithBaselines) {
            print("\nSkipping \(module) because it does not exist in the baseline")
        }

        if detectedBreakingChange {
            throw ExitCode(1)
        }
    }

    private func generateAPIBaselineUsingIntegratedAPIDigesterSupport(_ swiftCommandState: SwiftCommandState, baselineRevision: Revision, baselineDir: Basics.AbsolutePath, modulesNeedingBaselines: Set<String>) async throws -> Set<String> {
        // Setup a temporary directory where we can checkout and build the baseline treeish.
        let baselinePackageRoot = try swiftCommandState.productsBuildParameters.apiDiff.appending("\(baselineRevision.identifier)-checkout")
        if swiftCommandState.fileSystem.exists(baselinePackageRoot) {
            try swiftCommandState.fileSystem.removeFileTree(baselinePackageRoot)
        }
        if regenerateBaseline && swiftCommandState.fileSystem.exists(baselineDir) {
            try swiftCommandState.fileSystem.removeFileTree(baselineDir)
        }

        // Clone the current package in a sandbox and checkout the baseline revision.
        let repositoryProvider = GitRepositoryProvider()
        let specifier = RepositorySpecifier(path: baselinePackageRoot)
        let workingCopy = try await repositoryProvider.createWorkingCopy(
            repository: specifier,
            sourcePath: swiftCommandState.getPackageRoot(),
            at: baselinePackageRoot,
            editable: false
        )

        try workingCopy.checkout(revision: baselineRevision)

        // Create the workspace for this package.
        let workspace = try Workspace(
            forRootPackage: baselinePackageRoot,
            cancellator: swiftCommandState.cancellator
        )

        let graph = try await workspace.loadPackageGraph(
            rootPath: baselinePackageRoot,
            observabilityScope: swiftCommandState.observabilityScope
        )

        let baselineModules = try Self.determineModulesToDiff(
            packageGraph: graph,
            productNames: products,
            targetNames: targets,
            observabilityScope: swiftCommandState.observabilityScope,
            diagnoseMissingNames: false
        )

        // Don't emit a baseline for a module that didn't exist yet in this revision.
        var modulesNeedingBaselines = modulesNeedingBaselines
        modulesNeedingBaselines.formIntersection(graph.apiDigesterModules)

        // Abort if we weren't able to load the package graph.
        if swiftCommandState.observabilityScope.errorsReported {
            throw Diagnostics.fatalError
        }

        // Update the data path input build parameters so it's built in the sandbox.
        var productsBuildParameters = try swiftCommandState.productsBuildParameters
        productsBuildParameters.dataPath = workspace.location.scratchDirectory
        productsBuildParameters.apiDigesterMode = .generateBaselines(baselinesDirectory: baselineDir, modulesRequestingBaselines: modulesNeedingBaselines)

        // Build the baseline module.
        // FIXME: We need to implement the build tool invocation closure here so that build tool plugins work with the APIDigester. rdar://86112934
        let buildSystem = try await swiftCommandState.createBuildSystem(
            cacheBuildManifest: false,
            productsBuildParameters: productsBuildParameters,
            packageGraphLoader: { graph }
        )
        try await buildSystem.build()
        return baselineModules
    }

    private static func determineModulesToDiff(packageGraph: ModulesGraph, productNames: [String], targetNames: [String], observabilityScope: ObservabilityScope, diagnoseMissingNames: Bool) throws -> Set<String> {
        var modulesToDiff: Set<String> = []
        if productNames.isEmpty && targetNames.isEmpty {
            modulesToDiff.formUnion(packageGraph.apiDigesterModules)
        } else {
            for productName in productNames {
                guard
                    let product = packageGraph
                        .rootPackages
                        .flatMap(\.products)
                        .first(where: { $0.name == productName })
                else {
                    if diagnoseMissingNames {
                        observabilityScope.emit(error: "no such product '\(productName)'")
                    }
                    continue
                }
                guard product.type.isLibrary else {
                    if diagnoseMissingNames {
                        observabilityScope.emit(error: "'\(productName)' is not a library product")
                    }
                    continue
                }
                modulesToDiff.formUnion(product.modules.filter { $0.underlying is SwiftModule }.map(\.c99name))
            }
            for targetName in targetNames {
                guard
                    let target = packageGraph
                        .rootPackages
                        .flatMap(\.modules)
                        .first(where: { $0.name == targetName })
                else {
                    if diagnoseMissingNames {
                        observabilityScope.emit(error: "no such target '\(targetName)'")
                    }
                    continue
                }
                guard target.type == .library else {
                    if diagnoseMissingNames {
                        observabilityScope.emit(error: "'\(targetName)' is not a library target")
                    }
                    continue
                }
                guard target.underlying is SwiftModule else {
                    if diagnoseMissingNames {
                        observabilityScope.emit(error: "'\(targetName)' is not a Swift language target")
                    }
                    continue
                }
                modulesToDiff.insert(target.c99name)
            }
            guard !observabilityScope.errorsReported else {
                throw ExitCode.failure
            }
        }
        return modulesToDiff
    }

    private func printComparisonResult(
        _ comparisonResult: SwiftAPIDigester.ComparisonResult,
        observabilityScope: ObservabilityScope
    ) throws {
        for diagnostic in comparisonResult.otherDiagnostics {
            let metadata = try diagnostic.location.map { location -> ObservabilityMetadata in
                var metadata = ObservabilityMetadata()
                metadata.fileLocation = .init(
                    try .init(validating: location.filename),
                    line: location.line < Int.max ? Int(location.line) : .none
                )
                return metadata
            }

            switch diagnostic.level {
            case .error, .fatal:
                observabilityScope.emit(error: diagnostic.text, metadata: metadata)
            case .warning:
                observabilityScope.emit(warning: diagnostic.text, metadata: metadata)
            case .note:
                observabilityScope.emit(info: diagnostic.text, metadata: metadata)
            case .remark:
                observabilityScope.emit(info: diagnostic.text, metadata: metadata)
            case .ignored:
                break
            }
        }

        let moduleName = comparisonResult.moduleName
        if comparisonResult.apiBreakingChanges.isEmpty {
            print("\nNo breaking changes detected in \(moduleName)")
        } else {
            let count = comparisonResult.apiBreakingChanges.count
            print("\n\(count) breaking \(count > 1 ? "changes" : "change") detected in \(moduleName):")
            for change in comparisonResult.apiBreakingChanges {
                print("  💔 \(change.text)")
            }
        }
    }
}
