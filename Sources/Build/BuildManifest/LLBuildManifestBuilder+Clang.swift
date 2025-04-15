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
import SPMBuildCore

extension LLBuildManifestBuilder {
    /// Create a llbuild target for a Clang target description.
    func createClangCompileCommand(
        _ target: ClangModuleBuildDescription
    ) throws {
        var inputs: [Node] = []

        // Add resources node as the input to the target. This isn't great because we
        // don't need to block building of a module until its resources are assembled but
        // we don't currently have a good way to express that resources should be built
        // whenever a module is being built.
        if let resourcesNode = try self.createResourcesBundle(for: .clang(target)) {
            inputs.append(resourcesNode)
        }

        func addStaticTargetInputs(_ description: ModuleBuildDescription?) {
            if case .swift(let desc) = description, desc.target.type == .library {
                inputs.append(file: desc.moduleOutputPath)
            }
        }

        for dependency in target.dependencies(using: self.plan) {
            switch dependency {
            case .module(_, let description):
                addStaticTargetInputs(description)

            case .product(let product, let productDescription):
                switch product.type {
                case .executable, .snippet, .library(.dynamic), .macro:
                    guard let productDescription else {
                        throw InternalError("No build description for product: \(product)")
                    }
                    // Establish a dependency on binary of the product.
                    try inputs.append(file: productDescription.binaryPath)

                case .library(.automatic), .library(.static), .plugin:
                    for module in product.modules {
                        let dependencyDescription = self.plan.description(
                            for: module,
                            context: product.type == .plugin ? .host : target.destination
                        )
                        addStaticTargetInputs(dependencyDescription)
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

        var objectFileNodes: [Node] = []

        for path in try target.compilePaths() {
            let args = try target.emitCommandLine(for: path.source)

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

        let additionalInputs = try addBuildToolPlugins(.clang(target))

        // Create a phony node to represent the entire target.
        let targetName = target.llbuildTargetName
        let output: Node = .virtual(targetName)

        self.manifest.addNode(output, toTarget: targetName)
        self.manifest.addPhonyCmd(
            name: output.name,
            inputs: objectFileNodes + additionalInputs,
            outputs: [output]
        )

        if self.plan.graph.isInRootPackages(target.target, satisfying: target.buildParameters.buildEnvironment) {
            if !target.isTestTarget {
                self.addNode(output, toTarget: .main)
            }
            self.addNode(output, toTarget: .test)
        }
    }

    /// Create a llbuild target for a Clang target preparation
    func createClangPrepareCommand(
        _ target: ClangModuleBuildDescription
    ) throws {
        // Create the node for the target so you can --target it.
        // It is a no-op for index preparation.
        let targetName = target.llbuildTargetName
        let output: Node = .virtual(targetName)
        self.manifest.addNode(output, toTarget: targetName)
    }
}
