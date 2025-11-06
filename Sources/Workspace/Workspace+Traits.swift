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

        var enabledTraits = try manifest.enabledTraits(using: explicitlyEnabledTraits)

        // Check if any parents requested default traits for this package
        // If so, expand the default traits and union them with existing traits
        if let defaultSetters = self.enabledTraitsMap[defaultSettersFor: manifest.packageIdentity],
           !defaultSetters.isEmpty {
            // Calculate what the default traits are for this manifest
            let defaultTraits = try manifest.enabledTraits(using: .defaults)

            // Create enabled traits for each setter that requested defaults
            for setter in defaultSetters {
                let traitsFromSetter = EnabledTraits(
                    defaultTraits.map(\.name),
                    setBy: setter
                )
                enabledTraits.formUnion(traitsFromSetter)
            }
        }

        self.enabledTraitsMap[manifest.packageIdentity] = enabledTraits

        // Check enabled traits for the dependencies
        for dep in manifest.dependencies {
            updateEnabledTraits(forDependency: dep, manifest)
        }
    }

    /// Update the enabled traits for a `PackageDependency` of a given parent `Manifest`.
    ///
    /// This is called when a manifest is loaded to register the parent's trait requirements for its dependencies.
    /// When a parent doesn't specify traits, this explicitly registers that the parent wants the dependency
    /// to use its default traits, with the parent as the setter.
    private func updateEnabledTraits(forDependency dependency: PackageDependency, _ parent: Manifest) {
        let parentEnabledTraits = self.enabledTraitsMap[parent.packageIdentity]

        if let dependencyTraits = dependency.traits {
            // Parent explicitly specified traits (could be [] to disable, or a list of specific traits)
            let explicitlyEnabledTraits = dependencyTraits
                .filter { $0.isEnabled(by: parentEnabledTraits) }
                .map(\.name)

            let enabledTraits = EnabledTraits(
                explicitlyEnabledTraits,
                setBy: .package(.init(parent))
            )
            self.enabledTraitsMap[dependency.identity] = enabledTraits
        } else {
            // Parent didn't specify traits - it wants the dependency to use its defaults.
            // Explicitly register "default" with this parent as the setter.
            // This ensures the union system properly tracks that this parent wants defaults enabled,
            // even if other parents have disabled traits.
            let defaultTraits = EnabledTraits(
                ["default"],
                setBy: .package(.init(parent))
            )
            self.enabledTraitsMap[dependency.identity] = defaultTraits
        }
    }
}
