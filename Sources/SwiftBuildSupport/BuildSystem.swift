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

import SPMBuildCore
import PackageGraph
import PackageModel

extension BuildConfiguration {
    public var swiftbuildName: String {
        switch self {
        case .debug: "Debug"
        case .release: "Release"
        }
    }
}

extension BuildSubset {
    func pifTargetName(for graph: ModulesGraph) -> String {
        switch self {
        case .product(let name, _):
            PackagePIFBuilder.targetName(forProductName: name)
        case .target(let name, _):
            // If the named target is the main module of a main-module product (e.g. a test or
            // executable target), it is represented in the PIF by that product's target.
            if let product = graph.allProducts.first(where: {
                $0.isMainModuleProduct
                    && $0.mainModule?.name == name
                    && !($0.mainModule?.isTestSupportModule ?? false)
            }) {
                PackagePIFBuilder.targetName(forProductName: product.name)
            } else {
                name
            }
        case .allExcludingTests:
            PIFBuilder.allExcludingTestsTargetName
        case .allIncludingTests:
            PIFBuilder.allIncludingTestsTargetName
        }
    }
}
