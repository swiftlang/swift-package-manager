//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2015-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Basics.InternalError
import struct Basics.AbsolutePath
import struct Basics.RelativePath
import struct Basics.TSCAbsolutePath
import struct LLBuildManifest.Node
import struct LLBuildManifest.LLBuildManifest
import struct SPMBuildCore.BuildParameters
import struct PackageGraph.ResolvedModule
import protocol TSCBasic.FileSystem
import func TSCBasic.topologicalSort
import struct Basics.Environment

#if USE_IMPL_ONLY_IMPORTS
@_implementationOnly import class DriverSupport.SPMSwiftDriverExecutor
@_implementationOnly import Foundation
@_implementationOnly import SwiftDriver
@_implementationOnly import TSCUtility
#else
import class DriverSupport.SPMSwiftDriverExecutor
import Foundation
import SwiftDriver
import TSCUtility
#endif

import PackageModel

extension LLBuildManifestBuilder {
    /// Create a llbuild target for a Swift module description.
    func createSwiftCompileCommand(
        _ target: SwiftModuleBuildDescription
    ) throws {
        // Inputs.
        let inputs = try self.computeSwiftCompileCmdInputs(target)

        // Outputs.
        let objectNodes = target.buildParameters.prepareForIndexing == .off ? try target.objects.map(Node.file) : []
        let moduleNode = Node.file(target.moduleOutputPath)
        let cmdOutputs = objectNodes + [moduleNode]

        if target.buildParameters.driverParameters.useIntegratedSwiftDriver {
            try self.addSwiftCmdsViaIntegratedDriver(
                target,
                inputs: inputs,
                moduleNode: moduleNode
            )
        } else {
            try self.addCmdWithBuiltinSwiftTool(target, inputs: inputs, cmdOutputs: cmdOutputs)
        }

        self.addTargetCmd(target, cmdOutputs: cmdOutputs)
        try self.addModuleWrapCmd(target)
    }

    private func addSwiftCmdsViaIntegratedDriver(
        _ target: SwiftModuleBuildDescription,
        inputs: [Node],
        moduleNode: Node
    ) throws {
        // Use the integrated Swift driver to compute the set of frontend
        // jobs needed to build this Swift module.
        var commandLine = try target.emitCommandLine()
        commandLine.append("-driver-use-frontend-path")
        commandLine.append(target.buildParameters.toolchain.swiftCompilerPath.pathString)
        // FIXME: At some point SwiftPM should provide its own executor for
        // running jobs/launching processes during planning
        let resolver = try ArgsResolver(fileSystem: target.fileSystem)
        let executor = SPMSwiftDriverExecutor(
            resolver: resolver,
            fileSystem: target.fileSystem,
            env: Environment.current
        )
        var driver = try Driver(
            args: commandLine,
            diagnosticsOutput: .handler(self.observabilityScope.makeDiagnosticsHandler()),
            fileSystem: self.fileSystem,
            executor: executor,
            compilerIntegratedTooling: false
        )
        try driver.checkLDPathOption(commandLine: commandLine)

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
        for targetDescription: SwiftModuleBuildDescription,
        jobs: [Job],
        inputs: [Node],
        resolver: ArgsResolver,
        isMainModule: (Job) -> Bool,
    ) throws {
        // Add build jobs to the manifest
        for job in jobs {
            let tool = try resolver.resolve(.path(job.tool))
            let commandLine = try job.commandLine.map { try resolver.resolve($0) }
            let arguments = [tool] + commandLine

            let jobInputs = try job.inputs.map { try $0.resolveToNode(fileSystem: self.fileSystem) }
            let jobOutputs = try job.outputs.map { try $0.resolveToNode(fileSystem: self.fileSystem) }

            // Add module dependencies as inputs to the main module build command.
            //
            // Jobs for a module's intermediate build artifacts, such as PCMs or
            // modules built from a .swiftinterface, do not have a
            // dependency on cross-module build products. If multiple targets share
            // common intermediate dependency modules, such dependencies can lead
            // to cycles in the resulting manifest.
            var manifestNodeInputs: [Node] = []
            if !isMainModule(job) {
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

    private func addCmdWithBuiltinSwiftTool(
        _ target: SwiftModuleBuildDescription,
        inputs: [Node],
        cmdOutputs: [Node]
    ) throws {
        let isLibrary = target.target.type == .library || target.target.type == .test
        let cmdName = target.getCommandName()

        self.manifest.addWriteSourcesFileListCommand(sources: target.sources, sourcesFileListPath: target.sourcesFileListPath)
        let outputFileMapPath = target.tempsPath.appending("output-file-map.json")
        // FIXME: Eliminate side effect.
        try target.writeOutputFileMap(to: outputFileMapPath)
        self.manifest.addSwiftCmd(
            name: cmdName,
            inputs: inputs + [Node.file(target.sourcesFileListPath)],
            outputs: cmdOutputs,
            executable: target.buildParameters.toolchain.swiftCompilerPath,
            moduleName: target.target.c99name,
            moduleAliases: target.target.moduleAliases,
            moduleOutputPath: target.moduleOutputPath,
            importPath: target.modulesPath,
            tempsPath: target.tempsPath,
            objects: try target.objects,
            otherArguments: try target.compileArguments(),
            sources: target.sources,
            fileList: target.sourcesFileListPath,
            isLibrary: isLibrary,
            wholeModuleOptimization: target.useWholeModuleOptimization,
            outputFileMapPath: outputFileMapPath,
            prepareForIndexing: target.buildParameters.prepareForIndexing != .off
        )
    }

    private func computeSwiftCompileCmdInputs(
        _ target: SwiftModuleBuildDescription
    ) throws -> [Node] {
        var inputs = target.sources.map(Node.file)

        let swiftVersionFilePath = addSwiftGetVersionCommand(buildParameters: target.buildParameters)
        inputs.append(.file(swiftVersionFilePath))

        // Add resources node as the input to the module. This isn't great because we
        // don't need to block building of a module until its resources are assembled but
        // we don't currently have a good way to express that resources should be built
        // whenever a module is being built.
        if let resourcesNode = try createResourcesBundle(for: .swift(target)) {
            inputs.append(resourcesNode)
        }

        if let resourcesEmbeddingSource = target.resourcesEmbeddingSource {
            let resourceFilesToEmbed = target.resourceFilesToEmbed
            self.manifest.addWriteEmbeddedResourcesCommand(resources: resourceFilesToEmbed, outputPath: resourcesEmbeddingSource)
        }

        let prepareForIndexing = target.buildParameters.prepareForIndexing

        func addStaticTargetInputs(_ module: ResolvedModule, _ description: ModuleBuildDescription?) throws {
            // Ignore C Modules.
            if module.underlying is SystemLibraryModule { return }
            // Ignore Binary Modules.
            if module.underlying is BinaryModule { return }
            // Ignore Plugin Modules.
            if module.underlying is PluginModule { return }

            guard let description else {
                throw InternalError("No build description for module: \(module)")
            }

            // Depend on the binary for executable targets.
            if module.type == .executable && prepareForIndexing == .off {
                // FIXME: Optimize. Build plan could build a mapping between executable modules
                // and their products to speed up search here, which is inefficient if the plan
                // contains a lot of products.
                if let productDescription = try plan.productMap.values.first(where: {
                    try $0.product.type == .executable &&
                        $0.product.executableModule.id == module.id &&
                        $0.destination == description.destination
                }) {
                    try inputs.append(file: productDescription.binaryPath)
                }
                return
            }

            switch description {
            case .swift(let swiftDescription):
                inputs.append(file: swiftDescription.moduleOutputPath)
            case .clang(let clangDescription):
                if prepareForIndexing != .off {
                    // In preparation, we're only building swiftmodules
                    // propagate the dependency to the header files in this target
                    for header in clangDescription.clangTarget.headers {
                        inputs.append(file: header)
                    }
                } else {
                    for object in try clangDescription.objects {
                        inputs.append(file: object)
                    }
                }
            }
        }

        for dependency in target.dependencies(using: self.plan) {
            switch dependency {
            case .module(let module, let description):
                try addStaticTargetInputs(module, description)

            case .product(let product, let productDescription):
                switch product.type {
                case .executable, .snippet, .library(.dynamic), .macro:
                    guard let productDescription else {
                        throw InternalError("No description for product: \(product)")
                    }
                    // Establish a dependency on binary of the product.
                    try inputs.append(file: productDescription.binaryPath)

                // For automatic and static libraries, and plugins, add their targets as static input.
                case .library(.automatic), .library(.static), .plugin:
                    for module in product.modules {
                        let description = self.plan.description(
                            for: module,
                            context: product.type == .plugin ? .host : target.destination
                        )
                        try addStaticTargetInputs(module, description)
                    }

                case .test:
                    break
                }
            }
        }

        for binaryPath in target.libraryBinaryPaths {
            let path = target.buildParameters.destinationPath(forBinaryAt: binaryPath)
            if self.fileSystem.isDirectory(binaryPath) {
                inputs.append(directory: path)
            } else {
                inputs.append(file: path)
            }
        }

        let additionalInputs = try self.addBuildToolPlugins(.swift(target))

        // Depend on any required macro's output.
        try target.requiredMacros.forEach { macro in
            inputs.append(.virtual(getLLBuildTargetName(
                macro: macro,
                buildParameters: target.macroBuildParameters
            )))
        }

        return inputs + additionalInputs
    }

    /// Adds a top-level phony command that builds the entire module.
    private func addTargetCmd(_ target: SwiftModuleBuildDescription, cmdOutputs: [Node]) {
        // Create a phony node to represent the entire module.
        let targetName = target.getLLBuildTargetName()
        let targetOutput: Node = .virtual(targetName)

        self.manifest.addNode(targetOutput, toTarget: targetName)
        self.manifest.addPhonyCmd(
            name: targetOutput.name,
            inputs: cmdOutputs,
            outputs: [targetOutput]
        )
        if self.plan.graph.isInRootPackages(target.target, satisfying: target.buildParameters.buildEnvironment) {
            if !target.isTestTarget {
                self.addNode(targetOutput, toTarget: .main)
            }
            self.addNode(targetOutput, toTarget: .test)
        }
    }

    private func addModuleWrapCmd(_ target: SwiftModuleBuildDescription) throws {
        // Add commands to perform the module wrapping Swift modules when debugging strategy is `modulewrap`.
        guard target.buildParameters.debuggingStrategy == .modulewrap else { return }
        var moduleWrapArgs = [
            target.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-modulewrap", target.moduleOutputPath.pathString,
            "-o", target.wrappedModuleOutputPath.pathString,
        ]
        moduleWrapArgs += try target.buildParameters.tripleArgs(for: target.target)
        self.manifest.addShellCmd(
            name: target.wrappedModuleOutputPath.pathString,
            description: "Wrapping AST for \(target.target.name) for debugging",
            inputs: [.file(target.moduleOutputPath)],
            outputs: [.file(target.wrappedModuleOutputPath)],
            arguments: moduleWrapArgs
        )
    }

    private func addSwiftGetVersionCommand(buildParameters: BuildParameters) -> AbsolutePath {
        let swiftCompilerPath = buildParameters.toolchain.swiftCompilerPath

        // If we are already tracking this compiler, we can re-use the existing command by just returning the tracking file.
        if let swiftVersionFilePath = swiftGetVersionFiles[swiftCompilerPath] {
            return swiftVersionFilePath
        }

        // Otherwise, come up with a path for the new file and generate a command to populate it.
        let swiftCompilerPathHash = String(swiftCompilerPath.pathString.hash, radix: 16, uppercase: true)
        let swiftVersionFilePath = buildParameters.buildPath.appending(component: "swift-version-\(swiftCompilerPathHash).txt")
        self.manifest.addSwiftGetVersionCommand(swiftCompilerPath: swiftCompilerPath, swiftVersionFilePath: swiftVersionFilePath)
        swiftGetVersionFiles[swiftCompilerPath] = swiftVersionFilePath
        return swiftVersionFilePath
    }
}

extension TypedVirtualPath {
    /// Resolve a typed virtual path provided by the Swift driver to
    /// a node in the build graph.
    fileprivate func resolveToNode(fileSystem: some FileSystem) throws -> Node {
        if let absolutePath = (file.absolutePath.flatMap { AbsolutePath($0) }) {
            return Node.file(absolutePath)
        } else if let relativePath = (file.relativePath.flatMap { RelativePath($0) }) {
            guard let workingDirectory: AbsolutePath = fileSystem.currentWorkingDirectory else {
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

extension Driver {
    func checkLDPathOption(commandLine: [String]) throws {
        // `-ld-path` option is only available in recent versions of the compiler: rdar://117049947
        if let option = commandLine.first(where: { $0.hasPrefix("-ld-path") }),
           !self.supportedFrontendFeatures.contains("ld-path-driver-option") {
            throw LLBuildManifestBuilder.Error.ldPathDriverOptionUnavailable(option: option)
        }
    }
}

extension SwiftModuleBuildDescription {
    public func getCommandName() -> String {
        "C." + self.getLLBuildTargetName()
    }

    public func getLLBuildTargetName() -> String {
        self.target.getLLBuildTargetName(buildParameters: self.buildParameters)
    }
}
