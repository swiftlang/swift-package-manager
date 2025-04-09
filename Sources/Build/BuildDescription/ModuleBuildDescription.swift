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

import Basics
import struct PackageGraph.ResolvedModule
import struct PackageGraph.ResolvedPackage
import struct PackageGraph.ResolvedProduct
import struct PackageModel.Resource
import struct PackageModel.ToolsVersion
import struct SPMBuildCore.BuildToolPluginInvocationResult
import struct SPMBuildCore.BuildParameters
import protocol SPMBuildCore.ModuleBuildDescription

public enum BuildDescriptionError: Swift.Error {
    case requestedFileNotPartOfTarget(targetName: String, requestedFilePath: AbsolutePath)
}

@available(*, deprecated, renamed: "ModuleBuildDescription")
public typealias TargetBuildDescription = ModuleBuildDescription

/// A module build description which can either be for a Swift or Clang module.
public enum ModuleBuildDescription: SPMBuildCore.ModuleBuildDescription {
    /// Swift target description.
    case swift(SwiftModuleBuildDescription)

    /// Clang target description.
    case clang(ClangModuleBuildDescription)

    /// The objects in this target.
    var objects: [AbsolutePath] {
        get throws {
            switch self {
            case .swift(let module):
                return try module.objects
            case .clang(let module):
                return try module.objects
            }
        }
    }

    /// The resources in this target.
    var resources: [Resource] {
        switch self {
        case .swift(let buildDescription):
            return buildDescription.resources
        case .clang(let buildDescription):
            return buildDescription.resources
        }
    }

    /// Path to the bundle generated for this module (if any).
    var bundlePath: AbsolutePath? {
        switch self {
        case .swift(let buildDescription):
            return buildDescription.bundlePath
        case .clang(let buildDescription):
            return buildDescription.bundlePath
        }
    }

    public var module: ResolvedModule {
        switch self {
        case .swift(let buildDescription):
            return buildDescription.target
        case .clang(let buildDescription):
            return buildDescription.target
        }
    }

    public var package: ResolvedPackage {
        switch self {
        case .swift(let description):
            description.package
        case .clang(let description):
            description.package
        }
    }

    /// Paths to the binary libraries the target depends on.
    var libraryBinaryPaths: Set<AbsolutePath> {
        switch self {
        case .swift(let target):
            return target.libraryBinaryPaths
        case .clang(let target):
            return target.libraryBinaryPaths
        }
    }

    var resourceBundleInfoPlistPath: AbsolutePath? {
        switch self {
        case .swift(let buildDescription):
            return buildDescription.resourceBundleInfoPlistPath
        case .clang(let buildDescription):
            return buildDescription.resourceBundleInfoPlistPath
        }
    }

    var buildToolPluginInvocationResults: [BuildToolPluginInvocationResult] {
        switch self {
        case .swift(let buildDescription):
            return buildDescription.buildToolPluginInvocationResults
        case .clang(let buildDescription):
            return buildDescription.buildToolPluginInvocationResults
        }
    }

    public var buildParameters: BuildParameters {
        switch self {
        case .swift(let buildDescription):
            return buildDescription.buildParameters
        case .clang(let buildDescription):
            return buildDescription.buildParameters
        }
    }

    var destination: BuildParameters.Destination {
        switch self {
        case .swift(let buildDescription):
            buildDescription.destination
        case .clang(let buildDescription):
            buildDescription.destination
        }
    }

    var toolsVersion: ToolsVersion {
        switch self {
        case .swift(let buildDescription):
            return buildDescription.toolsVersion
        case .clang(let buildDescription):
            return buildDescription.toolsVersion
        }
    }

    /// Determines the arguments needed to run `swift-symbolgraph-extract` for
    /// this module.
    public func symbolGraphExtractArguments() throws -> [String] {
        switch self {
        case .swift(let buildDescription): try buildDescription.symbolGraphExtractArguments()
        case .clang(let buildDescription): try buildDescription.symbolGraphExtractArguments()
        }
    }
}

extension ModuleBuildDescription: Identifiable {
    public struct ID: Hashable {
        let moduleID: ResolvedModule.ID
        let destination: BuildParameters.Destination
    }

    public var id: ID {
        ID(moduleID: self.module.id, destination: self.destination)
    }
}

extension ModuleBuildDescription {
    package enum Dependency {
        /// Not all of the modules and products have build descriptions
        case product(ResolvedProduct, ProductBuildDescription?)
        case module(ResolvedModule, ModuleBuildDescription?)
    }

    package func dependencies(using plan: BuildPlan) -> [Dependency] {
        self.module
            .dependencies(satisfying: self.buildParameters.buildEnvironment)
            .map {
                switch $0 {
                case .product(let product, _):
                    let productDescription = plan.description(for: product, context: self.destination)
                    return .product(product, productDescription)
                case .module(let module, _):
                    let moduleDescription = plan.description(for: module, context: self.destination)
                    return .module(module, moduleDescription)
                }
            }
    }

    package func recursiveDependencies(using plan: BuildPlan) -> [Dependency] {
        var dependencies: [Dependency] = []
        plan.traverseDependencies(of: self) { product, _, description in
            dependencies.append(.product(product, description))
            return .continue
        } onModule: { module, _, description in
            dependencies.append(.module(module, description))
            return .continue
        }
        return dependencies
    }

    package func recursiveLinkDependencies(using plan: BuildPlan) -> [Dependency] {
        var dependencies: [Dependency] = []
        plan.traverseDependencies(of: self) { product, _, description in
            guard product.type != .macro && product.type != .plugin else {
                return .abort
            }

            dependencies.append(.product(product, description))
            return .continue
        } onModule: { module, _, description in
            guard module.type != .macro && module.type != .plugin else {
                return .abort
            }

            dependencies.append(.module(module, description))
            return .continue
        }
        return dependencies
    }
}
