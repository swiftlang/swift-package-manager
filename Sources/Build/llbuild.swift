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

    /// Path to the resolved file.
    let resolvedFile: AbsolutePath

    /// The name of the build manifest renegeration node.
    var buildManifestRegenerationNode: String {
        return "<C.build.manifest.regeneration>"
    }

    /// Create a new generator with a build plan.
    public init(_ plan: BuildPlan, resolvedFile: AbsolutePath) {
        self.plan = plan
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

            if buildByDefault {
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
        var targets = Targets()

        // Create commands for all target description in the plan.
        for (target, description) in plan.targetMap {
            switch description {
            case .swift(let description):
                // Only build targets by default if they are reachabe from a root target.
                targets.append(createSwiftCompileTarget(description),
                    buildByDefault: plan.graph.reachableTargets.contains(target),
                    isTest: description.isTestTarget)
            case .clang(let description):
                targets.append(createClangCompileTarget(description),
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
              name: swift-build
            tools: {}
            targets:\n
            """
        for target in targets.allTargets {
            stream <<< "  " <<< Format.asJSON(target.name)
            stream <<< ": " <<< Format.asJSON(target.outputs.values) <<< "\n"
        }

        if plan.buildParameters.shouldEnableManifestCaching {
            stream <<< "  " <<< Format.asJSON("regenerate")
            stream <<< ": " <<< Format.asJSON([buildManifestRegenerationNode])
            stream <<< "\n"
        }

        stream <<< "default: " <<< Format.asJSON(targets.main.name) <<< "\n"

        // Add manifest regeneration directory nodes as directory structure.
        let manifestRegenerationInputs = self.manifestRegenerationInputs()
        if let manifestRegenerationInputs = manifestRegenerationInputs, !manifestRegenerationInputs.dirs.isEmpty {
            stream <<< "nodes:\n"
            for dir in manifestRegenerationInputs.dirs {
                stream <<< "  " <<< Format.asJSON(dir) <<< ":\n"
                stream <<< "    is-directory-structure: true\n"
            }
        }
        
        stream <<< "commands: \n"
        for command in targets.allCommands.sorted(by: { $0.name < $1.name }) {
            stream <<< "  " <<< Format.asJSON(command.name) <<< ":\n"
            command.tool.append(to: stream)
            stream <<< "\n"
        }

        if let manifestRegenerationInputs = manifestRegenerationInputs {
            // Add command for computing manifest regeneration.
            let regenerationCommand = ShellTool(
                description: "",
                inputs: manifestRegenerationInputs.dirs + manifestRegenerationInputs.files,
                outputs: [buildManifestRegenerationNode],
                args: ["echo 1 > " + plan.buildParameters.regenerateManifestToken.asString],
                allowMissingInputs: true
            )
            stream <<< "  " <<< Format.asJSON(plan.buildParameters.regenerateManifestToken.asString) <<< ":\n"
            regenerationCommand.append(to: stream)
        }
        
        try localFileSystem.writeFileContents(path, bytes: stream.bytes)
    }
    
    private func manifestRegenerationInputs() -> (dirs: [String], files: [String])? {
        // If manifest caching is not enabled, just return nil from here.
        guard plan.buildParameters.shouldEnableManifestCaching else { return nil }

        var directoryNodesToTrack: [AbsolutePath] = []
        var filesToTrack: [AbsolutePath] = []
        
        let graph = plan.graph
        
        for package in graph.packages {
            // Track the package manifest.
            filesToTrack.append(package.underlyingPackage.manifest.path)
            
            if graph.isRootPackage(package) {
                // Track individual targets for root packages.
                for target in package.targets {
                    directoryNodesToTrack.append(target.sources.root)
                }
            } else {
                // Track the entire package and their package manifest.
                directoryNodesToTrack.append(package.path)
            }
        }

        // We also need to track the resolved file.
        filesToTrack.append(resolvedFile)
        return (directoryNodesToTrack.map({ $0.asString + "/" }), filesToTrack.map({ $0.asString }))
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
                description: "Linking \(buildProduct.binary.prettyPath())",
                inputs: inputs.map({ $0.asString }),
                outputs: [buildProduct.binary.asString],
                args: buildProduct.linkArguments(),
                allowMissingInputs: false
            )
        }

        var target = Target(name: buildProduct.product.llbuildTargetName)
        target.outputs.insert(contentsOf: tool.outputs)
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
            if target.underlyingTarget is SystemLibraryTarget { return }
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
        buildTarget.outputs.insert(target.moduleOutputPath.asString)
        let tool = SwiftCompilerTool(target: target, inputs: inputs.values)
        buildTarget.cmds.insert(Command(name: target.target.commandName, tool: tool))
        return buildTarget
    }

    /// Create a llbuild target for a Clang target description.
    private func createClangCompileTarget(_ target: ClangTargetDescription) -> Target {

        let standards = [
            (target.clangTarget.cxxLanguageStandard, SupportedLanguageExtension.cppExtensions),
            (target.clangTarget.cLanguageStandard, SupportedLanguageExtension.cExtensions),
        ]

        let commands: [Command] = target.compilePaths().map({ path in
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
                args: [plan.buildParameters.toolchain.clangCompiler.asString] + args,
                deps: path.deps.asString)
            return Command(name: path.object.asString, tool: clang)
        })

        // For Clang, the target requires all command outputs.
        var buildTarget = Target(name: target.target.llbuildTargetName)            
        buildTarget.outputs.insert(contentsOf: commands.flatMap({ $0.tool.outputs }))
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
