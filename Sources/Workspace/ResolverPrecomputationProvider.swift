/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageModel
import PackageGraph
import TSCBasic
import TSCUtility
import SourceControl

/// PackageContainerProvider implementation used by Workspace to do a dependency pre-calculation using the cached
/// dependency information (Workspace.DependencyManifests) to check if dependency resolution is required before
/// performing a full resolution.
struct ResolverPrecomputationProvider: PackageContainerProvider {
    /// The package graph inputs.
    let root: PackageGraphRoot

    /// The managed manifests to make available to the resolver.
    let dependencyManifests: Workspace.DependencyManifests

    /// The SwiftPM config.
    let config: SwiftPMConfig

    /// The tools version currently in use.
    let currentToolsVersion: ToolsVersion

    /// The diagnostics engine to report errors.
    let diagnostics: DiagnosticsEngine

    init(
        root: PackageGraphRoot,
        dependencyManifests: Workspace.DependencyManifests,
        config: SwiftPMConfig,
        currentToolsVersion: ToolsVersion = ToolsVersion.currentToolsVersion,
        diagnostics: DiagnosticsEngine
    ) {
        self.root = root
        self.dependencyManifests = dependencyManifests
        self.config = config
        self.currentToolsVersion = currentToolsVersion
        self.diagnostics = diagnostics
    }

    func getContainer(
        for identifier: PackageReference,
        skipUpdate: Bool,
        completion: @escaping (Result<PackageContainer, Error>) -> Void
    ) {
        // Start by searching manifests from the Workspace's resolved dependencies.
        if let manifest = dependencyManifests.dependencies.first(where: { $1.packageRef == identifier }) {
            let container = LocalPackageContainer(
                manifest: manifest.manifest,
                dependency: manifest.dependency,
                config: config,
                currentToolsVersion: currentToolsVersion
            )

            return completion(.success(container))
        }

        // Continue searching from the Workspace's root manifests.
        // FIXME: We might want to use a dictionary for faster lookups.
        if let index = dependencyManifests.root.packageRefs.firstIndex(of: identifier) {
            let container = LocalPackageContainer(
                manifest: dependencyManifests.root.manifests[index],
                dependency: nil,
                config: config,
                currentToolsVersion: currentToolsVersion
            )

            return completion(.success(container))
        }

        // As we don't have anything else locally, error out.
        completion(.failure(Diagnostics.fatalError))
    }
}

private struct LocalPackageContainer: PackageContainer {
    let manifest: Manifest
    /// The managed dependency if the package is not a root package.
    let dependency: ManagedDependency?
    let config: SwiftPMConfig
    let currentToolsVersion: ToolsVersion

    // Gets the package reference from the managed dependency or computes it for root packages.
    var identifier: PackageReference {
        if let identifier = dependency?.packageRef {
            return identifier
        } else {
            let identity = PackageReference.computeIdentity(packageURL: manifest.url)
            return PackageReference(
                identity: identity,
                path: manifest.path.pathString,
                kind: .root
            )
        }
    }

    var reversedVersions: [Version] {
        if let version = dependency?.state.checkout?.version {
            return [version]
        } else {
            return []
        }
    }

    func isToolsVersionCompatible(at version: Version) -> Bool {
        do {
            try manifest.toolsVersion.validateToolsVersion(currentToolsVersion, packagePath: "")
            return true
        } catch {
            return false
        }
    }

    func versions(filter isIncluded: (Version) -> Bool) -> AnySequence<Version> {
        return AnySequence(reversedVersions)
    }

    func getDependencies(at version: Version) throws -> [PackageContainerConstraint] {
        // Throw an error when the dependency is not at the correct version to fail resolution.
        guard dependency?.checkoutState?.version == version else {
            throw Diagnostics.fatalError
        }

        return manifest.dependencyConstraints(config: config)
    }

    func getDependencies(at revision: String) throws -> [PackageContainerConstraint] {
        // Throw an error when the dependency is not at the correct revision to fail resolution.
        guard dependency?.checkoutState?.revision.identifier == revision else {
            throw Diagnostics.fatalError
        }

        return manifest.dependencyConstraints(config: config)
    }

    func getUnversionedDependencies() throws -> [PackageContainerConstraint] {
        // Throw an error when the dependency is not unversioned to fail resolution.
        guard dependency?.state.isCheckout != true else {
            throw Diagnostics.fatalError
        }

        return manifest.dependencyConstraints(config: config)
    }

    func getUpdatedIdentifier(at boundVersion: BoundVersion) throws -> PackageReference {
        return identifier
    }
}

private extension ManagedDependency.State {
    var checkout: CheckoutState? {
        switch self {
        case .checkout(let state):
            return state
        default:
            return nil
        }
    }
}
