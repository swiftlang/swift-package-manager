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
        private(set) var main = Target(name: "main")

        /// Test target.
        private(set) var test = Target(name: "test")

        /// All commands.
        private(set) var allCommands = SortedArray<Command>(areInIncreasingOrder: <)

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
                targets.append(createSwiftCommand(target), isTest: target.isTestTarget)
            case .clang(let target):
                targets.append(createClangCommands(target), isTest: target.isTestTarget)
            }
        }

        // Create command for all products in the plan.
        for buildProduct in plan.buildProducts {
            targets.append(createLinkCommand(buildProduct), isTest: buildProduct.product.type == .test)
        }

        // Write the manifest.
        let stream = BufferedOutputByteStream()
        stream <<< "client:\n"
        stream <<< "  name: swift-build\n"
        stream <<< "tools: {}\n"
        stream <<< "targets:\n"
        for target in [targets.test, targets.main] {
            stream <<< "  " <<< Format.asJSON(target.name)
            stream <<< ": " <<< Format.asJSON(target.cmds.flatMap({ $0.tool.outputs })) <<< "\n"
        }
        stream <<< "default: " <<< Format.asJSON(targets.main.name) <<< "\n"
        stream <<< "commands: \n"
        for command in targets.allCommands.sorted(by: { $0.name < $1.name }) {
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
        if buildProduct.product.type == .library(.static) {
            tool = ArchiveTool(
                inputs: buildProduct.objects.map({ $0.asString }),
                outputs: [buildProduct.binary.asString])
        } else {
            let inputs = buildProduct.objects + buildProduct.dylibs.map({ $0.binary })
            tool = ShellTool(
                description: "Linking \(buildProduct.binary.prettyPath)",
                inputs: inputs.map({ $0.asString }),
                outputs: [buildProduct.binary.asString],
                args: buildProduct.linkArguments())
        }
        return Command(name: buildProduct.targetName, tool: tool)
    }

    /// Create command for Swift target description.
    private func createSwiftCommand(_ target: SwiftTargetDescription) -> Command {
        // Compute inital inputs.
        var inputs = SortedArray<String>()
        inputs += target.target.sources.paths.map({ $0.asString })

        func addStaticTargetInputs(_ target: ResolvedTarget) {
            // Ignore C Modules.
            if target.underlyingTarget is CTarget { return }
            switch plan.targetMap[target] {
            case .swift(let target)?:
                inputs.insert(target.moduleOutputPath.asString)
            case .clang(let target)?:
                inputs += target.objects.map({ $0.asString })
            case nil:
                fatalError("unexpected: target \(target) not in target map \(plan.targetMap)")
            }
        }

        for dependency in target.target.dependencies {
            switch dependency {
            case .target(let target):
                addStaticTargetInputs(target)

            case .product(let product):
                switch product.type {
                case .executable, .library(.dynamic):
                    // Establish a dependency on binary of the product.
                    inputs += [plan.productMap[product]!.binary.asString]

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

        let tool = SwiftCompilerTool(target: target, inputs: inputs.values)
        return Command(name: target.target.targetName, tool: tool)
    }

    /// Create commands for Clang targets.
    private func createClangCommands(_ target: ClangTargetDescription) -> [Command] {
        return target.compilePaths().map({ path in
            var args = target.basicArguments()
            args += ["-MD", "-MT", "dependencies", "-MF", path.deps.asString]
            args += ["-c", path.source.asString, "-o", path.object.asString]
            let clang = ClangTool(
                desc: "Compile \(target.target.name) \(path.filename.asString)",
                //FIXME: Should we add build time dependency on dependent targets?
                inputs: [path.source.asString],
                outputs: [path.object.asString],
                args: [plan.buildParameters.toolchain.clangCompiler.asString] + args,
                deps: path.deps.asString)
            return Command(name: path.object.asString, tool: clang)
        })
    }
}

extension ResolvedTarget {
    var targetName: String {
        return "<\(name).module>"
    }
}

extension ProductBuildDescription {
    public var targetName: String {
        switch product.type {
        case .library(.dynamic):
            return "<\(product.name).dylib>"
        case .test:
            return "<\(product.name).test>"
        case .library(.static):
            return "<\(product.name).a>"
        case .library(.automatic):
            fatalError()
        case .executable:
            return "<\(product.name).exe>"
        }
    }
}
