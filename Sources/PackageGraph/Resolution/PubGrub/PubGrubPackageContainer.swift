//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2019-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import _Concurrency
import OrderedCollections
import PackageModel

import struct TSCUtility.Version

/// A container for an individual package. This enhances PackageContainer to add PubGrub specific
/// logic which is mostly related to computing incompatibilities at a particular version.
final class PubGrubPackageContainer {
    /// The underlying package container.
    let underlying: PackageContainer

    /// `Package.resolved` in-memory representation.
    private let resolvedPackages: ResolvedPackagesStore.ResolvedPackages

    init(underlying: PackageContainer, resolvedPackages: ResolvedPackagesStore.ResolvedPackages) {
        self.underlying = underlying
        self.resolvedPackages = resolvedPackages
    }

    var package: PackageReference {
        self.underlying.package
    }

    /// Returns the pinned version for this package, if any.
    var pinnedVersion: Version? {
        switch self.resolvedPackages[self.underlying.package.identity]?.state {
        case .version(let version, _):
            version
        default:
            .none
        }
    }

    /// Returns the numbers of versions that are satisfied by the given version requirement.
    func versionCount(_ requirement: VersionSetSpecifier) async throws -> Int {
        if let pinnedVersion, requirement.contains(pinnedVersion) {
            return 1
        }
        return try await self.underlying.versionsDescending().filter(requirement.contains).count
    }

    /// Computes the bounds of the given range against the versions available in the package.
    ///
    /// `includesLowerBound` is `false` if range's lower bound is less than or equal to the lowest available version.
    /// Similarly, `includesUpperBound` is `false` if range's upper bound is greater than or equal to the highest
    /// available version.
    func computeBounds(for range: Range<Version>) async throws -> (includesLowerBound: Bool, includesUpperBound: Bool) {
        var includeLowerBound = true
        var includeUpperBound = true

        let versions = try await self.underlying.versionsDescending()

        if let last = versions.last, range.lowerBound < last {
            includeLowerBound = false
        }

        if let first = versions.first, range.upperBound > first {
            includeUpperBound = false
        }

        return (includeLowerBound, includeUpperBound)
    }

    /// Returns the best available version for a given term.
    func getBestAvailableVersion(for term: Term) async throws -> Version? {
        assert(term.isPositive, "Expected term to be positive")
        var versionSet = term.requirement

        // Restrict the selection to the pinned version if is allowed by the current requirements.
        if let pinnedVersion = self.pinnedVersion {
            if versionSet.contains(pinnedVersion) {
                if !self.underlying.shouldInvalidatePinnedVersions {
                    versionSet = .exact(pinnedVersion)
                } else {
                    // Make sure the pinned version is still available
                    let version = try await self.underlying.versionsDescending().first { pinnedVersion == $0 }
                    if version != nil {
                        return version
                    }
                }
            }
        }

        // Return the highest version that is allowed by the input requirement.
        return try await self.underlying.versionsDescending().first { versionSet.contains($0) }
    }

    /// Compute the bounds of incompatible tools version starting from the given version.
    private func computeIncompatibleToolsVersionBounds(fromVersion: Version) async throws -> VersionSetSpecifier {
        // TODO: do we really want to compute this for an assert?
        // assert(!self.underlying.isToolsVersionCompatible(at: fromVersion))
        let versions: [Version] = try await self.underlying.versionsAscending()

        // This is guaranteed to be present.
        let idx = versions.firstIndex(of: fromVersion)!

        var lowerBound = fromVersion
        var upperBound = fromVersion

        for version in versions.dropFirst(idx + 1) {
            let isToolsVersionCompatible = await self.underlying.isToolsVersionCompatible(at: version)
            if isToolsVersionCompatible {
                break
            }
            upperBound = version
        }

        for version in versions.dropLast(versions.count - idx).reversed() {
            let isToolsVersionCompatible = await self.underlying.isToolsVersionCompatible(at: version)
            if isToolsVersionCompatible {
                break
            }
            lowerBound = version
        }

        // If lower and upper bounds didn't change then this is the sole incompatible version.
        if lowerBound == upperBound {
            return .exact(lowerBound)
        }

        // If lower bound is the first version then we can use 0 as the sentinel. This
        // will end up producing a better diagnostic since we can omit the lower bound.
        if lowerBound == versions.first {
            lowerBound = "0.0.0"
        }

        if upperBound == versions.last {
            // If upper bound is the last version then we can use the next major version as the sentinel.
            // This will end up producing a better diagnostic since we can omit the upper bound.
            upperBound = Version(upperBound.major + 1, 0, 0)
        } else {
            // Use the next patch since the upper bound needs to be inclusive here.
            upperBound = upperBound.nextPatch()
        }
        return .range(lowerBound ..< upperBound.nextPatch())
    }

    /// Returns the incompatibilities of a package at the given version.
    func incompatibilites(
        at version: Version,
        node: DependencyResolutionNode,
        overriddenPackages: [PackageReference: (version: BoundVersion, products: ProductFilter)],
        root: DependencyResolutionNode,
        traitConfiguration: TraitConfiguration? = nil
    ) async throws -> [Incompatibility] {
        // FIXME: It would be nice to compute bounds for this as well.
        if await !self.underlying.isToolsVersionCompatible(at: version) {
            let requirement = try await self.computeIncompatibleToolsVersionBounds(fromVersion: version)
            let toolsVersion = try await self.underlying.toolsVersion(for: version)
            return try [Incompatibility(
                Term(node, requirement),
                root: root,
                cause: .incompatibleToolsVersion(toolsVersion)
            )]
        }

        var unprocessedDependencies = try await self.underlying.getDependencies(
            at: version,
            productFilter: node.productFilter,
            node.traits
        )
        if let sharedVersion = node.versionLock(version: version) {
            unprocessedDependencies.append(sharedVersion)
        }
        var constraints: [PackageContainerConstraint] = []
        for dep in unprocessedDependencies {
            // Version-based packages are not allowed to contain unversioned dependencies.
            guard case .versionSet = dep.requirement else {
                let cause: Incompatibility.Cause = .versionBasedDependencyContainsUnversionedDependency(
                    versionedDependency: self.package,
                    unversionedDependency: dep.package
                )
                return try [Incompatibility(Term(node, .exact(version)), root: root, cause: cause)]
            }

            // Skip if this package is overridden.
            if overriddenPackages.keys.contains(dep.package) {
                continue
            }

            for node in dep.nodes() {
                constraints.append(
                    PackageContainerConstraint(
                        package: node.package,
                        requirement: dep.requirement,
                        products: node.productFilter,
                        enabledTraits: dep.enabledTraits
                    )
                )
            }
        }

        return try constraints.flatMap { constraint -> [Incompatibility] in
            // We only have version-based requirements at this point.
            guard case .versionSet(let constraintRequirement) = constraint.requirement else {
                throw InternalError("Unexpected unversioned requirement: \(constraint)")
            }
            return try constraint.nodes().compactMap { constraintNode in
                // cycle
                guard node != constraintNode else {
                    return nil
                }

                var terms: OrderedCollections.OrderedSet<Term> = []
                // the package version requirement
                terms.append(Term(node, .exact(version)))
                // the dependency's version requirement
                terms.append(Term(not: constraintNode, constraintRequirement))

                return try Incompatibility(terms, root: root, cause: .dependency(node: node))
            }
        }
    }
}
