//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Basics.AbsolutePath
import func Basics.depthFirstSearch
import struct Basics.InternalError
import struct Basics.Triple
import struct PackageGraph.ResolvedModule
import struct PackageGraph.ResolvedProduct
import class PackageModel.BinaryModule
import class PackageModel.ClangModule

@_spi(SwiftPMInternal)
import class PackageModel.Module

import class PackageModel.SwiftModule
import class PackageModel.SystemLibraryModule
import struct SPMBuildCore.BuildParameters
import struct SPMBuildCore.ExecutableInfo
import func TSCBasic.topologicalSort

extension BuildPlan {
    /// Plan a product.
    func plan(buildProduct: ProductBuildDescription) throws {
        // Compute the product's dependency.
        let dependencies = try computeDependencies(of: buildProduct)

        // Add flags for system targets.
        for systemModule in dependencies.systemModules {
            guard case let target as SystemLibraryModule = systemModule.underlying else {
                throw InternalError("This should not be possible.")
            }
            // Add pkgConfig libs arguments.
            buildProduct.additionalFlags += try pkgConfig(for: target).libs
        }

        // Add flags for binary dependencies.
        for binaryPath in dependencies.libraryBinaryPaths {
            if binaryPath.extension == "framework" {
                buildProduct.additionalFlags += ["-framework", binaryPath.basenameWithoutExt]
            } else if binaryPath.basename.starts(with: "lib") {
                buildProduct.additionalFlags += ["-l\(binaryPath.basenameWithoutExt.dropFirst(3))"]
            } else {
                self.observabilityScope.emit(error: "unexpected binary framework")
            }
        }

        // Don't link libc++ or libstd++ when building for Embedded Swift.
        // Users can still link it manually for embedded platforms when needed,
        // by providing `-Xlinker -lc++` options via CLI or `Package.swift`.
        if !buildProduct.product.modules.contains(where: \.underlying.isEmbeddedSwiftTarget) {
            // Link C++ if needed.
            // Note: This will come from build settings in future.
            for description in dependencies.staticTargets {
                if case let target as ClangModule = description.module.underlying, target.isCXX {
                    let triple = buildProduct.buildParameters.triple
                    if triple.isDarwin() || triple.isFreeBSD() {
                        buildProduct.additionalFlags += ["-lc++"]
                    } else if triple.isWindows() {
                        // Don't link any C++ library.
                    } else {
                        buildProduct.additionalFlags += ["-lstdc++"]
                    }
                    break
                }
            }
        }

        for description in dependencies.staticTargets {
            switch description.module.underlying {
            case is SwiftModule:
                // Swift targets are guaranteed to have a corresponding Swift description.
                guard case .swift(let description) = description else {
                    throw InternalError("Expected a Swift module: \(description.module)")
                }

                // Based on the debugging strategy, we either need to pass swiftmodule paths to the
                // product or link in the wrapped module object. This is required for properly debugging
                // Swift products. Debugging strategy is computed based on the current platform we're
                // building for and is nil for the release configuration.
                switch buildProduct.buildParameters.debuggingStrategy {
                case .swiftAST:
                    buildProduct.swiftASTs.insert(description.moduleOutputPath)
                case .modulewrap:
                    buildProduct.objects += [description.wrappedModuleOutputPath]
                case nil:
                    break
                }
            default: break
            }
        }

        buildProduct.staticTargets = dependencies.staticTargets.map(\.module)
        buildProduct.dylibs = dependencies.dylibs
        buildProduct.objects += try dependencies.staticTargets.flatMap { try $0.objects }
        buildProduct.libraryBinaryPaths = dependencies.libraryBinaryPaths
        buildProduct.availableTools = dependencies.availableTools
    }

    /// Computes the dependencies of a product.
    private func computeDependencies(
        of productDescription: ProductBuildDescription
    ) throws -> (
        dylibs: [ProductBuildDescription],
        staticTargets: [ModuleBuildDescription],
        systemModules: [ResolvedModule],
        libraryBinaryPaths: Set<AbsolutePath>,
        availableTools: [String: AbsolutePath]
    ) {
        let product = productDescription.product
        /* Prior to tools-version 5.9, we used to erroneously recursively traverse executable/plugin dependencies and statically include their
         targets. For compatibility reasons, we preserve that behavior for older tools-versions. */
        let shouldExcludePlugins = productDescription.package.manifest.toolsVersion >= .v5_9

        // For test targets, we need to consider the first level of transitive dependencies since the first level is
        // always test targets.
        let topLevelDependencies: [PackageModel.Module] = if product.type == .test {
            product.modules.flatMap(\.underlying.dependencies).compactMap {
                switch $0 {
                case .product:
                    nil
                case .module(let target, _):
                    target
                }
            }
        } else {
            []
        }

        // get the dynamic libraries for explicitly linking rdar://108561857
        func recursiveDynamicLibraries(for description: ProductBuildDescription) throws -> [ProductBuildDescription] {
            let dylibs = try computeDependencies(of: description).dylibs
            return try dylibs + dylibs.flatMap { try recursiveDynamicLibraries(for: $0) }
        }

        // Sort the product targets in topological order.
        var allDependencies: [ModuleBuildDescription.Dependency] = []

        do {
            func successors(
                for product: ResolvedProduct,
                destination: BuildParameters.Destination
            ) throws -> [TraversalNode] {
                let productDependencies: [TraversalNode] = product.modules.map {
                    .init(module: $0, context: destination)
                }

                switch product.type {
                case .library(.automatic), .library(.static):
                    return productDependencies
                case .plugin:
                    return shouldExcludePlugins ? [] : productDependencies
                case .library(.dynamic):
                    guard let description = self.description(for: product, context: destination) else {
                        throw InternalError("Could not find a description for product: \(product)")
                    }
                    return try recursiveDynamicLibraries(for: description).map { TraversalNode(
                        product: $0.product,
                        context: $0.destination
                    ) }
                case .test, .executable, .snippet, .macro:
                    return []
                }
            }

            func successors(
                for module: ResolvedModule,
                destination: BuildParameters.Destination
            ) -> [TraversalNode] {
                let isTopLevel = topLevelDependencies.contains(module.underlying) || product.modules
                    .contains(id: module.id)
                let topLevelIsMacro = isTopLevel && product.type == .macro
                let topLevelIsPlugin = isTopLevel && product.type == .plugin
                let topLevelIsTest = isTopLevel && product.type == .test

                if !topLevelIsMacro && !topLevelIsTest && module.type == .macro {
                    return []
                }
                if shouldExcludePlugins, !topLevelIsPlugin && !topLevelIsTest && module.type == .plugin {
                    return []
                }
                return module.dependencies(satisfying: productDescription.buildParameters.buildEnvironment)
                    .map {
                        switch $0 {
                        case .product(let product, _):
                            .init(product: product, context: destination)
                        case .module(let module, _):
                            .init(module: module, context: destination)
                        }
                    }
            }

            let directDependencies = product.modules
                .map { TraversalNode(module: $0, context: productDescription.destination) }

            var uniqueNodes = Set<TraversalNode>(directDependencies)

            try depthFirstSearch(directDependencies) {
                let result: [TraversalNode] = switch $0 {
                case .product(let product, let destination):
                    try successors(for: product, destination: destination)
                case .module(let module, let destination):
                    successors(for: module, destination: destination)
                case .package:
                    []
                }

                return result.filter { uniqueNodes.insert($0).inserted }
            } onNext: { node, _ in
                switch node {
                case .package: break
                case .product(let product, let destination):
                    allDependencies.append(.product(product, self.description(for: product, context: destination)))
                case .module(let module, let destination):
                    allDependencies.append(.module(module, self.description(for: module, context: destination)))
                }
            }
        }

        // Create empty arrays to collect our results.
        var linkLibraries = [ProductBuildDescription]()
        var staticTargets = [ModuleBuildDescription]()
        var systemModules = [ResolvedModule]()
        var libraryBinaryPaths: Set<AbsolutePath> = []
        var availableTools = [String: AbsolutePath]()

        for dependency in allDependencies {
            switch dependency {
            case .module(let module, let description):
                switch module.type {
                // Executable target have historically only been included if they are directly in the product's
                // target list.  Otherwise they have always been just build-time dependencies.
                // In tool version .v5_5 or greater, we also include executable modules implemented in Swift in
                // any test products... this is to allow testing of executables.  Note that they are also still
                // built as separate products that the test can invoke as subprocesses.
                case .executable, .snippet, .macro:
                    if product.modules.contains(id: module.id) {
                        guard let description else {
                            throw InternalError("Could not find a description for module: \(module)")
                        }
                        staticTargets.append(description)
                    } else if product.type == .test && (module.underlying as? SwiftModule)?
                        .supportsTestableExecutablesFeature == true
                    {
                        // Only "top-level" targets should really be considered here, not transitive ones.
                        let isTopLevel = topLevelDependencies.contains(module.underlying) || product.modules
                            .contains(id: module.id)
                        if let toolsVersion = graph.package(for: product)?.manifest.toolsVersion, toolsVersion >= .v5_5,
                           isTopLevel
                        {
                            guard let description else {
                                throw InternalError("Could not find a description for module: \(module)")
                            }
                            staticTargets.append(description)
                        }
                    }
                // Test targets should be included only if they are directly in the product's target list.
                case .test:
                    if product.modules.contains(id: module.id) {
                        guard let description else {
                            throw InternalError("Could not find a description for module: \(module)")
                        }
                        staticTargets.append(description)
                    }
                // Library targets should always be included for the same build triple.
                case .library:
                    guard let description else {
                        throw InternalError("Could not find a description for module: \(module)")
                    }
                    if description.destination == productDescription.destination {
                        staticTargets.append(description)
                    }
                // Add system target to system targets array.
                case .systemModule:
                    systemModules.append(module)
                // Add binary to binary paths set.
                case .binary:
                    guard let binaryTarget = module.underlying as? BinaryModule else {
                        throw InternalError("invalid binary target '\(module.name)'")
                    }
                    switch binaryTarget.kind {
                    case .xcframework:
                        let libraries = try self.parseXCFramework(
                            for: binaryTarget,
                            triple: productDescription.buildParameters.triple
                        )
                        for library in libraries {
                            libraryBinaryPaths.insert(library.libraryPath)
                        }
                    case .artifactsArchive:
                        let tools = try self.parseArtifactsArchive(
                            for: binaryTarget, triple: productDescription.buildParameters.triple
                        )
                        tools.forEach { availableTools[$0.name] = $0.executablePath }
                    case .unknown:
                        throw InternalError("unknown binary target '\(module.name)' type")
                    }
                case .plugin:
                    continue
                }

            case .product(let product, let description):
                // Add the dynamic products to array of libraries to link.
                if product.type == .library(.dynamic) {
                    guard let description else {
                        throw InternalError("Dynamic library product should have description: \(product)")
                    }
                    linkLibraries.append(description)
                }
            }
        }

        // Add derived test targets, if necessary
        if product.type == .test, let derivedTestTargets = derivedTestTargetsMap[product.id] {
            staticTargets.append(contentsOf: derivedTestTargets.compactMap {
                self.description(for: $0, context: productDescription.destination)
            })
        }

        return (linkLibraries, staticTargets, systemModules, libraryBinaryPaths, availableTools)
    }

    /// Extracts the artifacts  from an artifactsArchive
    private func parseArtifactsArchive(for binaryTarget: BinaryModule, triple: Triple) throws -> [ExecutableInfo] {
        try self.externalExecutablesCache.memoize(key: binaryTarget) {
            let execInfos = try binaryTarget.parseArtifactArchives(for: triple, fileSystem: self.fileSystem)
            return execInfos.filter { !$0.supportedTriples.isEmpty }
        }
    }
}
