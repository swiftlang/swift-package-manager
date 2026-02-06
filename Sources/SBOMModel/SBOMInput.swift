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

import ArgumentParser
import Basics
import PackageGraph
import PackageModel

package enum Filter: String, Codable, Equatable, CaseIterable {
    case all
    case product
    case package

    package var defaultValueDescription: String {
        switch self {
        case .all: "Include all entities in the SBOM"
        case .product: "Only include product information and product dependencies"
        case .package: "Only include package information and package dependencies"
        }
    }
}

extension Filter: ExpressibleByArgument {
    package init?(argument: String) {
        self.init(rawValue: argument)
    }
}

package struct SBOMInput {
    // Fields for SBOMExtractor
    package let modulesGraph: ModulesGraph
    package let dependencyGraph: [String: [String]]?
    package let store: ResolvedPackagesStore
    package let filter: Filter
    package let product: String?
    
    // Fields for SBOMEncoder
    package let specs: [Spec]
    package let dir: AbsolutePath
    
    package init(
        modulesGraph: ModulesGraph,
        dependencyGraph: [String: [String]]?,
        store: ResolvedPackagesStore,
        filter: Filter,
        product: String?,
        specs: [Spec],
        dir: AbsolutePath
    ) {
        self.modulesGraph = modulesGraph
        self.dependencyGraph = dependencyGraph
        self.store = store
        self.filter = filter
        self.product = product
        self.specs = specs
        self.dir = dir
    }
}
