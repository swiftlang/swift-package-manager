//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageModel

import struct TSCUtility.Version

extension PackageDependency {
    /// Create the package reference object for the dependency.
    public var packageRef: PackageReference {
        let packageKind: PackageReference.Kind
        switch self {
        case .fileSystem(let settings):
            packageKind = .fileSystem(settings.path)
        case .sourceControl(let settings):
            switch settings.location {
            case .local(let path):
                packageKind = .localSourceControl(path)
            case .remote(let url):
                packageKind = .remoteSourceControl(url)
            }
        case .registry(let settings):
            packageKind = .registry(settings.identity)
        }
        return PackageReference(identity: self.identity, kind: packageKind)
    }

    public var majorVersionPackageRef: PackageReference {
        switch self {
        case .sourceControl:
            let id = self.majorVersionIdentity
            return PackageReference(identity: id, kind: self.packageRef.kind)
        case .registry, .fileSystem:
            return self.packageRef
        }
    }

}

extension Manifest {
    /// Constructs constraints of the dependencies in the raw package.
    public func dependencyConstraints(
        productFilter: ProductFilter,
        _ enabledTraits: EnabledTraits = ["default"]
    ) throws -> [PackageContainerConstraint] {
        return try self.dependenciesRequired(for: productFilter, enabledTraits).map({ dependency in
            let setter: EnabledTrait.Setter = .package(.init(identity: self.packageIdentity, name: self.displayName))
            let enabledTraitsSet: EnabledTraits
            if let dependencyTraits = dependency.traits {
                let explicitlyEnabledTraits = dependencyTraits.filter {
                    guard let condition = $0.condition else { return true }
                    return condition.isSatisfied(by: enabledTraits.names)
                }.map(\.name)
                enabledTraitsSet = EnabledTraits(explicitlyEnabledTraits, setBy: setter)
            } else {
                // Implicit default traits requested by parent.
                enabledTraitsSet = EnabledTraits(["default"], setBy: setter)
            }

            return PackageContainerConstraint(
                package: dependency.packageRef,
                requirement: try dependency.toConstraintRequirement(),
                products: dependency.productFilter,
                enabledTraits: enabledTraitsSet
            )
        })
    }
}

extension VersionSetSpecifier {
    /// The major-version bucket a dependency declaring this requirement belongs to, or `nil` if it isn't bucketed.
    ///
    /// This must mirror `PackageDependency.supportedMajorVersions` / `maxSupportedMajorVersion` so that the resolver
    /// and the graph layer (`majorVersionIdentity`) agree on which scoped identity a dependency refers to: the
    /// highest major the declared range reaches. A range confined to a single major (e.g. `upToNextMinor`) isn't
    /// bucketed there, so it isn't here either.
    var highestMajorBucket: Int? {
        switch self {
        case .exact(let version):
            return version.major
        case .range(let range):
            return range.lowerBound.major < range.upperBound.major ? range.upperBound.major - 1 : nil
        case .any, .empty, .ranges:
            return nil
        }
    }
}

extension PackageContainerConstraint {
    /// Prototype switch: resolve a version range's "1.x OR 2.x" ambiguity up front (see `scopedToHighestMajor`).
    /// When off, constraints keep targeting the plain package and the flagged-major machinery in PubGrub is what
    /// (incompletely) handles multiple majors.
    static let scopesToHighestMajor = true

    /// Decides the OR of a version range that spans several majors with a heuristic instead of in the solver: the
    /// constraint is rewritten to target the major-scoped package (`pkg@M`) for the HIGHEST major M in the range,
    /// with the range sliced to that major. This is the same rule the graph layer uses (`majorVersionIdentity`) and
    /// that module aliasing uses (`resolvedPackage(for:consumer:)`), so the resolver only ever sees single-major
    /// scoped nodes and every dependent has exactly one edge to the package.
    ///
    /// Limitations (known, deliberate): there is no fallback to a lower major if the highest can't be satisfied, and
    /// two dependents whose ranges overlap on several majors may end up with separate copies.
    internal func scopedToHighestMajor() -> PackageContainerConstraint {
        guard Self.scopesToHighestMajor,
              case .versionSet(let requirement) = self.requirement,
              let major = requirement.highestMajorBucket
        else {
            return self
        }

        switch self.package.kind {
        case .remoteSourceControl, .localSourceControl:
            break
        case .root, .fileSystem, .registry:
            return self
        }

        // Already scoped (e.g. the version lock a scoped product has on its own package).
        guard self.package.identity == self.package.identity.withoutMajor() else {
            return self
        }

        let slice = requirement.intersection(.range(Version(major, 0, 0)..<Version(major + 1, 0, 0)))
        return PackageContainerConstraint(
            package: self.package.scoped(toMajor: major),
            requirement: .versionSet(slice),
            products: self.products,
            enabledTraits: self.enabledTraits
        )
    }
}

extension PackageContainerConstraint {
    /// Constructs a structure of dependency nodes in a package.
    /// - returns: An array of ``DependencyResolutionNode``
    internal func nodes() -> [DependencyResolutionNode] {
        switch products {
        case .everything:
            return [.root(package: self.package, enabledTraits: self.enabledTraits)]
        case .specific:
            switch products {
            case .everything:
                assertionFailure("Attempted to enumerate a root package’s product filter; root packages have no filter.")
                return []
            case .specific(let set):
                if set.isEmpty { // Pointing at the package without a particular product.
                    return [.empty(package: self.package)]
                } else {
                    return set.sorted().map { .product($0, package: self.package, enabledTraits: self.enabledTraits) }
                }
            }
        }
    }
}
