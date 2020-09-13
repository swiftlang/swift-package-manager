/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import LLBuildManifest

import TSCBasic
import TSCUtility

import PackageModel
import PackageGraph
import SPMBuildCore

@_implementationOnly import SwiftDriver

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

    public private(set) var manifest: BuildManifest = BuildManifest()

    var buildConfig: String { buildParameters.configuration.dirname }
    var buildParameters: BuildParameters { plan.buildParameters }
    var buildEnvironment: BuildEnvironment { buildParameters.buildEnvironment }

    /// Create a new builder with a build plan.
    public init(_ plan: BuildPlan) {
        self.plan = plan
    }

    // MARK:- Generate Manifest
    /// Generate manifest at the given path.
    public func generateManifest(at path: AbsolutePath) throws {
        manifest.createTarget(TargetKind.main.targetName)
        manifest.createTarget(TargetKind.test.targetName)
        manifest.defaultTarget = TargetKind.main.targetName

        addPackageStructureCommand()
        addBinaryDependencyCommands()
        if buildParameters.useExplicitModuleBuild {
            // Explicit module builds use the integrated driver directly and
            // require that every target's build jobs specify its dependencies explicitly to plan
            // its build.
            // Currently behind:
            // --experimental-explicit-module-build
            try addTargetsToExplicitBuildManifest()
        } else {
            // Create commands for all target descriptions in the plan.
            for (_, description) in plan.targetMap {
                switch description {
                    case .swift(let desc):
                        try createSwiftCompileCommand(desc)
                    case .clang(let desc):
                        createClangCompileCommand(desc)
                }
            }
        }

        addTestFileGenerationCommand()

        // Create command for all products in the plan.
        for (_, description) in plan.productMap {
            createProductCommand(description)
        }

        // Output a dot graph
        if buildParameters.printManifestGraphviz {
            var serializer = DOTManifestSerializer(manifest: manifest)
            serializer.writeDOT(to: &stdoutStream)
            stdoutStream.flush()
        }

        try ManifestWriter().write(manifest, at: path)
    }

    func addNode(_ node: Node, toTarget targetKind: TargetKind) {
        manifest.addNode(node, toTarget: targetKind.targetName)
    }
}

// MARK:- Package Structure

extension LLBuildManifestBuilder {

    fileprivate func addPackageStructureCommand() {
        let inputs = plan.graph.rootPackages.flatMap { package -> [Node] in
            var inputs = package.targets
                .map { $0.sources.root }
                .sorted()
                .map { Node.directoryStructure($0) }

            // FIXME: Need to handle version-specific manifests.
            inputs.append(file: package.manifest.path)

            // FIXME: This won't be the location of Package.resolved for multiroot packages.
            inputs.append(file: package.path.appending(component: "Package.resolved"))

            // FIXME: Add config file as an input

            return inputs
        }

        let name = "PackageStructure"
        let output: Node = .virtual(name)

        manifest.addPkgStructureCmd(
            name: name,
            inputs: inputs,
            outputs: [output]
        )
        manifest.addNode(output, toTarget: name)
    }
}

// MARK:- Binary Dependencies

extension LLBuildManifestBuilder {

    // Creates commands for copying all binary artifacts depended on in the plan.
    fileprivate func addBinaryDependencyCommands() {
        let binaryPaths = Set(plan.targetMap.values.flatMap({ $0.libraryBinaryPaths }))
        for binaryPath in binaryPaths {
            let destination = destinationPath(forBinaryAt: binaryPath)
            addCopyCommand(from: binaryPath, to: destination)
        }
    }
}

// MARK:- Resources Bundle

extension LLBuildManifestBuilder {
    /// Adds command for creating the resources bundle of the given target.
    ///
    /// Returns the virtual node that will build the entire bundle.
    fileprivate func createResourcesBundle(
        for target: TargetBuildDescription
    ) -> Node? {
        guard let bundlePath = target.bundlePath else { return nil }

        var outputs: [Node] = []

        let infoPlistDestination = RelativePath("Info.plist")

        // Create a copy command for each resource file.
        for resource in target.target.underlyingTarget.resources {
            let destination = bundlePath.appending(resource.destination)
            let (_, output) = addCopyCommand(from: resource.path, to: destination)
            outputs.append(output)
        }

        // Create a copy command for the Info.plist if a resource with the same name doesn't exist yet.
        if let infoPlistPath = target.resourceBundleInfoPlistPath {
            let destination = bundlePath.appending(infoPlistDestination)
            let (_, output) = addCopyCommand(from: infoPlistPath, to: destination)
            outputs.append(output)
        }

        let cmdName = target.target.getLLBuildResourcesCmdName(config: buildConfig)
        manifest.addPhonyCmd(name: cmdName, inputs: outputs, outputs: [.virtual(cmdName)])

        return .virtual(cmdName)
    }
}

// MARK:- Compile Swift

extension LLBuildManifestBuilder {
    /// Create a llbuild target for a Swift target description.
    private func createSwiftCompileCommand(
        _ target: SwiftTargetBuildDescription
    ) throws {
        // Inputs.
        let inputs = computeSwiftCompileCmdInputs(target)

        // Outputs.
        let objectNodes = target.objects.map(Node.file)
        let moduleNode = Node.file(target.moduleOutputPath)
        let cmdOutputs = objectNodes + [moduleNode]

        if buildParameters.useIntegratedSwiftDriver {
            try addSwiftCmdsViaIntegratedDriver(target, inputs: inputs, objectNodes: objectNodes, moduleNode: moduleNode)
        } else if buildParameters.emitSwiftModuleSeparately {
            addSwiftCmdsEmitSwiftModuleSeparately(target, inputs: inputs, objectNodes: objectNodes, moduleNode: moduleNode)
        } else {
            addCmdWithBuiltinSwiftTool(target, inputs: inputs, cmdOutputs: cmdOutputs)
        }

        addTargetCmd(target, cmdOutputs: cmdOutputs)
        addModuleWrapCmd(target)
    }

    private func addSwiftCmdsViaIntegratedDriver(
        _ target: SwiftTargetBuildDescription,
        inputs: [Node],
        objectNodes: [Node],
        moduleNode: Node
    ) throws {
        // Use the integrated Swift driver to compute the set of frontend
        // jobs needed to build this Swift target.
        var commandLine = target.emitCommandLine();
        commandLine.append("-driver-use-frontend-path")
        commandLine.append(buildParameters.toolchain.swiftCompiler.pathString)
        // FIXME: At some point SwiftPM should provide its own executor for
        // running jobs/launching processes during planning
        let executor = try SwiftDriverExecutor(diagnosticsEngine: plan.diagnostics,
                                               processSet: ProcessSet(),
                                               fileSystem: target.fs,
                                               env: ProcessEnv.vars)
        var driver = try Driver(args: commandLine,
                                diagnosticsEngine: plan.diagnostics,
                                fileSystem: target.fs,
                                executor: executor)
        let jobs = try driver.planBuild()
        try addSwiftDriverJobs(for: target, jobs: jobs, inputs: inputs,
                               isMainModule: { driver.isExplicitMainModuleJob(job: $0)})
    }

    private func addSwiftDriverJobs(for targetDescription: SwiftTargetBuildDescription,
                                    jobs: [Job], inputs: [Node],
                                    isMainModule: (Job) -> Bool) throws {
        // Add build jobs to the manifest
        let resolver = try ArgsResolver(fileSystem: targetDescription.fs)
        for job in jobs {
            let tool = try resolver.resolve(.path(job.tool))
            let commandLine = try job.commandLine.map{ try resolver.resolve($0) }
            let arguments = [tool] + commandLine

            let jobInputs = job.inputs.map { $0.resolveToNode() }
            let jobOutputs = job.outputs.map { $0.resolveToNode() }

            // Add target dependencies as inputs to the main module build command.
            //
            // Jobs for a target's intermediate build artifacts, such as PCMs or
            // modules built from a .swiftinterface, do not have a
            // dependency on cross-target build products. If multiple targets share
            // common intermediate dependency modules, such dependencies can lead
            // to cycles in the resulting manifest.
            var manifestNodeInputs : [Node] = []
            if buildParameters.useExplicitModuleBuild && !isMainModule(job) {
                manifestNodeInputs = jobInputs
            } else {
                manifestNodeInputs = (inputs + jobInputs).uniqued()
            }

            let moduleName = targetDescription.target.c99name
            let description = job.description
            if job.kind.isSwiftFrontend {
                manifest.addSwiftFrontendCmd(
                    name: jobOutputs.first!.name,
                    moduleName: moduleName,
                    description: description,
                    inputs: manifestNodeInputs,
                    outputs: jobOutputs,
                    args: arguments
                )
            } else {
                manifest.addShellCmd(
                    name: jobOutputs.first!.name,
                    description: description,
                    inputs: manifestNodeInputs,
                    outputs: jobOutputs,
                    args: arguments
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
    // inter-module dependency graph to its dependees. First, SwiftPM will process B, and be
    // able to plan its full build because it does not have any target dependencies. Then the
    // driver is tasked with planning a build for A. SwiftPM will pass as input to the driver
    // the module dependency graph of its target’s dependencies, in this case, just the
    // dependency graph of B. The driver is then responsible for the necessary post-processing
    // to merge the dependency graphs and plan the build for A, using artifacts of B as explicit
    // inputs.
    public func addTargetsToExplicitBuildManifest() throws {
        // Sort the product targets in topological order in order to collect and "bubble up"
        // their respective dependency graphs to the depending targets.
        let nodes: [ResolvedTarget.Dependency] = plan.targetMap.keys.map {
            ResolvedTarget.Dependency.target($0, conditions: [])
        }
        let allPackageDependencies = try! topologicalSort(nodes, successors: { $0.dependencies })

        // Collect all targets' dependency graphs
        var targetDepGraphMap : [ResolvedTarget: InterModuleDependencyGraph] = [:]

        // Create commands for all target descriptions in the plan.
        for dependency in allPackageDependencies.reversed() {
            guard case .target(let target, _) = dependency else {
                // Product dependency build jobs are added after the fact.
                // Targets that depend on product dependencies will expand the corresponding
                // product into its constituent targets.
                continue
            }
            guard let description = plan.targetMap[target] else {
                fatalError("Expected description for target: \(target)")
            }
            switch description {
                case .swift(let desc):
                    try createExplicitSwiftTargetCompileCommand(description: desc,
                                                                targetDepGraphMap: &targetDepGraphMap)
                case .clang(let desc):
                    createClangCompileCommand(desc)
            }
        }
    }

    private func createExplicitSwiftTargetCompileCommand(
        description: SwiftTargetBuildDescription,
        targetDepGraphMap: inout [ResolvedTarget: InterModuleDependencyGraph]
    ) throws {
        // Inputs.
        let inputs = computeSwiftCompileCmdInputs(description)

        // Outputs.
        let objectNodes = description.objects.map(Node.file)
        let moduleNode = Node.file(description.moduleOutputPath)
        let cmdOutputs = objectNodes + [moduleNode]

        // Commands.
        try addExplicitBuildSwiftCmds(description, inputs: inputs,
                                      objectNodes: objectNodes,
                                      moduleNode: moduleNode,
                                      targetDepGraphMap: &targetDepGraphMap)

        addTargetCmd(description, cmdOutputs: cmdOutputs)
        addModuleWrapCmd(description)
    }

    private func addExplicitBuildSwiftCmds(
        _ targetDescription: SwiftTargetBuildDescription,
        inputs: [Node], objectNodes: [Node], moduleNode: Node,
        targetDepGraphMap: inout [ResolvedTarget: InterModuleDependencyGraph]
    ) throws {
        // Pass the driver its external dependencies (target dependencies)
        var targetDependencyMap: SwiftDriver.ExternalDependencyArtifactMap = [:]
        collectTargetDependencyInfos(for: targetDescription.target,
                                     targetDepGraphMap: targetDepGraphMap,
                                     dependencyArtifactMap: &targetDependencyMap)

        // Compute the set of frontend
        // jobs needed to build this Swift target.
        var commandLine = targetDescription.emitCommandLine();
        commandLine.append("-driver-use-frontend-path")
        commandLine.append(buildParameters.toolchain.swiftCompiler.pathString)
        commandLine.append("-experimental-explicit-module-build")
        // FIXME: At some point SwiftPM should provide its own executor for
        // running jobs/launching processes during planning
        let executor = try SwiftDriverExecutor(diagnosticsEngine: plan.diagnostics,
                                               processSet: ProcessSet(),
                                               fileSystem: targetDescription.fs,
                                               env: ProcessEnv.vars)
        var driver = try Driver(args: commandLine, fileSystem: targetDescription.fs,
                                executor: executor,
                                externalModuleDependencies: targetDependencyMap)

        let jobs = try driver.planBuild()

        // Save the dependency graph of this target to be used by its dependents
        guard let dependencyGraph = driver.interModuleDependencyGraph else {
            fatalError("Expected module dependency graph for target: \(targetDescription)")
        }
        targetDepGraphMap[targetDescription.target] = dependencyGraph
        try addSwiftDriverJobs(for: targetDescription, jobs: jobs, inputs: inputs,
                               isMainModule: { driver.isExplicitMainModuleJob(job: $0)})
    }

    /// Collect a map from all target dependencies of the specified target to the build planning artifacts for said dependency,
    /// in the form of a path to a .swiftmodule file and the dependency's InterModuleDependencyGraph.
    private func collectTargetDependencyInfos(for target: ResolvedTarget,
                                              targetDepGraphMap: [ResolvedTarget: InterModuleDependencyGraph],
                                              dependencyArtifactMap: inout SwiftDriver.ExternalDependencyArtifactMap
    ) {
        for dependency in target.dependencies {
            switch dependency {
                case .product:
                    // Product dependencies are broken down into the targets that make them up.
                    let dependencyProduct = dependency.product!
                    for dependencyProductTarget in dependencyProduct.targets {
                        addTargetDependencyInfo(for: dependencyProductTarget,
                                                targetDepGraphMap: targetDepGraphMap,
                                                dependencyArtifactMap: &dependencyArtifactMap)

                    }
                case .target:
                    // Product dependencies are broken down into the targets that make them up.
                    let dependencyTarget = dependency.target!
                    addTargetDependencyInfo(for: dependencyTarget,
                                            targetDepGraphMap: targetDepGraphMap,
                                            dependencyArtifactMap: &dependencyArtifactMap)
            }
        }
    }

    private func addTargetDependencyInfo(for target: ResolvedTarget,
                                         targetDepGraphMap: [ResolvedTarget: InterModuleDependencyGraph],
                                         dependencyArtifactMap: inout SwiftDriver.ExternalDependencyArtifactMap) {
        guard case .swift(let dependencySwiftTargetDescription) = plan.targetMap[target] else {
            return
        }
        guard let dependencyGraph = targetDepGraphMap[target] else {
            fatalError("Expected dependency graph for target: \(target.description)")
        }
        let moduleName = target.name
        let dependencyModulePath = dependencySwiftTargetDescription.moduleOutputPath
        dependencyArtifactMap[ModuleDependencyId.swiftPlaceholder(moduleName)] =
            (dependencyModulePath, dependencyGraph)

        collectTargetDependencyInfos(for: target,
                                     targetDepGraphMap: targetDepGraphMap,
                                     dependencyArtifactMap: &dependencyArtifactMap)
    }

    private func addSwiftCmdsEmitSwiftModuleSeparately(
        _ target: SwiftTargetBuildDescription,
        inputs: [Node],
        objectNodes: [Node],
        moduleNode: Node
    ) {
        // FIXME: We need to ingest the emitted dependencies.

        manifest.addShellCmd(
            name: target.moduleOutputPath.pathString,
            description: "Emitting module for \(target.target.name)",
            inputs: inputs,
            outputs: [moduleNode],
            args: target.emitModuleCommandLine()
        )

        let cmdName = target.target.getCommandName(config: buildConfig)
        manifest.addShellCmd(
            name: cmdName,
            description: "Compiling module \(target.target.name)",
            inputs: inputs,
            outputs: objectNodes,
            args: target.emitObjectsCommandLine()
        )
    }

    private func addCmdWithBuiltinSwiftTool(
        _ target: SwiftTargetBuildDescription,
        inputs: [Node],
        cmdOutputs: [Node]
    ) {
        let isLibrary = target.target.type == .library || target.target.type == .test
        let cmdName = target.target.getCommandName(config: buildConfig)

        manifest.addSwiftCmd(
            name: cmdName,
            inputs: inputs,
            outputs: cmdOutputs,
            executable: buildParameters.toolchain.swiftCompiler,
            moduleName: target.target.c99name,
            moduleOutputPath: target.moduleOutputPath,
            importPath: buildParameters.buildPath,
            tempsPath: target.tempsPath,
            objects: target.objects,
            otherArgs: target.compileArguments(),
            sources: target.sources,
            isLibrary: isLibrary,
            WMO: buildParameters.configuration == .release
        )
    }

    private func computeSwiftCompileCmdInputs(
        _ target: SwiftTargetBuildDescription
    ) -> [Node] {
        var inputs = target.sources.map(Node.file)

        // Add resources node as the input to the target. This isn't great because we
        // don't need to block building of a module until its resources are assembled but
        // we don't currently have a good way to express that resources should be built
        // whenever a module is being built.
        if let resourcesNode = createResourcesBundle(for: .swift(target)) {
            inputs.append(resourcesNode)
        }

        func addStaticTargetInputs(_ target: ResolvedTarget) {
            // Ignore C Modules.
            if target.underlyingTarget is SystemLibraryTarget { return }
            // Ignore Binary Modules.
            if target.underlyingTarget is BinaryTarget { return }

            // Depend on the binary for executable targets.
            if target.type == .executable {
                // FIXME: Optimize.
                let _product = plan.graph.allProducts.first {
                    $0.type == .executable && $0.executableModule == target
                }
                if let product = _product {
                    inputs.append(file: plan.productMap[product]!.binary)
                }
                return
            }

            switch plan.targetMap[target] {
            case .swift(let target)?:
                inputs.append(file: target.moduleOutputPath)
            case .clang(let target)?:
                for object in target.objects {
                    inputs.append(file: object)
                }
            case nil:
                fatalError("unexpected: target \(target) not in target map \(plan.targetMap)")
            }
        }

        for dependency in target.target.dependencies(satisfying: buildEnvironment) {
            switch dependency {
            case .target(let target, _):
                addStaticTargetInputs(target)

            case .product(let product, _):
                switch product.type {
                case .executable, .library(.dynamic):
                    // Establish a dependency on binary of the product.
                    inputs.append(file: plan.productMap[product]!.binary)

                // For automatic and static libraries, add their targets as static input.
                case .library(.automatic), .library(.static):
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
            if localFileSystem.isDirectory(binaryPath) {
                inputs.append(directory: path)
            } else {
                inputs.append(file: path)
            }
        }

        return inputs
    }

    /// Adds a top-level phony command that builds the entire target.
    private func addTargetCmd(_ target: SwiftTargetBuildDescription, cmdOutputs: [Node]) {
        // Create a phony node to represent the entire target.
        let targetName = target.target.getLLBuildTargetName(config: buildConfig)
        let targetOutput: Node = .virtual(targetName)

        manifest.addNode(targetOutput, toTarget: targetName)
        manifest.addPhonyCmd(
            name: targetOutput.name,
            inputs: cmdOutputs,
            outputs: [targetOutput]
        )
        if plan.graph.isInRootPackages(target.target) {
            if !target.isTestTarget {
                addNode(targetOutput, toTarget: .main)
            }
            addNode(targetOutput, toTarget: .test)
        }
    }

    private func addModuleWrapCmd(_ target: SwiftTargetBuildDescription) {
        // Add commands to perform the module wrapping Swift modules when debugging statergy is `modulewrap`.
        guard buildParameters.debuggingStrategy == .modulewrap else { return }
        var moduleWrapArgs = [
            target.buildParameters.toolchain.swiftCompiler.pathString,
            "-modulewrap", target.moduleOutputPath.pathString,
            "-o", target.wrappedModuleOutputPath.pathString
        ]
        moduleWrapArgs += buildParameters.targetTripleArgs(for: target.target)
        manifest.addShellCmd(
            name: target.wrappedModuleOutputPath.pathString,
            description: "Wrapping AST for \(target.target.name) for debugging",
            inputs: [.file(target.moduleOutputPath)],
            outputs: [.file(target.wrappedModuleOutputPath)],
            args: moduleWrapArgs)
    }
}

// MARK:- Compile C-family

extension LLBuildManifestBuilder {
    /// Create a llbuild target for a Clang target description.
    private func createClangCompileCommand(
        _ target: ClangTargetBuildDescription
    ) {
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
            if case .swift(let desc)? = plan.targetMap[target], target.type == .library {
                inputs.append(file: desc.moduleOutputPath)
            }
        }

        for dependency in target.target.dependencies(satisfying: buildEnvironment) {
            switch dependency {
            case .target(let target, _):
                addStaticTargetInputs(target)

            case .product(let product, _):
                switch product.type {
                case .executable, .library(.dynamic):
                    // Establish a dependency on binary of the product.
                    let binary = plan.productMap[product]!.binary
                    inputs.append(file: binary)

                case .library(.automatic), .library(.static):
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
            if localFileSystem.isDirectory(binaryPath) {
                inputs.append(directory: path)
            } else {
                inputs.append(file: path)
            }
        }

        var objectFileNodes: [Node] = []

        for path in target.compilePaths() {
            var args = target.basicArguments()
            args += ["-MD", "-MT", "dependencies", "-MF", path.deps.pathString]

            // Add language standard flag if needed.
            if let ext = path.source.extension {
                for (standard, validExtensions) in standards {
                    if let languageStandard = standard, validExtensions.contains(ext) {
                        args += ["-std=\(languageStandard)"]
                    }
                }
            }

            args += ["-c", path.source.pathString, "-o", path.object.pathString]

            let clangCompiler = try! buildParameters.toolchain.getClangCompiler().pathString
            args.insert(clangCompiler, at: 0)

            let objectFileNode: Node = .file(path.object)
            objectFileNodes.append(objectFileNode)

            manifest.addClangCmd(
                name: path.object.pathString,
                description: "Compiling \(target.target.name) \(path.filename)",
                inputs: inputs + [.file(path.source)],
                outputs: [objectFileNode],
                args: args,
                deps: path.deps.pathString
            )
        }

        // Create a phony node to represent the entire target.
        let targetName = target.target.getLLBuildTargetName(config: buildConfig)
        let output: Node = .virtual(targetName)

        manifest.addNode(output, toTarget: targetName)
        manifest.addPhonyCmd(
            name: output.name,
            inputs: objectFileNodes,
            outputs: [output]
        )

        if plan.graph.isInRootPackages(target.target) {
            if !target.isTestTarget {
                addNode(output, toTarget: .main)
            }
            addNode(output, toTarget: .test)
        }
    }
}

// MARK:- Test File Generation

extension LLBuildManifestBuilder {
    fileprivate func addTestFileGenerationCommand() {
        for target in plan.targets {
            guard case .swift(let target) = target,
                target.isTestTarget,
                target.testDiscoveryTarget else { continue }

            let testDiscoveryTarget = target

            let testTargets = testDiscoveryTarget.target.dependencies
                .compactMap{ $0.target }.compactMap{ plan.targetMap[$0] }
            let objectFiles = testTargets.flatMap{ $0.objects }.sorted().map(Node.file)
            let outputs = testDiscoveryTarget.target.sources.paths

            let cmdName = outputs.first{ $0.basename == "main.swift" }!.pathString
            manifest.addTestDiscoveryCmd(
                name: cmdName,
                inputs: objectFiles,
                outputs: outputs.map(Node.file)
            )
        }
    }
}

// MARK:- Product Command

extension LLBuildManifestBuilder {
    private func createProductCommand(_ buildProduct: ProductBuildDescription) {
        let cmdName = buildProduct.product.getCommandName(config: buildConfig)

        // Create archive tool for static library and shell tool for rest of the products.
        if buildProduct.product.type == .library(.static) {
            manifest.addArchiveCmd(
                name: cmdName,
                inputs: buildProduct.objects.map(Node.file),
                outputs: [.file(buildProduct.binary)]
            )
        } else {
            let inputs = buildProduct.objects + buildProduct.dylibs.map({ $0.binary })

            manifest.addShellCmd(
                name: cmdName,
                description: "Linking \(buildProduct.binary.prettyPath())",
                inputs: inputs.map(Node.file),
                outputs: [.file(buildProduct.binary)],
                args: buildProduct.linkArguments()
            )
        }

        // Create a phony node to represent the entire target.
        let targetName = buildProduct.product.getLLBuildTargetName(config: buildConfig)
        let output: Node = .virtual(targetName)

        manifest.addNode(output, toTarget: targetName)
        manifest.addPhonyCmd(
            name: output.name,
            inputs: [.file(buildProduct.binary)],
            outputs: [output]
        )

        if plan.graph.reachableProducts.contains(buildProduct.product) {
            if buildProduct.product.type != .test {
                addNode(output, toTarget: .main)
            }
            addNode(output, toTarget: .test)
        }
    }
}

extension ResolvedTarget {
    public func getCommandName(config: String) -> String {
       return "C." + getLLBuildTargetName(config: config)
    }

    public func getLLBuildTargetName(config: String) -> String {
        return "\(name)-\(config).module"
    }

    public func getLLBuildResourcesCmdName(config: String) -> String {
        return "\(name)-\(config).module-resources"
    }
}

extension ResolvedProduct {
    public func getLLBuildTargetName(config: String) -> String {
        switch type {
        case .library(.dynamic):
            return "\(name)-\(config).dylib"
        case .test:
            return "\(name)-\(config).test"
        case .library(.static):
            return "\(name)-\(config).a"
        case .library(.automatic):
            fatalError()
        case .executable:
            return "\(name)-\(config).exe"
        }
    }

    public func getCommandName(config: String) -> String {
        return "C." + getLLBuildTargetName(config: config)
    }
}

// MARK:- Helper

extension LLBuildManifestBuilder {
    @discardableResult
    fileprivate func addCopyCommand(
        from source: AbsolutePath,
        to destination: AbsolutePath
    ) -> (inputNode: Node, outputNode: Node) {
        let isDirectory = localFileSystem.isDirectory(source)
        let nodeType = isDirectory ? Node.directory : Node.file
        let inputNode = nodeType(source)
        let outputNode = nodeType(destination)
        manifest.addCopyCmd(name: destination.pathString, inputs: [inputNode], outputs: [outputNode])
        return (inputNode, outputNode)
    }

    fileprivate func destinationPath(forBinaryAt path: AbsolutePath) -> AbsolutePath {
        plan.buildParameters.buildPath.appending(component: path.basename)
    }
}

extension TypedVirtualPath {
    /// Resolve a typed virtual path provided by the Swift driver to
    /// a node in the build graph.
    func resolveToNode() -> Node {
        switch file {
        case .relative(let path):
            return Node.file(localFileSystem.currentWorkingDirectory!.appending(path))

        case .absolute(let path):
            return Node.file(path)

        case .temporary(let path), .fileList(let path, _):
            return Node.virtual(path.pathString)

        case .standardInput, .standardOutput:
            fatalError("Cannot handle standard input or output")
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
