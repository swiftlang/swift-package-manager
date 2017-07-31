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
public struct LLBuildManifestGenerator {

    /// The name of the llbuild target that builds all products and targets (excluding tests).
    public static let llbuildMainTargetName = "main"

    /// The name of the llbuild target that builds all products and targets (including tests).
    public static let llbuildTestTargetName = "test"

    /// The build plan to work on.
    public let plan: BuildPlan

    /// Create a new generator with a build plan.
    public init(_ plan: BuildPlan) {
        self.plan = plan
    }

    /// A structure for targets in the manifest.
    private struct Targets {

        /// Main target.
        private(set) var main = Target(name: LLBuildManifestGenerator.llbuildMainTargetName)

        /// Test target.
        private(set) var test = Target(name: LLBuildManifestGenerator.llbuildTestTargetName)

        /// All targets.
        var allTargets: [Target] {
            return [main, test] + otherTargets
        }

        /// All commands.
        private(set) var allCommands = SortedArray<Command>(areInIncreasingOrder: <)

        /// Other targets.
        private var otherTargets: [Target] = []

        /// Append a command.
        mutating func append(_ target: Target, isTest: Bool) {
            // Create a phony command with a virtual output node that represents the target.
            let virtualNodeName = "<\(target.name)>"
            let phonyTool = PhonyTool(inputs: target.outputs, outputs: [virtualNodeName])
            let phonyCommand = Command(name: "<C.\(target.name)>", tool: phonyTool)

            // Use the phony command as dependency.
            var newTarget = target
            newTarget.outputs = [virtualNodeName]
            newTarget.cmds.insert(phonyCommand)
            otherTargets.append(newTarget)

            if !isTest {
                main.outputs += newTarget.outputs
                main.cmds += newTarget.cmds
            }

            // Always build everything for the test target.
            test.outputs += newTarget.outputs
            test.cmds += newTarget.cmds
            allCommands += newTarget.cmds
        }
    }

    /// Generate manifest at the given path.
    public func generateManifest(at path: AbsolutePath) throws {
        var targets = Targets()

        // Create commands for all target description in the plan.
        for buildTarget in plan.targets {
            switch buildTarget {
            case .swift(let target):
                targets.append(createSwiftCompileTarget(target), isTest: target.isTestTarget)
            case .clang(let target):
                targets.append(createClangCompileTarget(target), isTest: target.isTestTarget)
            }
        }

        // Create command for all products in the plan.
        for buildProduct in plan.buildProducts {
            targets.append(createProductTarget(buildProduct), isTest: buildProduct.product.type == .test)
        }

        // Write the manifest.
        let stream = BufferedOutputByteStream()
        stream <<< """
            client:
              name: swift-build
            tools: {}
            targets:\n
            """
        for target in targets.allTargets {
            stream <<< "  " <<< Format.asJSON(target.name)
            stream <<< ": " <<< Format.asJSON(target.outputs) <<< "\n"
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

    /// Create a llbuild target for a product description.
    private func createProductTarget(_ buildProduct: ProductBuildDescription) -> Target {
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

        var target = Target(name: buildProduct.product.llbuildTargetName)
        target.outputs = tool.outputs
        target.cmds.insert(Command(name: buildProduct.product.commandName, tool: tool))
        return target
    }

    /// Create a llbuild target for a Swift target description.
    private func createSwiftCompileTarget(_ target: SwiftTargetDescription) -> Target {
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

        var buildTarget = Target(name: target.target.llbuildTargetName)
        // The target only cares about the module output.
        buildTarget.outputs = [target.moduleOutputPath.asString]
        let tool = SwiftCompilerTool(target: target, inputs: inputs.values)
        buildTarget.cmds.insert(Command(name: target.target.commandName, tool: tool))
        return buildTarget
    }

    /// Create a llbuild target for a Clang target description.
    private func createClangCompileTarget(_ target: ClangTargetDescription) -> Target {
        let commands: [Command] = target.compilePaths().map({ path in
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

        // For Clang, the target requires all command outputs.
        var buildTarget = Target(name: target.target.llbuildTargetName)            
        buildTarget.outputs = commands.flatMap({ $0.tool.outputs })
        buildTarget.cmds += commands
        return buildTarget
    }
}

extension ResolvedTarget {
    public var llbuildTargetName: String {
        return "\(name).module"
    }

    var commandName: String {
        return "C.\(llbuildTargetName)"
    }
}

extension ResolvedProduct {
    public var llbuildTargetName: String {
        switch type {
        case .library(.dynamic):
            return "\(name).dylib"
        case .test:
            return "\(name).test"
        case .library(.static):
            return "\(name).a"
        case .library(.automatic):
            fatalError()
        case .executable:
            return "\(name).exe"
        }
    }

    var commandName: String {
        return "C.\(llbuildTargetName)"
    }
}
