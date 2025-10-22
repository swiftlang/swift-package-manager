//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import class PackageModel.Manifest
import struct PackageModel.PackageIdentity
import enum PackageModel.ProductFilter

extension Workspace {
    public func precomputeTraits(
        _ topLevelManifests: [Manifest],
        _ manifestMap: [PackageIdentity: Manifest]
    ) throws -> [PackageIdentity: Set<String>] {
        var visited: Set<PackageIdentity> = []

        func dependencies(of parent: Manifest, _ productFilter: ProductFilter = .everything) throws {
            let parentTraits = self.enabledTraitsMap[parent.packageIdentity]
            let requiredDependencies = try parent.dependenciesRequired(for: productFilter, parentTraits)
            let guardedDependencies = parent.dependenciesTraitGuarded(withEnabledTraits: parentTraits)

            _ = try (requiredDependencies + guardedDependencies).compactMap({ dependency in
                return try manifestMap[dependency.identity].flatMap({ manifest in

                    let explicitlyEnabledTraits = dependency.traits?.filter {
                        guard let condition = $0.condition else { return true }
                        return condition.isSatisfied(by: parentTraits)
                    }.map(\.name)

                    if let enabledTraitsSet = explicitlyEnabledTraits.flatMap({ Set($0) }) {
                        let calculatedTraits = try manifest.enabledTraits(
                            using: enabledTraitsSet,
                            .init(parent)
                        )
                        self.enabledTraitsMap[dependency.identity] = calculatedTraits
                    }

                    let result = visited.insert(dependency.identity)
                    if result.inserted {
                        try dependencies(of: manifest, dependency.productFilter)
                    }

                    return manifest
                })
            })
        }

        for manifest in topLevelManifests {
            // Track already-visited manifests to avoid cycles
            let result = visited.insert(manifest.packageIdentity)
            if result.inserted {
                try dependencies(of: manifest)
            }
        }

        return self.enabledTraitsMap.dictionaryLiteral
    }

}
