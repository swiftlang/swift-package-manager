/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import TSCUtility

import PackageGraph
import PackageModel
import LLBuildManifest
import SPMLLBuild
import SPMBuildCore

public final class BuildOperation: PackageStructureDelegate, SPMBuildCore.BuildSystem {

    /// The build parameters.
    public let buildParameters: BuildParameters

    /// The diagnostics engine.
    public let diagnostics: DiagnosticsEngine

    /// The closure for loading the package graph.
    let packageGraphLoader: () throws -> PackageGraph

    /// The build delegate reference.
    private var buildDelegate: BuildDelegate?

    /// The build system reference.
    private var buildSystem: SPMLLBuild.BuildSystem?

    /// If build manifest caching should be enabled.
    public let useBuildManifestCaching: Bool

    /// The build plan that was computed, if any.
    public private(set) var buildPlan: BuildPlan?

    /// The build description resulting from planing.
    private var buildDescription: BuildDescription?

    /// The loaded package graph.
    private var packageGraph: PackageGraph?

    /// The stdout stream for the build delegate.
    let stdoutStream: OutputByteStream

    public var builtTestProducts: [BuiltTestProduct] {
        (try? getBuildDescription())?.builtTestProducts ?? []
    }

    public init(
        buildParameters: BuildParameters,
        useBuildManifestCaching: Bool,
        packageGraphLoader: @escaping () throws -> PackageGraph,
        diagnostics: DiagnosticsEngine,
        stdoutStream: OutputByteStream
    ) {
        self.buildParameters = buildParameters
        self.useBuildManifestCaching = useBuildManifestCaching
        self.packageGraphLoader = packageGraphLoader
        self.diagnostics = diagnostics
        self.stdoutStream = stdoutStream
    }

    public func getPackageGraph() throws -> PackageGraph {
        try memoize(to: &packageGraph) {
            try self.packageGraphLoader()
        }
    }

    /// Compute and return the latest build descroption.
    ///
    /// This will try skip build planning if build manifest caching is enabled
    /// and the package structure hasn't changed.
    public func getBuildDescription() throws -> BuildDescription {
        try memoize(to: &buildDescription) {
            if useBuildManifestCaching {
                try buildPackageStructure()

                // Return the build description that's on disk. We trust the above build to
                // update the build description when needed.
                do {
                    return try BuildDescription.load(from: buildParameters.buildDescriptionPath)
                } catch {
                    // Silently regnerate the build description if we failed to decode (which could happen
                    // because the existing file was created by different version of swiftpm).
                    if !(error is DecodingError) {
                        diagnostics.emit(warning: "failed to load the build description; running build planning: \(error)")
                    }
                }
            }

            // We need to perform actual planning if we reach here.
            return try plan()
        }
    }

    /// Cancel the active build operation.
    public func cancel() {
        buildSystem?.cancel()
    }

    /// Perform a build using the given build description and subset.
    public func build(subset: BuildSubset) throws {
        // Create the build system.
        let buildSystem = try createBuildSystem(with: getBuildDescription())
        self.buildSystem = buildSystem

        // Perform the build.
        let llbuildTarget = try computeLLBuildTargetName(for: subset)
        let success = buildSystem.build(target: llbuildTarget)

        buildDelegate?.progressAnimation.complete(success: success)
        guard success else { throw Diagnostics.fatalError }

        // Create backwards-compatibilty symlink to old build path.
        let oldBuildPath = buildParameters.dataPath.parentDirectory.appending(
            component: buildParameters.configuration.dirname
        )
        if localFileSystem.exists(oldBuildPath) {
            try localFileSystem.removeFileTree(oldBuildPath)
        }
        try createSymlink(oldBuildPath, pointingAt: buildParameters.buildPath, relative: true)
    }

    /// Compute the llbuild target name using the given subset.
    func computeLLBuildTargetName(for subset: BuildSubset) throws -> String {
        switch subset {
        case .allExcludingTests:
            return LLBuildManifestBuilder.TargetKind.main.targetName
        case .allIncludingTests:
            return LLBuildManifestBuilder.TargetKind.test.targetName
        default:
            // FIXME: This is super unfortunate that we might need to load the package graph.
            let graph = try getPackageGraph()
            if let result = subset.llbuildTargetName(
                for: graph,
                diagnostics: diagnostics,
                config: buildParameters.configuration.dirname
            ) {
                return result
            }
            throw Diagnostics.fatalError
        }
    }

    /// Create the build plan and return the build description.
    private func plan() throws -> BuildDescription {
        let graph = try getPackageGraph()
        let plan = try BuildPlan(
            buildParameters: buildParameters,
            graph: graph,
            diagnostics: diagnostics
        )
        self.buildPlan = plan

        return try BuildDescription.create(with: plan)
    }

    /// Build the package structure target.
    private func buildPackageStructure() throws {
        let buildSystem = try createBuildSystem(with: nil)
        self.buildSystem = buildSystem

        // Build the package structure target which will re-generate the llbuild manifest, if necessary.
        if !buildSystem.build(target: "PackageStructure") {
            throw Diagnostics.fatalError
        }
    }

    /// Create the build system using the given build description.
    ///
    /// The build description should only be omitted when creating the build system for
    /// building the package structure target.
    private func createBuildSystem(
        with buildDescription: BuildDescription?
    ) throws -> SPMLLBuild.BuildSystem {
        // Figure out which progress bar we have to use during the build.
        let isVerbose = verbosity != .concise
        let progressAnimation: ProgressAnimationProtocol = isVerbose
            ? MultiLineNinjaProgressAnimation(stream: self.stdoutStream)
            : NinjaProgressAnimation(stream: self.stdoutStream)

        let bctx = BuildExecutionContext(
            buildParameters,
            buildDescription: buildDescription,
            packageStructureDelegate: self
        )

        // Create the build delegate.
        let buildDelegate = BuildDelegate(
            bctx: bctx,
            diagnostics: diagnostics,
            outputStream: self.stdoutStream,
            progressAnimation: progressAnimation
        )
        self.buildDelegate = buildDelegate
        buildDelegate.isVerbose = isVerbose

        let databasePath = buildParameters.dataPath.appending(component: "build.db").pathString
        let buildSystem = BuildSystem(
            buildFile: buildParameters.llbuildManifest.pathString,
            databaseFile: databasePath,
            delegate: buildDelegate,
            schedulerLanes: buildParameters.jobs
        )
        buildDelegate.onCommmandFailure = { buildSystem.cancel() }

        return buildSystem
    }

    public func packageStructureChanged() -> Bool {
        do {
            _ = try plan()
        }
        catch Diagnostics.fatalError {
            return false
        }
        catch {
            diagnostics.emit(error)
            return false
        }
        return true
    }
}

extension BuildDescription {
    static func create(with plan: BuildPlan) throws -> BuildDescription {
        // Generate the llbuild manifest.
        let llbuild = LLBuildManifestBuilder(plan)
        try llbuild.generateManifest(at: plan.buildParameters.llbuildManifest)

        let swiftCommands = llbuild.manifest.getCmdToolMap(kind: SwiftCompilerTool.self)
        let swiftFrontendCommands = llbuild.manifest.getCmdToolMap(kind: SwiftFrontendTool.self)
        let testDiscoveryCommands = llbuild.manifest.getCmdToolMap(kind: TestDiscoveryTool.self)
        let copyCommands = llbuild.manifest.getCmdToolMap(kind: CopyTool.self)

        // Create the build description.
        let buildDescription = BuildDescription(
            plan: plan,
            swiftCommands: swiftCommands,
            swiftFrontendCommands: swiftFrontendCommands,
            testDiscoveryCommands: testDiscoveryCommands,
            copyCommands: copyCommands
        )
        try localFileSystem.createDirectory(
            plan.buildParameters.buildDescriptionPath.parentDirectory,
            recursive: true
        )
        try buildDescription.write(to: plan.buildParameters.buildDescriptionPath)
        return buildDescription
    }
}

extension BuildSubset {
    /// Returns the name of the llbuild target that corresponds to the build subset.
    func llbuildTargetName(for graph: PackageGraph, diagnostics: DiagnosticsEngine, config: String)
        -> String?
    {
        switch self {
        case .allExcludingTests:
            return LLBuildManifestBuilder.TargetKind.main.targetName
        case .allIncludingTests:
            return LLBuildManifestBuilder.TargetKind.test.targetName
        case .product(let productName):
            guard let product = graph.allProducts.first(where: { $0.name == productName }) else {
                diagnostics.emit(error: "no product named '\(productName)'")
                return nil
            }
            // If the product is automatic, we build the main target because automatic products
            // do not produce a binary right now.
            if product.type == .library(.automatic) {
                diagnostics.emit(
                    warning:
                        "'--product' cannot be used with the automatic product '\(productName)'; building the default target instead"
                )
                return LLBuildManifestBuilder.TargetKind.main.targetName
            }
            return product.getLLBuildTargetName(config: config)
        case .target(let targetName):
            guard let target = graph.allTargets.first(where: { $0.name == targetName }) else {
                diagnostics.emit(error: "no target named '\(targetName)'")
                return nil
            }
            return target.getLLBuildTargetName(config: config)
        }
    }
}
