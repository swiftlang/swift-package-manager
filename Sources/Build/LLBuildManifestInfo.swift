//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageGraph
import PackageModel
import SPMBuildCore

public enum LLBuildManifestInfo {
    public struct Info: Codable, PackageGraphInfo {
        let _products: [Product]
        let _targets: [Target]

        init(products: [Product], targets: [Target]) {
            self._products = products
            self._targets = targets
        }

        public var products: [ProductInfo] {
            return _products
        }

        public var targets: [TargetInfo] {
            return _targets
        }

        static func from(_ packageGraph: PackageGraph) -> Info {
            return Info(
                products: packageGraph.allProducts.compactMap {
                    if let target = $0.targets.first, let package = packageGraph.package(for: target) {
                        return try? .init($0, package)
                    } else {
                        return nil
                    }
                },
                targets: packageGraph.allTargets.compactMap {
                    if let package = packageGraph.package(for: $0) {
                        return .init($0, package)
                    } else {
                        return nil
                    }
                }
            )
        }
    }

    public struct Product: Codable, ProductInfo {
        private let _package: Package
        public let name: String
        public let type: ProductType
        private let _targets: [Target]
        let LLBuildTargetNameByConfig: [String: String]

        private init(package: Package, name: String, type: ProductType, targets: [Target], LLBuildTargetNameByConfig: [String : String]) {
            self._package = package
            self.name = name
            self.type = type
            self._targets = targets
            self.LLBuildTargetNameByConfig = LLBuildTargetNameByConfig
        }

        public var package: PackageInfo {
            return _package
        }

        public var targets: [TargetInfo] {
            return _targets
        }
    }

    public struct Target: Codable, TargetInfo {
        private let _package: Package
        public let name: String
        public let isSwiftTarget: Bool
        public let c99name: String
        public let sourcesDirectory: AbsolutePath?
        public let derivedSupportedPlatforms: [SupportedPlatform]
        public let type: PackageModel.Target.Kind
        let LLBuildTargetNameByConfig: [String: String]

        private init(package: Package, name: String, isSwiftTarget: Bool, c99name: String, sourcesDirectory: AbsolutePath?, derivedSupportedPlatforms: [SupportedPlatform], type: PackageModel.Target.Kind, LLBuildTargetNameByConfig: [String : String]) {
            self._package = package
            self.name = name
            self.isSwiftTarget = isSwiftTarget
            self.c99name = c99name
            self.sourcesDirectory = sourcesDirectory
            self.derivedSupportedPlatforms = derivedSupportedPlatforms
            self.type = type
            self.LLBuildTargetNameByConfig = LLBuildTargetNameByConfig
        }

        public var package: PackageInfo {
            return _package
        }
    }

    public struct Package: Codable, PackageInfo {
        public let identity: String
        public let isRoot: Bool
    }
}

extension LLBuildManifestInfo.Product {
    init(_ product: ResolvedProduct, _ package: ResolvedPackage) throws {
        var LLBuildTargetNameByConfig = [String: String]()

        // These types do not have LLBuild target names.
        if product.type != .plugin && product.type != .library(.automatic) {
            try BuildConfiguration.allCases.forEach {
                LLBuildTargetNameByConfig[$0.rawValue] = try product.getLLBuildTargetName(config: $0.rawValue)
            }
        }

        self.init(
            package: .init(package),
            name: product.name,
            type: product.type,
            targets: product.targets.map { .init($0, package) },
            LLBuildTargetNameByConfig: LLBuildTargetNameByConfig
        )
    }
}

extension LLBuildManifestInfo.Target {
    init(_ target: ResolvedTarget, _ package: ResolvedPackage) {
        var LLBuildTargetNameByConfig = [String: String]()
        BuildConfiguration.allCases.forEach {
            LLBuildTargetNameByConfig[$0.rawValue] = target.getLLBuildTargetName(config: $0.rawValue)
        }
        
        self.init(
            package: .init(package),
            name: target.name,
            isSwiftTarget: target.underlyingTarget is SwiftTarget,
            c99name: target.c99name,
            sourcesDirectory: target.sources.paths.first?.parentDirectory,
            derivedSupportedPlatforms: target.platforms.derived,
            type: target.type,
            LLBuildTargetNameByConfig: LLBuildTargetNameByConfig
        )
    }
}

extension LLBuildManifestInfo.Package {
    init(_ package: ResolvedPackage) {
        self.init(identity: package.identity.description, isRoot: package.manifest.packageKind.isRoot)
    }
}
