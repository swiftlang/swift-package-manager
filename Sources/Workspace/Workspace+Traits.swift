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
import enum PackageModel.PackageDependency
import struct PackageModel.EnabledTrait
import struct PackageModel.EnabledTraits

extension Workspace {
    /// Given a loaded `Manifest`, determine the traits that are enabled for it and
    /// calculate whichever traits are enabled transitively from this, if possible, and update the
    /// map of enabled traits on `Workspace` (`Workspace.enabledTraitsMap`).
    ///
    /// If the package defines a dependency with an explicit set of enabled traits, it will also
    /// add them to the enabled traits map.
    public func updateEnabledTraits(for manifest: Manifest) throws {
        // If the `Manifest` is a root, then we should default to using
        // the trait configuration set in the `Workspace`. Otherwise,
        // check the enabled traits map to see if there are traits
        // that have already been recorded as enabled.
        let explicitlyEnabledTraits = manifest.packageKind.isRoot ?
        try manifest.enabledTraits(using: self.traitConfiguration) :
        self.enabledTraitsMap[manifest.packageIdentity]

        let enabledTraits = try manifest.enabledTraits(using: explicitlyEnabledTraits)
        self.enabledTraitsMap[manifest.packageIdentity] = enabledTraits

        // Check enabled traits for the dependencies
        for dep in manifest.dependencies {
            updateEnabledTraits(forDependency: dep, manifest)
        }
    }

    /// Update the enabled traits for a `PackageDependency` of a given parent `Manifest`.
    ///
    /// This is only called if a loaded `Manifest` has package dependencies in which it sets
    /// an explicit list of enabled traits for that dependency.
    private func updateEnabledTraits(forDependency dependency: PackageDependency, _ parent: Manifest) {
        let parentEnabledTraits = self.enabledTraitsMap[parent.packageIdentity]
        let explicitlyEnabledTraits = dependency.traits?.filter { $0.isEnabled(by: parentEnabledTraits)}.map(\.name)

        if let explicitlyEnabledTraits {
            let explicitlyEnabledTraits = EnabledTraits(
                explicitlyEnabledTraits,
                setBy: .package(.init(parent))
            )
            self.enabledTraitsMap[dependency.identity] = explicitlyEnabledTraits
        }
    }

//    public func precomputeTraits(
//        _ topLevelManifests: [Manifest],
//        _ manifestMap: [PackageIdentity: Manifest]
//    ) throws -> [PackageIdentity: EnabledTraits] {
//        var visited: Set<PackageIdentity> = []
//
//        func dependencies(of parent: Manifest, _ productFilter: ProductFilter = .everything) throws {
//            let parentTraits = self.enabledTraitsMap[parent.packageIdentity]
//            let requiredDependencies = try parent.dependenciesRequired(for: productFilter, parentTraits)
//            let guardedDependencies = parent.dependenciesTraitGuarded(withEnabledTraits: parentTraits)
//
//            _ = try (requiredDependencies + guardedDependencies).compactMap({ dependency in
//                return try manifestMap[dependency.identity].flatMap({ manifest in
//
//                    let explicitlyEnabledTraits = dependency.traits?.filter { $0.isEnabled(by: parentTraits) }.map(\.name)
////                        .map({ EnabledTrait(name: $0.name, setBy: .package(.init(parent))) })
//                    if let explicitlyEnabledTraits {
//                        let explicitlyEnabledTraits = EnabledTraits(
//                            explicitlyEnabledTraits,
//                            setBy: .package(.init(parent))
//                        )
//                        let calculatedTraits = try manifest.enabledTraits(using: explicitlyEnabledTraits)
//                        self.enabledTraitsMap[dependency.identity] = calculatedTraits
//                    }
////                    if let enabledTraitsSet = explicitlyEnabledTraits.flatMap({ Set($0) }) {
////                        let calculatedTraits = try manifest.enabledTraits(
////                            using: enabledTraitsSet
//////                            .init(parent)
////                        )
////                        self.enabledTraitsMap[dependency.identity] = calculatedTraits
////                    }
//
//                    let result = visited.insert(dependency.identity)
//                    if result.inserted {
//                        try dependencies(of: manifest, dependency.productFilter)
//                    }
//
//                    return manifest
//                })
//            })
//        }
//
//        for manifest in topLevelManifests {
//            // Track already-visited manifests to avoid cycles
//            let result = visited.insert(manifest.packageIdentity)
//            if result.inserted {
//                try dependencies(of: manifest)
//            }
//        }
//
//        return self.enabledTraitsMap.dictionaryLiteral
//    }
}
