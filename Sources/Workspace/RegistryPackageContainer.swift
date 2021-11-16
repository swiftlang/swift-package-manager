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
import TSCBasic

public class RegistryPackageContainer: PackageContainer {
    public let package: PackageReference

    private let registryClient: RegistryClient
    private let identityResolver: IdentityResolver
    private let manifestLoader: ManifestLoaderProtocol
    private let toolsVersionLoader: ToolsVersionLoaderProtocol
    private let currentToolsVersion: ToolsVersion
    private let observabilityScope: ObservabilityScope

    private var knownVersionsCache = ThreadSafeBox<[Version]>()
    private var toolsVersionsCache = ThreadSafeKeyValueStore<Version, ToolsVersion>()
    private var validToolsVersionsCache = ThreadSafeKeyValueStore<Version, Bool>()
    private var manifestsCache = ThreadSafeKeyValueStore<Version, Manifest>()

    public init(
        package: PackageReference,
        identityResolver: IdentityResolver,
        registryClient: RegistryClient,
        manifestLoader: ManifestLoaderProtocol,
        toolsVersionLoader: ToolsVersionLoaderProtocol,
        currentToolsVersion: ToolsVersion,
        observabilityScope: ObservabilityScope
    ) {
        self.package = package
        self.identityResolver = identityResolver
        self.registryClient = registryClient
        self.manifestLoader = manifestLoader
        self.toolsVersionLoader = toolsVersionLoader
        self.currentToolsVersion = currentToolsVersion
        self.observabilityScope = observabilityScope
    }

    // MARK: - PackageContainer

    public func isToolsVersionCompatible(at version: Version) -> Bool {
        self.validToolsVersionsCache.memoize(version) {
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
        try self.toolsVersionsCache.memoize(version) {
            let manifests = try temp_await {
                self.registryClient.getAvailableManifests(
                    package: self.package.identity,
                    version: version,
                    observabilityScope: self.observabilityScope,
                    callbackQueue: .sharedConcurrent,
                    completion: $0
                )
            }

            // ToolsVersionLoader is designed to scan files to decide which is the best tools-version
            // as such, this writes a fake manifest based on the information returned by the registry
            // with only the header line which is all that is needed by ToolsVersionLoader
            let fileSystem = InMemoryFileSystem()
            for manifest in manifests {
                try fileSystem.writeFileContents(AbsolutePath.root.appending(component: manifest.key), string: "// swift-tools-version: \(manifest.value)")
            }
            return try self.toolsVersionLoader.load(at: .root, fileSystem: fileSystem)
        }
    }

    public func versionsDescending() throws -> [Version] {
        try self.knownVersionsCache.memoize {
            let versions = try temp_await {
                self.registryClient.fetchVersions(
                    package: self.package.identity,
                    observabilityScope: self.observabilityScope,
                    callbackQueue: .sharedConcurrent,
                    completion: $0
                )
            }
            return versions.sorted(by: >)
        }
    }

    public func versionsAscending() throws -> [Version] {
        try self.versionsDescending().reversed()
    }

    public func toolsVersionsAppropriateVersionsDescending() throws -> [Version] {
        try self.versionsDescending().filter(self.isToolsVersionCompatible(at:))
    }

    public func getDependencies(at version: Version, productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        let manifest = try manifestsCache.memoize(version) {
            return try self.loadManifest(version: version)
        }
        return try manifest.dependencyConstraints(productFilter: productFilter)
    }

    public func getDependencies(at revision: String, productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        throw InternalError("getDependencies for revision not supported by RegistryPackageContainer")
    }

    public func getUnversionedDependencies(productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        throw InternalError("getUnversionedDependencies not supported by RegistryPackageContainer")
    }

    public func loadPackageReference(at boundVersion: BoundVersion) throws -> PackageReference {
        return self.package
    }

    // FIXME: make this DRYer with toolsVersion(for:)
    // FIXME: improve the concurrency
    private func loadManifest(version: Version) throws -> Manifest {
        let manifests = try temp_await {
            self.registryClient.getAvailableManifests(
                package: self.package.identity,
                version: version,
                observabilityScope: self.observabilityScope,
                callbackQueue: .sharedConcurrent,
                completion: $0
            )
        }

        // ToolsVersionLoader is designed to scan files to decide which is the best tools-version
        // as such, this writes a fake manifest based on the information returned by the registry
        // with only the header line which is all that is needed by ToolsVersionLoader
        let fileSystem = InMemoryFileSystem()
        for manifest in manifests {
            try fileSystem.writeFileContents(AbsolutePath.root.appending(component: manifest.key), string: "// swift-tools-version: \(manifest.value)")
        }
        guard let mainToolsVersion = manifests.first(where: { $0.key == Manifest.filename })?.value else {
            throw StringError("Could not find the '\(Manifest.filename)' file for '\(self.package.identity)' '\(version)'")
        }
        let preferredToolsVersion = try self.toolsVersionLoader.load(at: .root, fileSystem: fileSystem)
        let customToolsVersion = preferredToolsVersion != mainToolsVersion ? preferredToolsVersion : nil

        // now that we know the tools version we need, fetch the manifest content
        let manifestContent = try temp_await {
            self.registryClient.getManifestContent(
                package: self.package.identity,
                version: version,
                customToolsVersion: customToolsVersion,
                observabilityScope: self.observabilityScope,
                callbackQueue: .sharedConcurrent,
                completion: $0
            )
        }

        // replace the fake manifest with the real manifest content
        let filename: String
        if let toolsVersion = customToolsVersion {
            filename = Manifest.basename + "@swift-\(toolsVersion).swift"
        } else {
            filename = Manifest.filename
        }
        try fileSystem.writeFileContents(AbsolutePath.root.appending(component: filename), string: manifestContent)

        // Validate the tools version.
        try preferredToolsVersion.validateToolsVersion(
            self.currentToolsVersion,
            packageIdentity: self.package.identity,
            packageVersion: "FIMXE"
        )

        // Load the manifest.
        return try temp_await {
            self.manifestLoader.load(
                at: .root,
                packageIdentity: self.package.identity,
                packageKind: self.package.kind,
                packageLocation: self.package.locationString,
                version: version,
                revision: nil,
                toolsVersion: preferredToolsVersion,
                identityResolver: self.identityResolver,
                fileSystem: fileSystem,
                observabilityScope: self.observabilityScope,
                on: .sharedConcurrent,
                completion: $0
            )
        }
    }
}

// MARK: - CustomStringConvertible

extension RegistryPackageContainer: CustomStringConvertible {
    public var description: String {
        return "RegistryPackageContainer(\(package.identity))"
    }
}
