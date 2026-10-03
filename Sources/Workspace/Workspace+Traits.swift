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
import enum PackageModel.TraitError
import class Basics.ObservabilityScope
import Basics

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
            try self.validateEnabledTraits(explicitlyEnabledTraits, for: manifest)
        }

        var enabledTraits = try manifest.enabledTraits(using: explicitlyEnabledTraits)

        // Check if any parents requested default traits for this package, and expand and
        // union them.
        // Traits are unified across the graph, so once a parent explicitly opts into specific
        // traits, that explicit selection must be unioned with its defaults.
        if let defaultSetters = self.enabledTraitsMap[defaultSettersFor: manifest.packageIdentity],
           !defaultSetters.isEmpty {
            // Calculate what the default traits are for this manifest
            let defaultTraits = try manifest.enabledTraits(using: .defaults)
            enabledTraits.formUnion(defaultTraits)
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
            self.enabledTraitsMap[dependency.identity] = defaultTraits
        }
    }

    /// Validates the traits enabled for a non-root `Manifest`, throwing only for a request that must fail
    /// package resolution.
    ///
    /// A parent manifest asking a traitless package to *disable* its defaults is an error. This rule is in place
    /// to protect the ability of a package to move existing API behind a default trait without breaking its consumers.
    /// The parent's author owns the manifest that made the request, so they can act on the error.
    ///
    /// Everything else falls back to the package's defaults, which is what `enabledTraits(using:)` returns for
    /// a traitless package anyway, and `reportTraitFallbacks` warns about it. That covers naming traits the
    /// package no longer declares, and disabling defaults from a stored trait configuration: in both cases the
    /// dependency is the thing that changed, and there is nothing the consumer can do about it short of
    /// editing a manifest they may not own.
    func validateEnabledTraits(_ enabledTraits: EnabledTraits, for manifest: Manifest) throws {
        guard let unsupportedTraits = manifest.unsupportedTraitsError(enabledTraits) else {
            try manifest.validateEnabledTraits(enabledTraits)
            return
        }

        if enabledTraits.isEmpty, !self.defaultsDisabledOnlyByTraitConfiguration(manifest) {
            throw unsupportedTraits
        }
    }

    /// Whether every setter that disabled this package's default traits was a stored trait configuration.
    ///
    /// `EnabledTraits.disabledBy` reports one setter picked arbitrarily out of the recorded disablers, so it
    /// can't answer this when a package was disabled by more than one thing. Ask the map for all of them
    /// instead: a parent manifest among them is a request its author can fix, and stays an error.
    private func defaultsDisabledOnlyByTraitConfiguration(_ manifest: Manifest) -> Bool {
        guard let disablers = self.enabledTraitsMap[disablersFor: manifest.packageIdentity],
              !disablers.isEmpty
        else {
            return false
        }

        return disablers.allSatisfy { $0 == .traitConfiguration }
    }

    /// Warns about packages that were asked for traits they don't declare and will fall back to their defaults.
    ///
    /// This runs over the whole manifest set rather than from `updateEnabledTraits`, because a single
    /// manifest's enabled traits aren't final until every parent has registered its edges. Warning as each
    /// manifest loads would report a request that is still being assembled, and report it once per loading
    /// pass rather than once per package.
    func reportTraitFallbacks(
        for manifests: some Sequence<Manifest>,
        observabilityScope: ObservabilityScope
    ) {
        for manifest in manifests where !manifest.packageKind.isRoot {
            // Report only the named traits, `default` is always present.
            var requestedTraits = self.enabledTraitsMap[manifest.packageIdentity]
            _ = requestedTraits.remove("default")

            // If all that is left is an empty map, the request is to disable defaults. This is only tolerated
            // (and so we only warn about it) when every disabler was a stored trait configuration.
            // An empty map with no disablers at all means nothing was requested of this package, so there is nothing to report.
            guard !requestedTraits.isEmpty || self.defaultsDisabledOnlyByTraitConfiguration(manifest),
                  let unsupportedTraits = manifest.unsupportedTraitsError(requestedTraits)
            else {
                continue
            }

            observabilityScope.emit(
                warning: """
                \(self.traitFallbackReason(unsupportedTraits, requestedTraits, manifest)) The package will \
                be built with its default traits.
                """
            )
        }
    }

    /// Describes why a package can't honour what was asked of it, for use in a warning.
    ///
    /// `TraitError`'s own prose ends by explaining why the request is normally rejected, which contradicts a
    /// warning saying we went ahead regardless. That only applies to disabling defaults, so reuse the error's
    /// wording for a request naming traits and describe the disable case here.
    private func traitFallbackReason(
        _ unsupportedTraits: TraitError,
        _ requestedTraits: EnabledTraits,
        _ manifest: Manifest
    ) -> String {
        guard requestedTraits.isEmpty else {
            return "\(unsupportedTraits)"
        }

        return """
        The trait configuration disables the default traits of package \
        \(Manifest.PackageIdentifier(manifest)), which declares no traits.
        """
    }
}

extension Workspace {
    internal func validateUpdatedTraits(
        manifests: DependencyManifests,
        addedOrUpdatedPackages: [PackageReference],
        observabilityScope: ObservabilityScope
    ) async throws {
        let packages = manifests.dependencies.filter({
            addedOrUpdatedPackages.map(\.identity).contains($0.manifest.packageIdentity) })

        for package in packages {
            let manifest = package.manifest
            let enabledTraits = self.enabledTraitsMap[manifest]

            // Validate traits on update.
            try self.validateEnabledTraits(enabledTraits, for: manifest)
        }
    }
}
