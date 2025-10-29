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
    public func updateEnabledTraits(for manifest: Manifest) throws {
        print("calling update enabled traits on \(manifest.displayName)")
        let explicitlyEnabledTraits = manifest.packageKind.isRoot ? try manifest.enabledTraits(using: self.traitConfiguration) : self.enabledTraitsMap[manifest.packageIdentity]
        // TODO bp set parent here, if possible, for loaded manifests that aren't root.
        print("updating traits for manifest \(manifest.displayName)")
        let enabledTraits = try manifest.enabledTraits(using: explicitlyEnabledTraits)
        print("new enabled traits: \(enabledTraits)")
        print("with map: \(enabledTraitsMap)")
//        print("====== package \(manifest.packageIdentity.description) ========")
//        print("explicit traits: \(explicitlyEnabledTraits)")
//        print("new calculated traits: \(traits)")
        self.enabledTraitsMap[manifest.packageIdentity] = enabledTraits
//        print("traits in map: \(self.enabledTraitsMap[manifest.packageIdentity])")
//        print(self.enabledTraitsMap)

        // Check dependencies of the manifest; see if present in enabled traits map
        for dep in manifest.dependencies {
            updateEnabledTraits(forDependency: dep, manifest)
        }
    }

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

        // TODO bp: fetch loaded manifest for dependency, if it exists.
        // otherwise, we can omit this part:
//        if let enabledTraitsSet = explicitlyEnabledTraits.flatMap({ Set($0) }) {
////            let calculatedTraits = try dependencyManifest.enabledTraits(
////                using: enabledTraitsSet,
////                .init(parent)
////            )
//            // just add the parent enabled traits to
//            // the map; once this dependency is loaded, it will make a call to updateenabledtraits anyways
//            // TODO bp see if necessary to add parent here
//            self.enabledTraitsMap[dependency.identity/*, .package(.init(parent))*/] = enabledTraitsSet
//        }
    }

    public func precomputeTraits(
        _ topLevelManifests: [Manifest],
        _ manifestMap: [PackageIdentity: Manifest]
    ) throws -> [PackageIdentity: EnabledTraits] {
        var visited: Set<PackageIdentity> = []

        func dependencies(of parent: Manifest, _ productFilter: ProductFilter = .everything) throws {
            let parentTraits = self.enabledTraitsMap[parent.packageIdentity]
            let requiredDependencies = try parent.dependenciesRequired(for: productFilter, parentTraits)
            let guardedDependencies = parent.dependenciesTraitGuarded(withEnabledTraits: parentTraits)

            _ = try (requiredDependencies + guardedDependencies).compactMap({ dependency in
                return try manifestMap[dependency.identity].flatMap({ manifest in

                    let explicitlyEnabledTraits = dependency.traits?.filter { $0.isEnabled(by: parentTraits) }.map(\.name)
//                        .map({ EnabledTrait(name: $0.name, setBy: .package(.init(parent))) })
                    if let explicitlyEnabledTraits {
                        let explicitlyEnabledTraits = EnabledTraits(
                            explicitlyEnabledTraits,
                            setBy: .package(.init(parent))
                        )
                        let calculatedTraits = try manifest.enabledTraits(using: explicitlyEnabledTraits)
                        self.enabledTraitsMap[dependency.identity] = calculatedTraits
                    }
//                    if let enabledTraitsSet = explicitlyEnabledTraits.flatMap({ Set($0) }) {
//                        let calculatedTraits = try manifest.enabledTraits(
//                            using: enabledTraitsSet
////                            .init(parent)
//                        )
//                        self.enabledTraitsMap[dependency.identity] = calculatedTraits
//                    }

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

        print("enabled traits map: \(enabledTraitsMap)")
        return self.enabledTraitsMap.dictionaryLiteral
    }
}
