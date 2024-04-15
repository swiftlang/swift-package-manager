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

import struct LLBuildManifest.Node
import struct Basics.AbsolutePath
import struct Basics.InternalError
import class Basics.ObservabilityScope
import struct PackageGraph.ResolvedModule
import PackageModel

extension LLBuildManifestBuilder {
    /// Create a llbuild target for a Clang target description.
    func createClangCompileCommand(
        _ buildDescription: ClangModuleBuildDescription
    ) throws {
        var inputs: [Node] = []

        // Add resources node as the input to the target. This isn't great because we
        // don't need to block building of a module until its resources are assembled but
        // we don't currently have a good way to express that resources should be built
        // whenever a module is being built.
        if let resourcesNode = try self.createResourcesBundle(for: .clang(buildDescription)) {
            inputs.append(resourcesNode)
        }

        func addStaticLibraryInputs(_ target: ResolvedModule) {
            if case .swift(let desc)? = self.plan.targetMap[target.id], target.type == .library {
                inputs.append(file: desc.moduleOutputPath)
            }
        }

        for dependency in buildDescription.module.dependencies(satisfying: buildDescription.buildEnvironment) {
            switch dependency {
            case .module(let module, _):
                addStaticLibraryInputs(module)

            case .product(let product, _):
                switch product.type {
                case .executable, .snippet, .library(.dynamic), .macro:
                    guard let planProduct = plan.productMap[product.id] else {
                        throw InternalError("unknown product \(product)")
                    }
                    // Establish a dependency on binary of the product.
                    let binary = try planProduct.binaryPath
                    inputs.append(file: binary)

                case .library(.automatic), .library(.static), .plugin:
                    for module in product.modules {
                        addStaticLibraryInputs(module)
                    }
                case .test:
                    break
                }
            }
        }

        for binaryPath in buildDescription.libraryBinaryPaths {
            let path = buildDescription.buildParameters.destinationPath(forBinaryAt: binaryPath)
            if self.fileSystem.isDirectory(binaryPath) {
                inputs.append(directory: path)
            } else {
                inputs.append(file: path)
            }
        }

        var objectFileNodes: [Node] = []

        for path in try buildDescription.compilePaths() {
            let args = try buildDescription.emitCommandLine(for: path.source)

            let objectFileNode: Node = .file(path.object)
            objectFileNodes.append(objectFileNode)

            self.manifest.addClangCmd(
                name: path.object.pathString,
                description: "Compiling \(buildDescription.module.name) \(path.filename)",
                inputs: inputs + [.file(path.source)],
                outputs: [objectFileNode],
                arguments: args,
                dependencies: path.deps.pathString
            )
        }

        let additionalInputs = try addBuildToolPlugins(.clang(buildDescription))

        // Create a phony node to represent the entire target.
        let targetName = buildDescription.module.getLLBuildTargetName(config: buildDescription.buildParameters.buildConfig)
        let output: Node = .virtual(targetName)

        self.manifest.addNode(output, toTarget: targetName)
        self.manifest.addPhonyCmd(
            name: output.name,
            inputs: objectFileNodes + additionalInputs,
            outputs: [output]
        )

        if self.plan.graph.isInRootPackages(
            buildDescription.module,
            satisfying: buildDescription.buildParameters.buildEnvironment
        ) {
            if !buildDescription.isTestModule {
                self.addNode(output, toTarget: .main)
            }
            self.addNode(output, toTarget: .test)
        }
    }
}
