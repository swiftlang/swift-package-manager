//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Dispatch
import PackageGraph
import PackageModel
import SourceControl

import struct TSCUtility.Version

/// Enumeration of the different errors that can arise from the `ResolverPrecomputationProvider` provider.
enum ResolverPrecomputationError: Error {
    /// Represents the error when a package was requested but couldn't be found.
    case missingPackage(package: PackageReference)

    /// Represents the error when a different requirement of a package was requested.
    case differentRequirement(
        package: PackageReference,
        state: Workspace.ManagedDependency.State?,
        requirement: PackageRequirement
    )
}

/// PackageContainerProvider implementation used by Workspace to do a dependency pre-calculation using the cached
/// dependency information (Workspace.DependencyManifests) to check if dependency resolution is required before
/// performing a full resolution.
struct ResolverPrecomputationProvider: PackageContainerProvider {
    /// The package graph inputs.
    let root: PackageGraphRoot

    /// The managed manifests to make available to the resolver.
    let dependencyManifests: Workspace.DependencyManifests

    /// The tools version currently in use.
    let currentToolsVersion: ToolsVersion

    init(
        root: PackageGraphRoot,
        dependencyManifests: Workspace.DependencyManifests,
        currentToolsVersion: ToolsVersion = ToolsVersion.current
    ) {
        self.root = root
        self.dependencyManifests = dependencyManifests
        self.currentToolsVersion = currentToolsVersion
    }

    func getContainer(
        for package: PackageReference,
        updateStrategy: ContainerUpdateStrategy,
        observabilityScope: ObservabilityScope,
        on queue: DispatchQueue,
        completion: @escaping (Result<PackageContainer, Error>) -> Void
    ) {
        queue.async {
            // Start by searching manifests from the Workspace's resolved dependencies.
            if let manifest = self.dependencyManifests.dependencies.first(where: { _, managed, _, _ in managed.packageRef == package }) {
                let container = LocalPackageContainer(
                    package: package,
                    manifest: manifest.manifest,
                    dependency: manifest.dependency,
                    currentToolsVersion: self.currentToolsVersion
                )
                return completion(.success(container))
            }

            // Continue searching from the Workspace's root manifests.
            if let rootPackage = self.dependencyManifests.root.packages[package.identity] {
                let container = LocalPackageContainer(
                    package: package,
                    manifest: rootPackage.manifest,
                    dependency: nil,
                    currentToolsVersion: self.currentToolsVersion
                )
                return completion(.success(container))
            }

            // As we don't have anything else locally, error out.
            completion(.failure(ResolverPrecomputationError.missingPackage(package: package)))
        }
    }
}

private struct LocalPackageContainer: PackageContainer {
    let package: PackageReference
    let manifest: Manifest
    /// The managed dependency if the package is not a root package.
    let dependency: Workspace.ManagedDependency?
    let currentToolsVersion: ToolsVersion
    let shouldInvalidatePinnedVersions = false

    func versionsAscending() throws -> [Version] {
        switch dependency?.state {
        case .sourceControlCheckout(.version(let version, revision: _)):
            return [version]
        case .registryDownload(let version):
            return [version]
        default:
            return []
        }
    }

    func isToolsVersionCompatible(at version: Version) -> Bool {
        do {
            try manifest.toolsVersion.validateToolsVersion(currentToolsVersion, packageIdentity: .plain("unknown"))
            return true
        } catch {
            return false
        }
    }

    func toolsVersion(for version: Version) throws -> ToolsVersion {
        return currentToolsVersion
    }

    func toolsVersionsAppropriateVersionsDescending() async throws -> [Version] {
        try await self.versionsDescending()
    }

    func getDependencies(at version: Version, productFilter: ProductFilter, _ enabledTraits: Set<String>?) throws -> [PackageContainerConstraint] {
        // Because of the implementation of `reversedVersions`, we should only get the exact same version.
        switch dependency?.state {
        case .sourceControlCheckout(.version(version, revision: _)):
            return try manifest.dependencyConstraints(productFilter: productFilter, enabledTraits)
        case .registryDownload(version: version):
            return try manifest.dependencyConstraints(productFilter: productFilter, enabledTraits)
        default:
            throw InternalError("expected version based state, but state was \(String(describing: dependency?.state))")
        }
    }

    func getDependencies(at revisionString: String, productFilter: ProductFilter, _ enabledTraits: Set<String>?) throws -> [PackageContainerConstraint] {
        let revision = Revision(identifier: revisionString)
        switch dependency?.state {
        case .sourceControlCheckout(.branch(_, revision: revision)), .sourceControlCheckout(.revision(revision)):
            // Return the dependencies if the checkout state matches the revision.
            return try manifest.dependencyConstraints(productFilter: productFilter, enabledTraits)
        default:
            // Throw an error when the dependency is not revision based to fail resolution.
            throw ResolverPrecomputationError.differentRequirement(
                package: self.package,
                state: self.dependency?.state,
                requirement: .revision(revisionString)
            )
        }
    }

    func getUnversionedDependencies(productFilter: ProductFilter, _ enabledTraits: Set<String>?) throws -> [PackageContainerConstraint] {
        switch dependency?.state {
        case .none, .fileSystem, .edited:
            return try manifest.dependencyConstraints(productFilter: productFilter, enabledTraits)
        default:
            // Throw an error when the dependency is not unversioned to fail resolution.
            throw ResolverPrecomputationError.differentRequirement(
                package: package,
                state: dependency?.state,
                requirement: .unversioned
            )
        }
    }

    // Gets the package reference from the managed dependency or computes it for root packages.
    func loadPackageReference(at boundVersion: BoundVersion) throws -> PackageReference {
        if let packageRef = dependency?.packageRef {
            return packageRef
        } else {
            return .root(identity: self.package.identity, path: self.manifest.path)
        }
    }

    func getEnabledTraits(traitConfiguration: TraitConfiguration?, at version: Version? = nil) async throws -> Set<String> {
        guard manifest.packageKind.isRoot else {
            return []
        }

        let configurationEnabledTraits = traitConfiguration?.enabledTraits
        let enableAllTraits = traitConfiguration?.enableAllTraits ?? false

        if let version {
            switch dependency?.state {
            case .sourceControlCheckout(.version(version, revision: _)):
                return try manifest.enabledTraits(using: configurationEnabledTraits, enableAllTraits: enableAllTraits) ?? []
            case .registryDownload(version: version):
                return try manifest.enabledTraits(using: configurationEnabledTraits, enableAllTraits: enableAllTraits) ?? []
            default:
                throw InternalError("expected version based state, but state was \(String(describing: dependency?.state))")
            }
        } else {
            return try manifest.enabledTraits(using: configurationEnabledTraits, enableAllTraits: enableAllTraits) ?? []
        }
    }
}
