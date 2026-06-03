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

import class PackageModel.Manifest
import struct PackageModel.PackageIdentity
import struct PackageModel.PackageReference
import enum PackageModel.ProductFilter
import enum PackageModel.PackageDependency
import struct PackageModel.EnabledTrait
import struct PackageModel.EnabledTraits
import class Basics.ObservabilityScope
import Basics

extension Workspace {
//    public struct EnabledTraitsManager: Cancellable {
//
//        // todo to fill in stubs?
//    }
}
extension Workspace {
    /// Given a loaded `Manifest`, determine the traits that are enabled for it and
    /// calculate whichever traits are enabled transitively from this, if possible, and update the
    /// map of enabled traits on `Workspace` (`Workspace.enabledTraitsMap`).
    ///
    /// If the package defines a dependency with an explicit set of enabled traits, it will also
    /// add them to the enabled traits map.
    public func updateEnabledTraits(for manifest: Manifest, observabilityScope: ObservabilityScope) async throws {
        // If the `Manifest` is a root, then we should default to using
        // the trait configuration set in the `Workspace`. Otherwise,
        // check the enabled traits map to see if there are traits
        // that have already been recorded as enabled.
        let explicitlyEnabledTraits = manifest.packageKind.isRoot ?
        try manifest.enabledTraits(using: self.traitConfiguration) :
        self.enabledTraitsMap[manifest.packageIdentity]

        // Validate before expanding: this is the only point where the original EnabledTraits
        // (including the disabledBy setter) is still available. Once enabledTraits(using:) runs
        // for a no-trait package it discards that information and returns ["default"].
        // Root packages are validated separately through the trait configuration path.
        if !manifest.packageKind.isRoot {
            try manifest.validateEnabledTraits(explicitlyEnabledTraits)
        }

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

        self.enabledTraitsMap[manifest] = enabledTraits

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
            // todo bp dependency.packageRef may be relevant here.
            self.enabledTraitsMap[dependency.identity] = defaultTraits
        }
    }
}

extension Workspace {
    internal func updateTraits(
        manifests: DependencyManifests,
        addedOrUpdatedPackages: [PackageReference],
        observabilityScope: ObservabilityScope
    ) async throws {
        let packages = manifests.dependencies.filter({
            addedOrUpdatedPackages.map(\.identity).contains($0.manifest.packageIdentity) })

        for package in packages {
            let manifest = package.manifest
            // TODO bp: not clearing out old traits; need to reset this somehow..
            // since we have the updated packages, reconcile how we can identify
            // "stale" enabled trait entries in the map vs whichever "new" ones
            // were added in this new run. perhaps when an update is being initiated,
            // keep track of the enabled traits by parents...?
            let enabledTraits = self.enabledTraitsMap[manifest]
            // Find outdated trait enablement from previous state.

            // Validate traits on update.
            try manifest.validateEnabledTraits(enabledTraits)

            // Validate dependency manifest traits?
            let dependencies = manifest.dependencies.filter({ dep in
                guard let traits = dep.traits else {
                    return false
                }
                return !traits.isEmpty
            })
        }
    }
}
