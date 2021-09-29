/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import Dispatch
import PackageGraph
import PackageLoading
import PackageModel
import PackageRegistry
import SourceControl
import TSCBasic
import TSCUtility

public class RegistryPackageContainer: PackageContainer {
    public let package: PackageReference

    private let registryManager: RegistryManager
    private let identityResolver: IdentityResolver
    private let manifestLoader: ManifestLoaderProtocol
    private let toolsVersionLoader: ToolsVersionLoaderProtocol
    private let currentToolsVersion: ToolsVersion

    private var knownVersionsCache = ThreadSafeBox<[Version]>()
    private var toolsVersionsCache = ThreadSafeKeyValueStore<Version, ToolsVersion>()
    private var validToolsVersionsCache = ThreadSafeKeyValueStore<Version, Bool>()
    private var manifestsCache = ThreadSafeKeyValueStore<Version, Manifest>()

    public init(
        package: PackageReference,
        identityResolver: IdentityResolver,
        manager: RegistryManager,
        manifestLoader: ManifestLoaderProtocol,
        toolsVersionLoader: ToolsVersionLoaderProtocol,
        currentToolsVersion: ToolsVersion
    ) {
        self.package = package
        self.identityResolver = identityResolver
        self.registryManager = manager
        self.manifestLoader = manifestLoader
        self.toolsVersionLoader = toolsVersionLoader
        self.currentToolsVersion = currentToolsVersion
    }

    // MARK: - PackageContainer

    public func isToolsVersionCompatible(at version: Version) -> Bool {
        validToolsVersionsCache.memoize(version) {
            do {
                let toolsVersion = try self.toolsVersion(for: version)
                try toolsVersion.validateToolsVersion(currentToolsVersion, packageIdentity: package.identity)
                return true
            } catch {
                return false
            }
        }
    }

    public func toolsVersion(for version: Version) throws -> ToolsVersion {
        // TODO: Refactor ToolsVersionLoaderProtocol to support loading from string
        // TODO: Add support for version-specific manifests
        toolsVersionsCache.memoize(version) {
            return .currentToolsVersion
        }
    }

    public func versionsDescending() throws -> [Version] {
        try knownVersionsCache.memoize {
            let versions = try temp_await { self.registryManager.fetchVersions(of: self.package, on: .sharedConcurrent, completion: $0) }
            return versions.sorted(by: <)
        }
    }

    public func versionsAscending() throws -> [Version] {
        try versionsDescending().reversed()
    }

    public func toolsVersionsAppropriateVersionsDescending() throws -> [Version] {
        try versionsDescending().filter(isToolsVersionCompatible(at:))
    }

    public func getDependencies(at version: Version, productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        let manifest = try manifestsCache.memoize(version) {
            try temp_await { registryManager.fetchManifest(for: version, of: self.package, using: self.manifestLoader, on: .sharedConcurrent, completion: $0) }
        }

        return try manifest.dependencyConstraints(productFilter: productFilter)
    }

    public func getDependencies(at revision: String, productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        assertionFailure("this method shouldn't be called") // FIXME: remove
        return []
    }

    public func getUnversionedDependencies(productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        assertionFailure("this method shouldn't be called") // FIXME: remove
        return []
    }

    public func getUpdatedIdentifier(at boundVersion: BoundVersion) throws -> PackageReference {
        return package
    }
}

// MARK: - CustomStringConvertible

extension RegistryPackageContainer: CustomStringConvertible {
    public var description: String {
        return "RegistryPackageContainer(\(package.identity))"
    }
}
