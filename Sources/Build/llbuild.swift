/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility
import PackageModel
import PackageGraph

/// llbuild manifest file generator for a build plan.
public struct LLbuildManifestGenerator {

    /// The build plan to work on.
    public let plan: BuildPlan

    /// Create a new generator with a build plan.
    public init(_ plan: BuildPlan) {
        self.plan = plan
    }

    /// A structure for targets in the manifest.
    private struct Targets {

        /// Main target.
        private(set) var main = Target(name: "main", cmds: [])

        /// Test target.
        private(set) var test = Target(name: "test", cmds: [])

        /// All commands.
        private(set) var allCommands: [Command] = []

        /// Append a command.
        mutating func append(_ command: Command, isTest: Bool) {
            append([command], isTest: isTest)
        }

        /// Append an array of commands.
        mutating func append(_ commands: [Command], isTest: Bool) {
            if !isTest {
                main.cmds += commands
            }
            // Always build everything for the test target.
            test.cmds += commands
            allCommands += commands
        }
    }

    /// Generate manifest at the given path.
    public func generateManifest(at path: AbsolutePath) throws {
        var targets = Targets()

        // Create commands for all target description in the plan.
        for buildTarget in plan.targets {
            switch buildTarget {
            case .swift(let target):
                targets.append(createSwiftCommand(target), isTest: target.module.isTest)
            case .clang(let target):
                targets.append(createClangCommands(target), isTest: target.module.isTest)
            }
        }

        // Create command for all products in the plan.
        for buildProduct in plan.buildProducts {
            targets.append(createLinkCommand(buildProduct), isTest: buildProduct.product.isTest)
        }

        // Write the manifest.
        let stream = BufferedOutputByteStream()
        stream <<< "client:\n"
        stream <<< "  name: swift-build\n"
        stream <<< "tools: {}\n"
        stream <<< "targets:\n"
        for target in [targets.test, targets.main] {
            stream <<< "  " <<< Format.asJSON(target.name) <<< ": " <<< Format.asJSON(target.cmds.flatMap{$0.tool.outputs}) <<< "\n"
        }
        stream <<< "default: " <<< Format.asJSON(targets.main.name) <<< "\n"
        stream <<< "commands: \n"
        for command in targets.allCommands {
            stream <<< "  " <<< Format.asJSON(command.name) <<< ":\n"
            command.tool.append(to: stream)
            stream <<< "\n"
        }
        try localFileSystem.writeFileContents(path, bytes: stream.bytes)
    }

    /// Create link command for products.
    private func createLinkCommand(_ buildProduct: ProductBuildDescription) -> Command {
        let tool: ToolProtocol
        // Create archive tool for static library and shell tool for rest of the products.
        if buildProduct.product.type == .Library(.Static) {
            tool = ArchiveTool(inputs: buildProduct.objects.map{$0.asString}, outputs: [buildProduct.binary.asString])
        } else {
            tool = ShellTool(
                description: "Linking \(buildProduct.binary.prettyPath)",
                inputs: buildProduct.objects.map{$0.asString},
                outputs: [buildProduct.binary.asString],
                args: buildProduct.linkArguments())
        }
        return Command(name: buildProduct.product.targetName, tool: tool)
    }

    /// Create command for Swift target description.
    private func createSwiftCommand(_ target: SwiftTargetDescription) -> Command {
        // Compute inputs.
        var inputs = target.module.sources.paths.map{ $0.asString }
        for dependency in target.module.dependencies {
            // Ignore C Modules.
            if dependency is CModule { continue }
            switch plan.targetMap[dependency] {
            case .swift(let target)?:
                inputs += [target.moduleOutputPath.asString]
            case .clang(let target)?:
                inputs += target.objects.map{$0.asString}
            case nil:
                fatalError("unexpected: module \(dependency) not in target map \(plan.targetMap)")
            }
        }

        let tool = SwiftCompilerTool(target: target, inputs: inputs)
        return Command(name: target.module.targetName, tool: tool)
    }

    /// Create commands for Clang targets.
    private func createClangCommands(_ target: ClangTargetDescription) -> [Command] {
        return target.compilePaths().map { path in
            var args = target.basicArguments()
            args += ["-MD", "-MT", "dependencies", "-MF", path.deps.asString]
            args += ["-c", path.source.asString, "-o", path.object.asString]
            let clang = ClangTool(desc: "Compile \(target.module.name) \(path.filename.asString)",
                                  //FIXME: Should we add build time dependency on dependent modules?
                                  inputs: [path.source.asString],
                                  outputs: [path.object.asString],
                                  args: [plan.buildParameters.toolchain.clangCompiler.asString] + args,
                                  deps: path.deps.asString)
            return Command(name: path.object.asString, tool: clang)
        }
    }
}

/// Swift compiler llbuild tool.
// FIXME: Remove the old SwiftcTool once we completely shift to the new Build model.
struct SwiftCompilerTool: ToolProtocol {

    /// Inputs to the tool.
    let inputs: [String]

    /// Outputs produced by the tool.
    var outputs: [String] {
        return target.objects.map{ $0.asString } + [target.moduleOutputPath.asString]
    }

    /// The underlying Swift build target.
    let target: SwiftTargetDescription

    init(target: SwiftTargetDescription, inputs: [String]) {
        self.target = target
        self.inputs = inputs
    }

    func append(to stream: OutputByteStream) {
        stream <<< "    tool: swift-compiler\n"
        stream <<< "    executable: " <<< Format.asJSON(target.buildParameters.toolchain.swiftCompiler.asString) <<< "\n"
        stream <<< "    module-name: " <<< Format.asJSON(target.module.c99name) <<< "\n"
        stream <<< "    module-output-path: " <<< Format.asJSON(target.moduleOutputPath.asString) <<< "\n"
        stream <<< "    inputs: " <<< Format.asJSON(inputs) <<< "\n"
        stream <<< "    outputs: " <<< Format.asJSON(outputs) <<< "\n"
        stream <<< "    import-paths: " <<< Format.asJSON([target.buildParameters.buildPath.asString]) <<< "\n"
        stream <<< "    temps-path: " <<< Format.asJSON(target.tempsPath.asString) <<< "\n"
        stream <<< "    objects: " <<< Format.asJSON(target.objects.map{ $0.asString }) <<< "\n"
        stream <<< "    other-args: " <<< Format.asJSON(target.compileArguments()) <<< "\n"
        stream <<< "    sources: " <<< Format.asJSON(target.module.sources.paths.map{ $0.asString }) <<< "\n"
        stream <<< "    is-library: " <<< Format.asJSON(target.module.type == .library) <<< "\n"
        stream <<< "    enable-whole-module-optimization: " <<< Format.asJSON(target.buildParameters.configuration == .release) <<< "\n"
        stream <<< "    num-threads: " <<< Format.asJSON("\(SwiftcTool.numThreads)") <<< "\n"
    }
}
