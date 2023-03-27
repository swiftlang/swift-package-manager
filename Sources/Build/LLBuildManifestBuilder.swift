//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2015-2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@_implementationOnly import DriverSupport
import LLBuildManifest
import PackageGraph
import PackageModel
import SPMBuildCore
@_implementationOnly import SwiftDriver
import TSCBasic

public class LLBuildManifestBuilder {
    public enum TargetKind {
        case main
        case test

        public var targetName: String {
            switch self {
            case .main: return "main"
            case .test: return "test"
            }
        }
    }

    /// The build plan to work on.
    public let plan: BuildPlan

    /// Whether to sandbox commands from build tool plugins.
    public let disableSandboxForPluginCommands: Bool

    /// File system reference.
    private let fileSystem: FileSystem

    /// ObservabilityScope with which to emit diagnostics
    public let observabilityScope: ObservabilityScope

    public private(set) var manifest: BuildManifest = .init()

    var buildConfig: String { self.buildParameters.configuration.dirname }
    var buildParameters: BuildParameters { self.plan.buildParameters }
    var buildEnvironment: BuildEnvironment { self.buildParameters.buildEnvironment }

    /// Create a new builder with a build plan.
    public init(
        _ plan: BuildPlan,
        disableSandboxForPluginCommands: Bool = false,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) {
        self.plan = plan
        self.disableSandboxForPluginCommands = disableSandboxForPluginCommands
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope
    }

    // MARK: - Generate Manifest

    /// Generate manifest at the given path.
    @discardableResult
    public func generateManifest(at path: AbsolutePath) throws -> BuildManifest {
        self.manifest.createTarget(TargetKind.main.targetName)
        self.manifest.createTarget(TargetKind.test.targetName)
        self.manifest.defaultTarget = TargetKind.main.targetName

        addPackageStructureCommand()
        addBinaryDependencyCommands()
        if self.buildParameters.useExplicitModuleBuild {
            // Explicit module builds use the integrated driver directly and
            // require that every target's build jobs specify its dependencies explicitly to plan
            // its build.
            // Currently behind:
            // --experimental-explicit-module-build
            try addTargetsToExplicitBuildManifest()
        } else {
            // Create commands for all target descriptions in the plan.
            for (_, description) in self.plan.targetMap {
                switch description {
                case .swift(let desc):
                    try self.createSwiftCompileCommand(desc)
                case .clang(let desc):
                    try self.createClangCompileCommand(desc)
                }
            }
        }

        try self.addTestDiscoveryGenerationCommand()
        try self.addTestEntryPointGenerationCommand()

        // Create command for all products in the plan.
        for (_, description) in self.plan.productMap {
            try self.createProductCommand(description)
        }

        try ManifestWriter(fileSystem: self.fileSystem).write(self.manifest, at: path)
        return self.manifest
    }

    func addNode(_ node: Node, toTarget targetKind: TargetKind) {
        self.manifest.addNode(node, toTarget: targetKind.targetName)
    }
}

// MARK: - Package Structure

extension LLBuildManifestBuilder {
    private func addPackageStructureCommand() {
        let inputs = self.plan.graph.rootPackages.flatMap { package -> [Node] in
            var inputs = package.targets
                .map(\.sources.root)
                .sorted()
                .map { Node.directoryStructure($0) }

            // Add the output paths of any prebuilds that were run, so that we redo the plan if they change.
            var derivedSourceDirPaths: [AbsolutePath] = []
            for result in plan.prebuildCommandResults.values.flatMap({ $0 }) {
                derivedSourceDirPaths.append(contentsOf: result.outputDirectories)
            }
            inputs.append(contentsOf: derivedSourceDirPaths.sorted().map { Node.directoryStructure($0) })

            // FIXME: Need to handle version-specific manifests.
            inputs.append(file: package.manifest.path)

            // FIXME: This won't be the location of Package.resolved for multiroot packages.
            inputs.append(file: package.path.appending("Package.resolved"))

            // FIXME: Add config file as an input

            return inputs
        }

        let name = "PackageStructure"
        let output: Node = .virtual(name)

        self.manifest.addPkgStructureCmd(
            name: name,
            inputs: inputs,
            outputs: [output]
        )
        self.manifest.addNode(output, toTarget: name)
    }
}

// MARK: - Binary Dependencies

extension LLBuildManifestBuilder {
    // Creates commands for copying all binary artifacts depended on in the plan.
    private func addBinaryDependencyCommands() {
        let binaryPaths = Set(plan.targetMap.values.flatMap(\.libraryBinaryPaths))
        for binaryPath in binaryPaths {
            let destination = destinationPath(forBinaryAt: binaryPath)
            addCopyCommand(from: binaryPath, to: destination)
        }
    }
}

// MARK: - Resources Bundle

extension LLBuildManifestBuilder {
    /// Adds command for creating the resources bundle of the given target.
    ///
    /// Returns the virtual node that will build the entire bundle.
    private func createResourcesBundle(
        for target: TargetBuildDescription
    ) -> Node? {
        guard let bundlePath = target.bundlePath else { return nil }

        var outputs: [Node] = []

        let infoPlistDestination = RelativePath("Info.plist")

        // Create a copy command for each resource file.
        for resource in target.resources {
            switch resource.rule {
            case .copy, .process:
                let destination = bundlePath.appending(resource.destination)
                let (_, output) = addCopyCommand(from: resource.path, to: destination)
                outputs.append(output)
            case .embedInCode:
                break
            }
        }

        // Create a copy command for the Info.plist if a resource with the same name doesn't exist yet.
        if let infoPlistPath = target.resourceBundleInfoPlistPath {
            let destination = bundlePath.appending(infoPlistDestination)
            let (_, output) = addCopyCommand(from: infoPlistPath, to: destination)
            outputs.append(output)
        }

        let cmdName = target.target.getLLBuildResourcesCmdName(config: self.buildConfig)
        self.manifest.addPhonyCmd(name: cmdName, inputs: outputs, outputs: [.virtual(cmdName)])

        return .virtual(cmdName)
    }
}

// MARK: - Compile Swift

extension LLBuildManifestBuilder {
    /// Create a llbuild target for a Swift target description.
    private func createSwiftCompileCommand(
        _ target: SwiftTargetBuildDescription
    ) throws {
        // Inputs.
        let inputs = try self.computeSwiftCompileCmdInputs(target)

        // Outputs.
        let objectNodes = try target.objects.map(Node.file)
        let moduleNode = Node.file(target.moduleOutputPath)
        let cmdOutputs = objectNodes + [moduleNode]

        if self.buildParameters.useIntegratedSwiftDriver {
            try self.addSwiftCmdsViaIntegratedDriver(
                target,
                inputs: inputs,
                objectNodes: objectNodes,
                moduleNode: moduleNode
            )
        } else if self.buildParameters.emitSwiftModuleSeparately {
            try self.addSwiftCmdsEmitSwiftModuleSeparately(
                target,
                inputs: inputs,
                objectNodes: objectNodes,
                moduleNode: moduleNode
            )
        } else {
            try self.addCmdWithBuiltinSwiftTool(target, inputs: inputs, cmdOutputs: cmdOutputs)
        }

        self.addTargetCmd(target, cmdOutputs: cmdOutputs)
        try self.addModuleWrapCmd(target)
    }

    private func addSwiftCmdsViaIntegratedDriver(
        _ target: SwiftTargetBuildDescription,
        inputs: [Node],
        objectNodes: [Node],
        moduleNode: Node
    ) throws {
        // Use the integrated Swift driver to compute the set of frontend
        // jobs needed to build this Swift target.
        var commandLine = try target.emitCommandLine()
        commandLine.append("-driver-use-frontend-path")
        commandLine.append(self.buildParameters.toolchain.swiftCompilerPath.pathString)
        // FIXME: At some point SwiftPM should provide its own executor for
        // running jobs/launching processes during planning
        let resolver = try ArgsResolver(fileSystem: target.fileSystem)
        let executor = SPMSwiftDriverExecutor(
            resolver: resolver,
            fileSystem: target.fileSystem,
            env: ProcessEnv.vars
        )
        var driver = try Driver(
            args: commandLine,
            diagnosticsOutput: .handler(self.observabilityScope.makeDiagnosticsHandler()),
            fileSystem: self.fileSystem,
            executor: executor
        )
        let jobs = try driver.planBuild()
        try self.addSwiftDriverJobs(
            for: target,
            jobs: jobs,
            inputs: inputs,
            resolver: resolver,
            isMainModule: { driver.isExplicitMainModuleJob(job: $0) }
        )
    }

    private func addSwiftDriverJobs(
        for targetDescription: SwiftTargetBuildDescription,
        jobs: [Job],
        inputs: [Node],
        resolver: ArgsResolver,
        isMainModule: (Job) -> Bool,
        uniqueExplicitDependencyTracker: UniqueExplicitDependencyJobTracker? = nil
    ) throws {
        // Add build jobs to the manifest
        for job in jobs {
            let tool = try resolver.resolve(.path(job.tool))
            let commandLine = try job.commandLine.map { try resolver.resolve($0) }
            let arguments = [tool] + commandLine

            // Check if an explicit pre-build dependency job has already been
            // added as a part of this build.
            if let uniqueExplicitDependencyTracker,
               job.isExplicitDependencyPreBuildJob
            {
                if try !uniqueExplicitDependencyTracker.registerExplicitDependencyBuildJob(job) {
                    // This is a duplicate of a previously-seen identical job.
                    // Skip adding it to the manifest
                    continue
                }
            }

            let jobInputs = try job.inputs.map { try $0.resolveToNode(fileSystem: self.fileSystem) }
            let jobOutputs = try job.outputs.map { try $0.resolveToNode(fileSystem: self.fileSystem) }

            // Add target dependencies as inputs to the main module build command.
            //
            // Jobs for a target's intermediate build artifacts, such as PCMs or
            // modules built from a .swiftinterface, do not have a
            // dependency on cross-target build products. If multiple targets share
            // common intermediate dependency modules, such dependencies can lead
            // to cycles in the resulting manifest.
            var manifestNodeInputs: [Node] = []
            if self.buildParameters.useExplicitModuleBuild && !isMainModule(job) {
                manifestNodeInputs = jobInputs
            } else {
                manifestNodeInputs = (inputs + jobInputs).uniqued()
            }

            guard let firstJobOutput = jobOutputs.first else {
                throw InternalError("unknown first JobOutput")
            }

            let moduleName = targetDescription.target.c99name
            let packageName = targetDescription.package.identity.description.spm_mangledToC99ExtendedIdentifier()
            let description = job.description
            if job.kind.isSwiftFrontend {
                self.manifest.addSwiftFrontendCmd(
                    name: firstJobOutput.name,
                    moduleName: moduleName,
                    packageName: packageName,
                    description: description,
                    inputs: manifestNodeInputs,
                    outputs: jobOutputs,
                    arguments: arguments
                )
            } else {
                self.manifest.addShellCmd(
                    name: firstJobOutput.name,
                    description: description,
                    inputs: manifestNodeInputs,
                    outputs: jobOutputs,
                    arguments: arguments
                )
            }
        }
    }

    // Building a Swift module in Explicit Module Build mode requires passing all of its module
    // dependencies as explicit arguments to the build command. Thus, building a SwiftPM package
    // with multiple inter-dependent targets thus requires that each target’s build job must
    // have its target dependencies’ modules passed into it as explicit module dependencies.
    // Because none of the targets have been built yet, a given target's dependency scanning
    // action will not be able to discover its target dependencies' modules. Instead, it is
    // SwiftPM's responsibility to communicate to the driver, when planning a given target's
    // build, that this target has dependencies that are other targets, along with a list of
    // future artifacts of such dependencies (.swiftmodule and .pcm files).
    // The driver will then use those artifacts as explicit inputs to its module’s build jobs.
    //
    // Consider an example SwiftPM package with two targets: target B, and target A, where A
    // depends on B:
    // SwiftPM will process targets in a topological order and “bubble-up” each target’s
    // inter-module dependency graph to its dependencies. First, SwiftPM will process B, and be
    // able to plan its full build because it does not have any target dependencies. Then the
    // driver is tasked with planning a build for A. SwiftPM will pass as input to the driver
    // the module dependency graph of its target’s dependencies, in this case, just the
    // dependency graph of B. The driver is then responsible for the necessary post-processing
    // to merge the dependency graphs and plan the build for A, using artifacts of B as explicit
    // inputs.
    public func addTargetsToExplicitBuildManifest() throws {
        // Sort the product targets in topological order in order to collect and "bubble up"
        // their respective dependency graphs to the depending targets.
        let nodes: [ResolvedTarget.Dependency] = self.plan.targetMap.keys.map {
            ResolvedTarget.Dependency.target($0, conditions: [])
        }
        let allPackageDependencies = try topologicalSort(nodes, successors: { $0.dependencies })
        // Instantiate the inter-module dependency oracle which will cache commonly-scanned
        // modules across targets' Driver instances.
        let dependencyOracle = InterModuleDependencyOracle()

        // Explicit dependency pre-build jobs may be common to multiple targets.
        // We de-duplicate them here to avoid adding identical entries to the
        // downstream LLBuild manifest
        let explicitDependencyJobTracker = UniqueExplicitDependencyJobTracker()

        // Create commands for all target descriptions in the plan.
        for dependency in allPackageDependencies.reversed() {
            guard case .target(let target, _) = dependency else {
                // Product dependency build jobs are added after the fact.
                // Targets that depend on product dependencies will expand the corresponding
                // product into its constituent targets.
                continue
            }
            guard target.underlyingTarget.type != .systemModule,
                  target.underlyingTarget.type != .binary
            else {
                // Much like non-Swift targets, system modules will consist of a modulemap
                // somewhere in the filesystem, with the path to that module being either
                // manually-specified or computed based on the system module type (apt, brew).
                // Similarly, binary targets will bring in an .xcframework, the contents of
                // which will be exposed via search paths.
                //
                // In both cases, the dependency scanning action in the driver will be automatically
                // be able to detect such targets' modules.
                continue
            }
            guard let description = plan.targetMap[target] else {
                throw InternalError("Expected description for target \(target)")
            }
            switch description {
            case .swift(let desc):
                try self.createExplicitSwiftTargetCompileCommand(
                    description: desc,
                    dependencyOracle: dependencyOracle,
                    explicitDependencyJobTracker: explicitDependencyJobTracker
                )
            case .clang(let desc):
                try self.createClangCompileCommand(desc)
            }
        }
    }

    private func createExplicitSwiftTargetCompileCommand(
        description: SwiftTargetBuildDescription,
        dependencyOracle: InterModuleDependencyOracle,
        explicitDependencyJobTracker: UniqueExplicitDependencyJobTracker?
    ) throws {
        // Inputs.
        let inputs = try self.computeSwiftCompileCmdInputs(description)

        // Outputs.
        let objectNodes = try description.objects.map(Node.file)
        let moduleNode = Node.file(description.moduleOutputPath)
        let cmdOutputs = objectNodes + [moduleNode]

        // Commands.
        try addExplicitBuildSwiftCmds(
            description,
            inputs: inputs,
            dependencyOracle: dependencyOracle,
            explicitDependencyJobTracker: explicitDependencyJobTracker
        )

        self.addTargetCmd(description, cmdOutputs: cmdOutputs)
        try self.addModuleWrapCmd(description)
    }

    private func addExplicitBuildSwiftCmds(
        _ targetDescription: SwiftTargetBuildDescription,
        inputs: [Node],
        dependencyOracle: InterModuleDependencyOracle,
        explicitDependencyJobTracker: UniqueExplicitDependencyJobTracker? = nil
    ) throws {
        // Pass the driver its external dependencies (target dependencies)
        var dependencyModuleDetailsMap: SwiftDriver.ExternalTargetModuleDetailsMap = [:]
        // Collect paths for target dependencies of this target (direct and transitive)
        try self.collectTargetDependencyModuleDetails(
            for: targetDescription.target,
            dependencyModuleDetailsMap: &dependencyModuleDetailsMap
        )

        // Compute the set of frontend
        // jobs needed to build this Swift target.
        var commandLine = try targetDescription.emitCommandLine()
        commandLine.append("-driver-use-frontend-path")
        commandLine.append(self.buildParameters.toolchain.swiftCompilerPath.pathString)
        commandLine.append("-experimental-explicit-module-build")
        let resolver = try ArgsResolver(fileSystem: self.fileSystem)
        let executor = SPMSwiftDriverExecutor(
            resolver: resolver,
            fileSystem: self.fileSystem,
            env: ProcessEnv.vars
        )
        var driver = try Driver(
            args: commandLine,
            fileSystem: self.fileSystem,
            executor: executor,
            externalTargetModuleDetailsMap: dependencyModuleDetailsMap,
            interModuleDependencyOracle: dependencyOracle
        )
        let jobs = try driver.planBuild()
        try self.addSwiftDriverJobs(
            for: targetDescription,
            jobs: jobs,
            inputs: inputs,
            resolver: resolver,
            isMainModule: { driver.isExplicitMainModuleJob(job: $0) },
            uniqueExplicitDependencyTracker: explicitDependencyJobTracker
        )
    }

    /// Collect a map from all target dependencies of the specified target to the build planning artifacts for said
    /// dependency,
    /// in the form of a path to a .swiftmodule file and the dependency's InterModuleDependencyGraph.
    private func collectTargetDependencyModuleDetails(
        for target: ResolvedTarget,
        dependencyModuleDetailsMap: inout SwiftDriver.ExternalTargetModuleDetailsMap
    ) throws {
        for dependency in target.dependencies(satisfying: self.buildEnvironment) {
            switch dependency {
            case .product:
                // Product dependencies are broken down into the targets that make them up.
                guard let dependencyProduct = dependency.product else {
                    throw InternalError("unknown dependency product for \(dependency)")
                }
                for dependencyProductTarget in dependencyProduct.targets {
                    try self.addTargetDependencyInfo(
                        for: dependencyProductTarget,
                        dependencyModuleDetailsMap: &dependencyModuleDetailsMap
                    )
                }
            case .target:
                // Product dependencies are broken down into the targets that make them up.
                guard let dependencyTarget = dependency.target else {
                    throw InternalError("unknown dependency target for \(dependency)")
                }
                try self.addTargetDependencyInfo(
                    for: dependencyTarget,
                    dependencyModuleDetailsMap: &dependencyModuleDetailsMap
                )
            }
        }
    }

    private func addTargetDependencyInfo(
        for target: ResolvedTarget,
        dependencyModuleDetailsMap: inout SwiftDriver.ExternalTargetModuleDetailsMap
    ) throws {
        guard case .swift(let dependencySwiftTargetDescription) = self.plan.targetMap[target] else {
            return
        }
        dependencyModuleDetailsMap[ModuleDependencyId.swiftPlaceholder(target.c99name)] =
            SwiftDriver.ExternalTargetModuleDetails(
                path: dependencySwiftTargetDescription.moduleOutputPath,
                isFramework: false
            )
        try self.collectTargetDependencyModuleDetails(
            for: target,
            dependencyModuleDetailsMap: &dependencyModuleDetailsMap
        )
    }

    private func addSwiftCmdsEmitSwiftModuleSeparately(
        _ target: SwiftTargetBuildDescription,
        inputs: [Node],
        objectNodes: [Node],
        moduleNode: Node
    ) throws {
        // FIXME: We need to ingest the emitted dependencies.

        self.manifest.addShellCmd(
            name: target.moduleOutputPath.pathString,
            description: "Emitting module for \(target.target.name)",
            inputs: inputs,
            outputs: [moduleNode],
            arguments: try target.emitModuleCommandLine()
        )

        let cmdName = target.target.getCommandName(config: self.buildConfig)
        self.manifest.addShellCmd(
            name: cmdName,
            description: "Compiling module \(target.target.name)",
            inputs: inputs,
            outputs: objectNodes,
            arguments: try target.emitObjectsCommandLine()
        )
    }

    private func addCmdWithBuiltinSwiftTool(
        _ target: SwiftTargetBuildDescription,
        inputs: [Node],
        cmdOutputs: [Node]
    ) throws {
        let isLibrary = target.target.type == .library || target.target.type == .test
        let cmdName = target.target.getCommandName(config: self.buildConfig)

        self.manifest.addSwiftCmd(
            name: cmdName,
            inputs: inputs,
            outputs: cmdOutputs,
            executable: self.buildParameters.toolchain.swiftCompilerPath,
            packageName: target.package.identity.description.spm_mangledToC99ExtendedIdentifier(),
            moduleName: target.target.c99name,
            moduleAliases: target.target.moduleAliases,
            moduleOutputPath: target.moduleOutputPath,
            importPath: self.buildParameters.buildPath,
            tempsPath: target.tempsPath,
            objects: try target.objects,
            otherArguments: try target.compileArguments(),
            sources: target.sources,
            isLibrary: isLibrary,
            wholeModuleOptimization: self.buildParameters.configuration == .release
        )
    }

    private func computeSwiftCompileCmdInputs(
        _ target: SwiftTargetBuildDescription
    ) throws -> [Node] {
        var inputs = target.sources.map(Node.file)

        // Add resources node as the input to the target. This isn't great because we
        // don't need to block building of a module until its resources are assembled but
        // we don't currently have a good way to express that resources should be built
        // whenever a module is being built.
        if let resourcesNode = createResourcesBundle(for: .swift(target)) {
            inputs.append(resourcesNode)
        }

        func addStaticTargetInputs(_ target: ResolvedTarget) throws {
            // Ignore C Modules.
            if target.underlyingTarget is SystemLibraryTarget { return }
            // Ignore Binary Modules.
            if target.underlyingTarget is BinaryTarget { return }
            // Ignore Plugin Targets.
            if target.underlyingTarget is PluginTarget { return }

            // Depend on the binary for executable targets.
            if target.type == .executable {
                // FIXME: Optimize.
                let product = try plan.graph.allProducts.first {
                    try $0.type == .executable && $0.executableTarget == target
                }
                if let product {
                    guard let planProduct = plan.productMap[product] else {
                        throw InternalError("unknown product \(product)")
                    }
                    inputs.append(file: planProduct.binaryPath)
                }
                return
            }

            switch self.plan.targetMap[target] {
            case .swift(let target)?:
                inputs.append(file: target.moduleOutputPath)
            case .clang(let target)?:
                for object in try target.objects {
                    inputs.append(file: object)
                }
            case nil:
                throw InternalError("unexpected: target \(target) not in target map \(self.plan.targetMap)")
            }
        }

        for dependency in target.target.dependencies(satisfying: self.buildEnvironment) {
            switch dependency {
            case .target(let target, _):
                try addStaticTargetInputs(target)

            case .product(let product, _):
                switch product.type {
                case .executable, .snippet, .library(.dynamic), .macro:
                    guard let planProduct = plan.productMap[product] else {
                        throw InternalError("unknown product \(product)")
                    }
                    // Establish a dependency on binary of the product.
                    inputs.append(file: planProduct.binaryPath)

                // For automatic and static libraries, and plugins, add their targets as static input.
                case .library(.automatic), .library(.static), .plugin:
                    for target in product.targets {
                        try addStaticTargetInputs(target)
                    }

                case .test:
                    break
                }
            }
        }

        for binaryPath in target.libraryBinaryPaths {
            let path = destinationPath(forBinaryAt: binaryPath)
            if self.fileSystem.isDirectory(binaryPath) {
                inputs.append(directory: path)
            } else {
                inputs.append(file: path)
            }
        }

        // Add any regular build commands created by plugins for the target.
        for result in target.buildToolPluginInvocationResults {
            // Only go through the regular build commands — prebuild commands are handled separately.
            for command in result.buildCommands {
                // Create a shell command to invoke the executable. We include the path of the executable as a
                // dependency, and make sure the name is unique.
                let execPath = command.configuration.executable
                let uniquedName = ([execPath.pathString] + command.configuration.arguments).joined(separator: "|")
                let displayName = command.configuration.displayName ?? execPath.basename
                var commandLine = [execPath.pathString] + command.configuration.arguments
                if !self.disableSandboxForPluginCommands {
                    commandLine = try Sandbox.apply(
                        command: commandLine,
                        strictness: .writableTemporaryDirectory,
                        writableDirectories: [result.pluginOutputDirectory]
                    )
                }
                self.manifest.addShellCmd(
                    name: displayName + "-" + ByteString(encodingAsUTF8: uniquedName).sha256Checksum,
                    description: displayName,
                    inputs: command.inputFiles.map { .file($0) },
                    outputs: command.outputFiles.map { .file($0) },
                    arguments: commandLine,
                    environment: command.configuration.environment,
                    workingDirectory: command.configuration.workingDirectory?.pathString
                )
            }
        }

        // Depend on any required macro product's output.
        try target.requiredMacroProducts.forEach { macro in
            try inputs.append(.virtual(macro.getLLBuildTargetName(config: buildConfig)))
        }

        return inputs
    }

    /// Adds a top-level phony command that builds the entire target.
    private func addTargetCmd(_ target: SwiftTargetBuildDescription, cmdOutputs: [Node]) {
        // Create a phony node to represent the entire target.
        let targetName = target.target.getLLBuildTargetName(config: self.buildConfig)
        let targetOutput: Node = .virtual(targetName)

        self.manifest.addNode(targetOutput, toTarget: targetName)
        self.manifest.addPhonyCmd(
            name: targetOutput.name,
            inputs: cmdOutputs,
            outputs: [targetOutput]
        )
        if self.plan.graph.isInRootPackages(target.target, satisfying: self.buildEnvironment) {
            if !target.isTestTarget {
                self.addNode(targetOutput, toTarget: .main)
            }
            self.addNode(targetOutput, toTarget: .test)
        }
    }

    private func addModuleWrapCmd(_ target: SwiftTargetBuildDescription) throws {
        // Add commands to perform the module wrapping Swift modules when debugging strategy is `modulewrap`.
        guard self.buildParameters.debuggingStrategy == .modulewrap else { return }
        var moduleWrapArgs = [
            target.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-modulewrap", target.moduleOutputPath.pathString,
            "-o", target.wrappedModuleOutputPath.pathString,
        ]
        moduleWrapArgs += try self.buildParameters.targetTripleArgs(for: target.target)
        self.manifest.addShellCmd(
            name: target.wrappedModuleOutputPath.pathString,
            description: "Wrapping AST for \(target.target.name) for debugging",
            inputs: [.file(target.moduleOutputPath)],
            outputs: [.file(target.wrappedModuleOutputPath)],
            arguments: moduleWrapArgs
        )
    }
}

extension SwiftDriver.Job {
    fileprivate var isExplicitDependencyPreBuildJob: Bool {
        (kind == .emitModule && inputs.contains { $0.file.extension == "swiftinterface" }) || kind == .generatePCM
    }
}

/// A simple mechanism to keep track of already-known explicit module pre-build jobs.
/// It uses the output filename of the job (either a `.swiftmodule` or a `.pcm`) for uniqueness,
/// because the SwiftDriver encodes the module's context hash into this filename. Any two jobs
/// producing an binary module file with an identical name are therefore duplicate
private class UniqueExplicitDependencyJobTracker {
    private var uniqueDependencyModuleIDSet: Set<Int> = []

    /// Registers the input Job with the tracker. Returns `false` if this job is already known
    func registerExplicitDependencyBuildJob(_ job: SwiftDriver.Job) throws -> Bool {
        guard job.isExplicitDependencyPreBuildJob,
              let soleOutput = job.outputs.spm_only
        else {
            throw InternalError("Expected explicit module dependency build job")
        }
        let jobUniqueID = soleOutput.file.basename.hashValue
        let (new, _) = self.uniqueDependencyModuleIDSet.insert(jobUniqueID)
        return new
    }
}

// MARK: - Compile C-family

extension LLBuildManifestBuilder {
    /// Create a llbuild target for a Clang target description.
    private func createClangCompileCommand(
        _ target: ClangTargetBuildDescription
    ) throws {
        let standards = [
            (target.clangTarget.cxxLanguageStandard, SupportedLanguageExtension.cppExtensions),
            (target.clangTarget.cLanguageStandard, SupportedLanguageExtension.cExtensions),
        ]

        var inputs: [Node] = []

        // Add resources node as the input to the target. This isn't great because we
        // don't need to block building of a module until its resources are assembled but
        // we don't currently have a good way to express that resources should be built
        // whenever a module is being built.
        if let resourcesNode = createResourcesBundle(for: .clang(target)) {
            inputs.append(resourcesNode)
        }

        func addStaticTargetInputs(_ target: ResolvedTarget) {
            if case .swift(let desc)? = self.plan.targetMap[target], target.type == .library {
                inputs.append(file: desc.moduleOutputPath)
            }
        }

        for dependency in target.target.dependencies(satisfying: self.buildEnvironment) {
            switch dependency {
            case .target(let target, _):
                addStaticTargetInputs(target)

            case .product(let product, _):
                switch product.type {
                case .executable, .snippet, .library(.dynamic), .macro:
                    guard let planProduct = plan.productMap[product] else {
                        throw InternalError("unknown product \(product)")
                    }
                    // Establish a dependency on binary of the product.
                    let binary = planProduct.binaryPath
                    inputs.append(file: binary)

                case .library(.automatic), .library(.static), .plugin:
                    for target in product.targets {
                        addStaticTargetInputs(target)
                    }
                case .test:
                    break
                }
            }
        }

        for binaryPath in target.libraryBinaryPaths {
            let path = destinationPath(forBinaryAt: binaryPath)
            if self.fileSystem.isDirectory(binaryPath) {
                inputs.append(directory: path)
            } else {
                inputs.append(file: path)
            }
        }

        var objectFileNodes: [Node] = []

        for path in try target.compilePaths() {
            let isCXX = path.source.extension.map { SupportedLanguageExtension.cppExtensions.contains($0) } ?? false
            let isC = path.source.extension.map { $0 == SupportedLanguageExtension.c.rawValue } ?? false

            var args = try target.basicArguments(isCXX: isCXX, isC: isC)

            args += ["-MD", "-MT", "dependencies", "-MF", path.deps.pathString]

            // Add language standard flag if needed.
            if let ext = path.source.extension {
                for (standard, validExtensions) in standards {
                    if let standard, validExtensions.contains(ext) {
                        args += ["-std=\(standard)"]
                    }
                }
            }

            args += ["-c", path.source.pathString, "-o", path.object.pathString]

            let clangCompiler = try buildParameters.toolchain.getClangCompiler().pathString
            args.insert(clangCompiler, at: 0)

            let objectFileNode: Node = .file(path.object)
            objectFileNodes.append(objectFileNode)

            self.manifest.addClangCmd(
                name: path.object.pathString,
                description: "Compiling \(target.target.name) \(path.filename)",
                inputs: inputs + [.file(path.source)],
                outputs: [objectFileNode],
                arguments: args,
                dependencies: path.deps.pathString
            )
        }

        // Create a phony node to represent the entire target.
        let targetName = target.target.getLLBuildTargetName(config: self.buildConfig)
        let output: Node = .virtual(targetName)

        self.manifest.addNode(output, toTarget: targetName)
        self.manifest.addPhonyCmd(
            name: output.name,
            inputs: objectFileNodes,
            outputs: [output]
        )

        if self.plan.graph.isInRootPackages(target.target, satisfying: self.buildEnvironment) {
            if !target.isTestTarget {
                self.addNode(output, toTarget: .main)
            }
            self.addNode(output, toTarget: .test)
        }
    }
}

// MARK: - Test File Generation

extension LLBuildManifestBuilder {
    private func addTestDiscoveryGenerationCommand() throws {
        for testDiscoveryTarget in self.plan.targets.compactMap(\.testDiscoveryTargetBuildDescription) {
            let testTargets = testDiscoveryTarget.target.dependencies
                .compactMap(\.target).compactMap { plan.targetMap[$0] }
            let objectFiles = try testTargets.flatMap { try $0.objects }.sorted().map(Node.file)
            let outputs = testDiscoveryTarget.target.sources.paths

            guard let mainOutput = (outputs.first { $0.basename == TestDiscoveryTool.mainFileName }) else {
                throw InternalError("main output (\(TestDiscoveryTool.mainFileName)) not found")
            }
            let cmdName = mainOutput.pathString
            self.manifest.addTestDiscoveryCmd(
                name: cmdName,
                inputs: objectFiles,
                outputs: outputs.map(Node.file)
            )
        }
    }

    private func addTestEntryPointGenerationCommand() throws {
        for target in self.plan.targets {
            guard case .swift(let target) = target,
                  case .entryPoint(let isSynthesized) = target.testTargetRole,
                  isSynthesized else { continue }

            let testEntryPointTarget = target

            // Get the Swift target build descriptions of all discovery targets this synthesized entry point target
            // depends on.
            let discoveredTargetDependencyBuildDescriptions = testEntryPointTarget.target.dependencies
                .compactMap(\.target)
                .compactMap { plan.targetMap[$0] }
                .compactMap(\.testDiscoveryTargetBuildDescription)

            // The module outputs of the discovery targets this synthesized entry point target depends on are
            // considered the inputs to the entry point command.
            let inputs = discoveredTargetDependencyBuildDescriptions.map(\.moduleOutputPath)

            let outputs = testEntryPointTarget.target.sources.paths

            guard let mainOutput = (outputs.first { $0.basename == TestEntryPointTool.mainFileName }) else {
                throw InternalError("main output (\(TestEntryPointTool.mainFileName)) not found")
            }
            let cmdName = mainOutput.pathString
            self.manifest.addTestEntryPointCmd(
                name: cmdName,
                inputs: inputs.map(Node.file),
                outputs: outputs.map(Node.file)
            )
        }
    }
}

extension TargetBuildDescription {
    /// If receiver represents a Swift target build description whose test target role is Discovery,
    /// then this returns that Swift target build description, else returns nil.
    fileprivate var testDiscoveryTargetBuildDescription: SwiftTargetBuildDescription? {
        guard case .swift(let targetBuildDescription) = self,
              case .discovery = targetBuildDescription.testTargetRole else { return nil }
        return targetBuildDescription
    }
}

// MARK: - Product Command

extension LLBuildManifestBuilder {
    private func createProductCommand(_ buildProduct: ProductBuildDescription) throws {
        let cmdName = try buildProduct.product.getCommandName(config: self.buildConfig)

        switch buildProduct.product.type {
        case .library(.static):
            self.manifest.addShellCmd(
                name: cmdName,
                description: "Archiving \(buildProduct.binaryPath.prettyPath())",
                inputs: buildProduct.objects.map(Node.file),
                outputs: [.file(buildProduct.binaryPath)],
                arguments: try buildProduct.archiveArguments()
            )

        default:
            let inputs = buildProduct.objects + buildProduct.dylibs.map(\.binaryPath)

            self.manifest.addShellCmd(
                name: cmdName,
                description: "Linking \(buildProduct.binaryPath.prettyPath())",
                inputs: inputs.map(Node.file),
                outputs: [.file(buildProduct.binaryPath)],
                arguments: try buildProduct.linkArguments()
            )
        }

        // Create a phony node to represent the entire target.
        let targetName = try buildProduct.product.getLLBuildTargetName(config: self.buildConfig)
        let output: Node = .virtual(targetName)

        self.manifest.addNode(output, toTarget: targetName)
        self.manifest.addPhonyCmd(
            name: output.name,
            inputs: [.file(buildProduct.binaryPath)],
            outputs: [output]
        )

        if self.plan.graph.reachableProducts.contains(buildProduct.product) {
            if buildProduct.product.type != .test {
                self.addNode(output, toTarget: .main)
            }
            self.addNode(output, toTarget: .test)
        }
    }
}

extension ResolvedTarget {
    public func getCommandName(config: String) -> String {
        "C." + self.getLLBuildTargetName(config: config)
    }

    public func getLLBuildTargetName(config: String) -> String {
        "\(name)-\(config).module"
    }

    public func getLLBuildResourcesCmdName(config: String) -> String {
        "\(name)-\(config).module-resources"
    }
}

extension ResolvedProduct {
    public func getLLBuildTargetName(config: String) throws -> String {
        let potentialExecutableTargetName = "\(name)-\(config).exe"
        let potentialLibraryTargetName = "\(name)-\(config).dylib"

        switch type {
        case .library(.dynamic):
            return potentialLibraryTargetName
        case .test:
            return "\(name)-\(config).test"
        case .library(.static):
            return "\(name)-\(config).a"
        case .library(.automatic):
            throw InternalError("automatic library not supported")
        case .executable, .snippet:
            return potentialExecutableTargetName
        case .macro:
            #if BUILD_MACROS_AS_DYLIBS
            return potentialLibraryTargetName
            #else
            return potentialExecutableTargetName
            #endif
        case .plugin:
            throw InternalError("unexpectedly asked for the llbuild target name of a plugin product")
        }
    }

    public func getCommandName(config: String) throws -> String {
        try "C." + self.getLLBuildTargetName(config: config)
    }
}

// MARK: - Helper

extension LLBuildManifestBuilder {
    @discardableResult
    private func addCopyCommand(
        from source: AbsolutePath,
        to destination: AbsolutePath
    ) -> (inputNode: Node, outputNode: Node) {
        let isDirectory = self.fileSystem.isDirectory(source)
        let nodeType = isDirectory ? Node.directory : Node.file
        let inputNode = nodeType(source)
        let outputNode = nodeType(destination)
        self.manifest.addCopyCmd(name: destination.pathString, inputs: [inputNode], outputs: [outputNode])
        return (inputNode, outputNode)
    }

    private func destinationPath(forBinaryAt path: AbsolutePath) -> AbsolutePath {
        self.plan.buildParameters.buildPath.appending(component: path.basename)
    }
}

extension TypedVirtualPath {
    /// Resolve a typed virtual path provided by the Swift driver to
    /// a node in the build graph.
    func resolveToNode(fileSystem: FileSystem) throws -> Node {
        if let absolutePath = file.absolutePath {
            return Node.file(absolutePath)
        } else if let relativePath = file.relativePath {
            guard let workingDirectory = fileSystem.currentWorkingDirectory else {
                throw InternalError("unknown working directory")
            }
            return Node.file(workingDirectory.appending(relativePath))
        } else if let temporaryFileName = file.temporaryFileName {
            return Node.virtual(temporaryFileName.pathString)
        } else {
            throw InternalError("Cannot resolve VirtualPath: \(file)")
        }
    }
}

extension Sequence where Element: Hashable {
    /// Unique the elements in a sequence.
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
