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
import PackageExtension

struct BuildTargetBuildContext: TargetBuildContext {
    let targetName: String
    let inputs: [String]
    let buildDirectory: String
    let targetBuildDirectory: String
}

class LLBuildTaskGeneration: TaskGenerationDelegate {
    func createCommand(inputs: [String], outputs: [String], commandLine: [String], description: String) {
        let tool = ShellTool(
            description: description,
            inputs: inputs,
            outputs: outputs,
            args: commandLine,
            allowMissingInputs: false
        )
        tools.append(tool)
    }

    func declareSwiftSource(_ path: String) {
        swiftSources.append(path)
    }

    var tools: [ShellTool] = []
    var swiftSources: [String] = []
}

/// llbuild manifest file generator for a build plan.
public struct LLBuildManifestGenerator {

    /// The name of the llbuild target that builds all products and targets (excluding tests).
    public static let llbuildMainTargetName = "main"

    /// The name of the llbuild target that builds all products and targets (including tests).
    public static let llbuildTestTargetName = "test"

    /// The build plan to work on.
    public let plan: BuildPlan

    /// The manifest client name.
    public let client: String

    /// Path to the resolved file.
    let resolvedFile: AbsolutePath

    /// Create a new generator with a build plan.
    public init(_ plan: BuildPlan, client: String, resolvedFile: AbsolutePath) {
        self.plan = plan
        self.client = client
        self.resolvedFile = resolvedFile
    }

    /// A structure for targets in the manifest.
    private struct Targets {

        /// Main target.
        private(set) var main = Target(name: LLBuildManifestGenerator.llbuildMainTargetName)

        /// Test target.
        private(set) var test = Target(name: LLBuildManifestGenerator.llbuildTestTargetName)

        /// All targets.
        var allTargets: [Target] {
            return [main, test] + otherTargets.sorted(by: { $0.name < $1.name })
        }

        /// All commands.
        private(set) var allCommands = SortedArray<Command>(areInIncreasingOrder: <)

        /// Other targets.
        private var otherTargets: [Target] = []

        let buildPackageExtMode: Bool

        init(buildPackageExtMode: Bool) {
            self.buildPackageExtMode = buildPackageExtMode
        }

        /// Append a command.
        mutating func append(_ target: Target, buildByDefault: Bool, isTest: Bool) {

            // Create a phony command with a virtual output node that represents the target.
            let virtualNodeName = "<\(target.name)>"
            let phonyTool = PhonyTool(inputs: target.outputs.values, outputs: [virtualNodeName])
            let phonyCommand = Command(name: "<C.\(target.name)>", tool: phonyTool)

            // Use the phony command as dependency.
            var newTarget = target
            newTarget.outputs.insert(virtualNodeName)
            newTarget.cmds.insert(phonyCommand)
            otherTargets.append(newTarget)

            // Jugad to always build extensions.
            if buildPackageExtMode || buildByDefault {
                if !isTest {
                    main.outputs += newTarget.outputs
                    main.cmds += newTarget.cmds
                }

                // Always build everything for the test target.
                test.outputs += newTarget.outputs
                test.cmds += newTarget.cmds
            }

            allCommands += newTarget.cmds
        }
    }

    /// Generate manifest at the given path.
    public func generateManifest(at path: AbsolutePath) throws {

        var targets = Targets(buildPackageExtMode: plan.buildPackageExtMode)

        // Create commands for all target description in the plan.
        for (target, description) in plan.targetMap {
            switch description {
            case .swift(let description):
                // Only build targets by default if they are reachabe from a root target.
                targets.append(createSwiftCompileTarget(description),
                    buildByDefault: plan.graph.reachableTargets.contains(target),
                    isTest: description.isTestTarget)
            case .clang(let description):
                targets.append(try createClangCompileTarget(description),
                    buildByDefault: plan.graph.reachableTargets.contains(target),
                    isTest: description.isTestTarget)
            }
        }

        // Create command for all products in the plan.
        for (product, description) in plan.productMap {
            // Only build products by default if they are reachabe from a root target.
            targets.append(createProductTarget(description),
                buildByDefault: plan.graph.reachableProducts.contains(product),
                isTest: product.type == .test)
        }

        // Write the manifest.
        let stream = BufferedOutputByteStream()
        stream <<< """
            client:
              name: \(client)
            tools: {}
            targets:\n
            """
        for target in targets.allTargets {
            stream <<< "  " <<< Format.asJSON(target.name)
            stream <<< ": " <<< Format.asJSON(target.outputs.values) <<< "\n"
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

            let ds = plan.computeDependencies(of: buildProduct.product).staticTargets
            var extraObjects: [String] = []
            for d in ds {
                if let tar = plan.targetMap[d]?.swift {
                    extraObjects += tar.additionalObjects.map({ $0.asString })
                }
            }

            tool = ShellTool(
                description: "Linking \(buildProduct.binary.prettyPath())",
                inputs: inputs.map({ $0.asString }) + extraObjects,
                outputs: [buildProduct.binary.asString],
                args: buildProduct.linkArguments() + extraObjects,
                allowMissingInputs: false
            )
        }

        let buildConfig = plan.buildParameters.configuration.dirname
        var target = Target(name: buildProduct.product.getLLBuildTargetName(config: buildConfig))
        target.outputs.insert(contentsOf: tool.outputs)
        target.cmds.insert(Command(name: buildProduct.product.getCommandName(config: buildConfig), tool: tool))
        return target
    }

    /// Create a llbuild target for a Swift target description.
    private func createSwiftCompileTarget(_ target: SwiftTargetBuildDescription) -> Target {
        // Compute inital inputs.
        var inputs = SortedArray<String>()
        inputs += target.target.sources.paths.map({ $0.asString })

        func addStaticTargetInputs(_ target: ResolvedTarget) {
            // Ignore C Modules.
            if target.underlyingTarget is SystemLibraryTarget { return }
            switch plan.targetMap[target] {
            case .swift(let target)?:
                inputs.insert(target.moduleOutputPath.asString)
            case .clang(let target)?:
                inputs += target.objects.map({ $0.asString })
            case nil:
                break
                //fatalError("unexpected: target \(target) not in target map \(plan.targetMap)")
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
                    if let p = plan.productMap[product] {
                        inputs += [p.binary.asString]
                    }

                // For automatic and static libraries, add their targets as static input.
                case .library(.automatic), .library(.static):
                    for target in product.targets {
                        addStaticTargetInputs(target)
                    }
                case .test:
                    break
                case .packageExt:
                    break
                }
            }
        }

        // Add dependency to custom build rules.
        let customBuildRules = OrderedSet(target.target.sources.codegenPaths.map({ $0.buildRule }))
        var extinputs = SortedArray<String>()
        if !customBuildRules.isEmpty {
            // Find the target for this build rule.
            let packageExtTargets = plan.graph.allTargets.filter({ $0.type == .packageExt })
            for t in packageExtTargets {
                for d in t.dependencies {
                    switch d {
                    case .target(let target):

                        if let p = plan.buildProducts.filter({ $0.product.targets == [target] }).first {
                            extinputs += [p.binary.asString]
                        }

                        // FIXME: unhandled target dependencies.

                    case .product(let product):
                        if let p = plan.productMap[product] {
                            extinputs += [p.binary.asString]
                        }
                    }
                }
            }
        }

        let buildConfig = plan.buildParameters.configuration.dirname
        let commandName = target.target.getCommandName(config: buildConfig)

        // Custom commands.
        var customCommands: [Command] = []
        do {
            for buildRuleName in customBuildRules {
                let buildRuleType = SwiftPackageManager.default.buildRules[buildRuleName]!
                let buildRule = buildRuleType.init()

                let inputFiles = target.target.sources.codegenPaths.filter({ $0.buildRule == buildRuleName }).map({ $0.path })
                let inputs = inputFiles.map({ target.target.sources.root.appending($0) }).map({ $0.asString })

                let buildContext = BuildTargetBuildContext(
                    targetName: target.target.name,
                    inputs: inputs,
                    buildDirectory: plan.buildParameters.buildPath.asString,
                    targetBuildDirectory: target.tempsPath.asString
                )

                let delegate = LLBuildTaskGeneration()
                try! buildRule.constructTasks(target: buildContext, delegate: delegate)

                target.additionalSources += delegate.swiftSources.map({ AbsolutePath($0) })

                for (idx, tool) in delegate.tools.enumerated() {
                    let buildRuleCommandName = "<custom-\(buildRuleName)-\(commandName)-\(idx)>"

                    var tool = tool
                    tool.inputs += extinputs.values
                    tool.outputs += [buildRuleCommandName]

                    customCommands.append(Command(name: buildRuleCommandName, tool: tool))
                }
            }
        }

        inputs.insert(contentsOf: target.additionalSources.map({ $0.asString }))

        var buildTarget = Target(name: target.target.getLLBuildTargetName(config: buildConfig))
        // The target only cares about the module output.
        buildTarget.outputs.insert(target.moduleOutputPath.asString)

        let tool = SwiftCompilerTool(target: target, inputs: inputs.values)
        buildTarget.cmds.insert(Command(name: commandName, tool: tool))

        for command in customCommands {
            buildTarget.cmds.insert(command)
            buildTarget.outputs.insert(command.name)
        }

        return buildTarget
    }

    /// Create a llbuild target for a Clang target description.
    private func createClangCompileTarget(_ target: ClangTargetBuildDescription) throws -> Target {

        let standards = [
            (target.clangTarget.cxxLanguageStandard, SupportedLanguageExtension.cppExtensions),
            (target.clangTarget.cLanguageStandard, SupportedLanguageExtension.cExtensions),
        ]

        let commands: [Command] = try target.compilePaths().map({ path in
            var args = target.basicArguments()
            args += ["-MD", "-MT", "dependencies", "-MF", path.deps.asString]

            // Add language standard flag if needed.
            if let ext = path.source.extension {
                for (standard, validExtensions) in standards {
                    if let languageStandard = standard, validExtensions.contains(ext) {
                        args += ["-std=\(languageStandard)"]
                    }
                }
            }

            args += ["-c", path.source.asString, "-o", path.object.asString]
            let clang = ClangTool(
                desc: "Compile \(target.target.name) \(path.filename.asString)",
                //FIXME: Should we add build time dependency on dependent targets?
                inputs: [path.source.asString],
                outputs: [path.object.asString],
                args: [try plan.buildParameters.toolchain.getClangCompiler().asString] + args,
                deps: path.deps.asString)
            return Command(name: path.object.asString, tool: clang)
        })

        // For Clang, the target requires all command outputs.
        var buildTarget = Target(name: target.target.getLLBuildTargetName(config: plan.buildParameters.configuration.dirname))
        buildTarget.outputs.insert(contentsOf: commands.flatMap({ $0.tool.outputs }))
        buildTarget.cmds += commands
        return buildTarget
    }
}

extension ResolvedTarget {
    public func getCommandName(config: String) -> String {
       return "C." + getLLBuildTargetName(config: config)
    }

    public func getLLBuildTargetName(config: String) -> String {
        return "\(name)-\(config).module"
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
        case .packageExt:
            return "\(name)-\(config).ext"
        }
    }

    public func getCommandName(config: String) -> String {
        return "C." + getLLBuildTargetName(config: config)
    }
}
