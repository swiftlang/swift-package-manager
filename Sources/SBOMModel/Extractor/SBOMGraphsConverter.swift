//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageGraph
import PackageModel
import SwiftBuildSupport

// TODO: echeng3805, add this to PackagePIFBuilder+Helpers.swift?
// These functions aren't used anywhere except for SBOMs.

extension PackagePIFBuilder {

    /// Helper function to consistently generate a target name string for a module in a product.
    package static func targetName(forModuleName name: String, suffix: TargetSuffix? = nil) -> String {
        let suffix = suffix?.rawValue ?? ""
        return "\(name)\(suffix)"
    }

    /// Removes known TargetSuffix patterns from a name string.
    private static func removeSuffix(from name: String) -> String {
        for suffix in TargetSuffix.allCases {
            let suffixPattern: String
            switch suffix {
            case .testable, .dynamic:
                suffixPattern = "-\(suffix.rawValue)"
                if name.hasSuffix(suffixPattern) {
                    return String(name.dropLast(suffixPattern.count))
                }
            }
        }
        return name
    }

    /// Helper function to get a product name for a target name
    package static func productName(forTargetName name: String) -> String? {
        guard name.hasSuffix("-product") else {
            return nil
        }
        let nameWithoutProduct = String(name.dropLast("-product".count))
        return removeSuffix(from: nameWithoutProduct)
    }

    /// Helper function to get a module name for a target name
    package static func moduleName(forTargetName name: String) -> String? {
        guard !name.hasSuffix("-product") else {
            return nil
        }
        // Resource bundle target names follow the pattern packageName_moduleName
        // e.g., swift-nio_NIOPosix, swift-crypto__CryptoExtras
        // So should be ignored by moduleName()
        // But moduleName can start with _, like _CryptoExtras and __AsyncFileSystem
        if name.contains("_") && !name.starts(with: "_") {
            return nil
        }
        return removeSuffix(from: name)
    }
}

/// Utilities for converting between ModulesGraph and dependency graph naming conventions.
internal struct SBOMGraphsConverter {

    // The PIF creates target names for products, modules, and resource bundles
    // Product target names get a -product suffix
    // Module target names are passed through
    // Resource bundle target names are packageName_moduleName
    // SBOMs ignore resource bundles

    internal static func getTargetName(fromProduct name: String) -> String {
        return PackagePIFBuilder.targetName(forProductName: name)
    }

    internal static func getTargetName(fromModule name: String) -> String {
        return PackagePIFBuilder.targetName(forModuleName: name)
    }

    internal static func getProductName(fromTarget name: String) -> String? {
        return PackagePIFBuilder.productName(forTargetName: name)
    }

    internal static func getModuleName(fromTarget name: String) -> String?
    {
        return PackagePIFBuilder.moduleName(forTargetName: name)
    }

    internal static func toProduct(fromTarget name: String, modulesGraph: ModulesGraph) -> ResolvedProduct? {
        getProductName(fromTarget: name).flatMap { modulesGraph.product(for: $0) }
    }

    internal static func toModule(fromTarget name: String, modulesGraph: ModulesGraph) -> ResolvedModule? {
        getModuleName(fromTarget: name).flatMap { modulesGraph.module(for: $0) }
    }
}