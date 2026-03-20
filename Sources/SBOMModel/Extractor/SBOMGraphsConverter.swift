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