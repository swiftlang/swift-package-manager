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

    /// Generate manifest at the given path.
    public func generateManifest(at path: AbsolutePath) throws {
        manifest.createTarget(TargetKind.main.targetName)
        manifest.createTarget(TargetKind.test.targetName)
        manifest.defaultTarget = TargetKind.main.targetName

        addPackageStructureCommand()
        addBinaryDependencyCommands()

        // Create commands for all target descriptions in the plan.
        for (_, description) in plan.targetMap {
            switch description {
            case .swift(let desc):
                createSwiftCompileCommand(desc)
            case .clang(let desc):
                createClangCompileCommand(desc)
            }
        }

        addTestFileGenerationCommand()

        // Create command for all products in the plan.
        for (_, description) in plan.productMap {
            createProductCommand(description)
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
    ) {
        // Inputs.
        let inputs = computeSwiftCompileCmdInputs(target)

        // Outputs.
        let objectNodes = target.objects.map(Node.file)
        let moduleNode = Node.file(target.moduleOutputPath)
        let cmdOutputs = objectNodes + [moduleNode]

        if buildParameters.useIntegratedSwiftDriver {
            addSwiftCmdsViaIntegratedDriver(target, inputs: inputs, objectNodes: objectNodes, moduleNode: moduleNode)
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
    ) {
        do {
            // Use the integrated Swift driver to compute the set of frontend
            // jobs needed to build this Swift target.
            var commandLine = target.emitCommandLine();
            commandLine.append("-driver-use-frontend-path")
            commandLine.append(buildParameters.toolchain.swiftCompiler.pathString)
            if buildParameters.useExplicitModuleBuild {
              commandLine.append("-experimental-explicit-module-build")
            }
            var driver = try Driver(args: commandLine, fileSystem: target.fs)
            let jobs = try driver.planBuild()
            let resolver = try ArgsResolver(fileSystem: target.fs)

            for job in jobs {
                let tool = try resolver.resolve(.path(job.tool))
                let commandLine = try job.commandLine.map{ try resolver.resolve($0) }
                let arguments = [tool] + commandLine

                let jobInputs = job.inputs.map { $0.resolveToNode() }
                let jobOutputs = job.outputs.map { $0.resolveToNode() }

                let moduleName = target.target.c99name
                let description = job.description
                if job.kind.isSwiftFrontend {
                    manifest.addSwiftFrontendCmd(
                        name: jobOutputs.first!.name,
                        moduleName: moduleName,
                        description: description,
                        inputs: (inputs + jobInputs).uniqued(),
                        outputs: jobOutputs,
                        args: arguments
                    )
                } else {
                    manifest.addShellCmd(
                        name: jobOutputs.first!.name,
                        description: description,
                        inputs: (inputs + jobInputs).uniqued(),
                        outputs: jobOutputs,
                        args: arguments
                    )
                }
             }
         } catch {
             fatalError("\(error)")
         }
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

        case .temporary(let path):
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
