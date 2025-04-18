//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import _Concurrency
import Dispatch
import PackageGraph
import PackageLoading
import PackageModel
import PackageRegistry
import TSCBasic

import struct TSCUtility.Version

public class RegistryPackageContainer: PackageContainer {
    public let package: PackageReference

    private let registryClient: RegistryClient
    private let identityResolver: IdentityResolver
    private let dependencyMapper: DependencyMapper
    private let manifestLoader: ManifestLoaderProtocol
    private let currentToolsVersion: ToolsVersion
    private let observabilityScope: ObservabilityScope

    private var knownVersionsCache = ThreadSafeBox<[Version]>()
    private var toolsVersionsCache = ThrowingAsyncKeyValueMemoizer<Version, ToolsVersion>()
    private var validToolsVersionsCache = AsyncKeyValueMemoizer<Version, Bool>()
    private var manifestsCache = ThrowingAsyncKeyValueMemoizer<Version, Manifest>()
    private var availableManifestsCache = ThreadSafeKeyValueStore<Version, (manifests: [String: (toolsVersion: ToolsVersion, content: String?)], fileSystem: FileSystem)>()

    public init(
        package: PackageReference,
        identityResolver: IdentityResolver,
        dependencyMapper: DependencyMapper,
        registryClient: RegistryClient,
        manifestLoader: ManifestLoaderProtocol,
        currentToolsVersion: ToolsVersion,
        observabilityScope: ObservabilityScope
    ) {
        self.package = package
        self.identityResolver = identityResolver
        self.dependencyMapper = dependencyMapper
        self.registryClient = registryClient
        self.manifestLoader = manifestLoader
        self.currentToolsVersion = currentToolsVersion
        self.observabilityScope = observabilityScope.makeChildScope(
            description: "RegistryPackageContainer",
            metadata: package.diagnosticsMetadata)
    }

    // MARK: - PackageContainer

    public func isToolsVersionCompatible(at version: Version) async -> Bool {
        await self.validToolsVersionsCache.memoize(version) {
            do {
                let toolsVersion = try await self.toolsVersion(for: version)
                try toolsVersion.validateToolsVersion(self.currentToolsVersion, packageIdentity: self.package.identity)
                return true
            } catch {
                return false
            }
        }
    }

    public func toolsVersion(for version: Version) async throws -> ToolsVersion {
        try await self.toolsVersionsCache.memoize(version) {
            let result = try await self.getAvailableManifestsFilesystem(version: version)
            // find the manifest path and parse it's tools-version
            let manifestPath = try ManifestLoader.findManifest(packagePath: .root, fileSystem: result.fileSystem, currentToolsVersion: self.currentToolsVersion)
            return try ToolsVersionParser.parse(manifestPath: manifestPath, fileSystem: result.fileSystem)
        }
    }

    public func versionsDescending() async throws -> [Version] {
        try await self.knownVersionsCache.memoize {
            let metadata = try await self.registryClient.getPackageMetadata(
                package: self.package.identity,
                observabilityScope: self.observabilityScope
            )
            return metadata.versions.sorted(by: >)
        }
    }

    public func versionsAscending() async throws -> [Version] {
        try await self.versionsDescending().reversed()
    }

    public func toolsVersionsAppropriateVersionsDescending() async throws -> [Version] {
        var results: [Version] = []
        for version in try await self.versionsDescending() {
            if await self.isToolsVersionCompatible(at: version) {
                results.append(version)
            }
        }
        return results
    }

    public func getDependencies(at version: Version, productFilter: ProductFilter, _ enabledTraits: Set<String>?) async throws -> [PackageContainerConstraint] {
        let manifest = try await self.loadManifest(version: version)
        return try manifest.dependencyConstraints(productFilter: productFilter, enabledTraits)
    }

    public func getDependencies(at revision: String, productFilter: ProductFilter, _ enabledTraits: Set<String>?) throws -> [PackageContainerConstraint] {
        throw InternalError("getDependencies for revision not supported by RegistryPackageContainer")
    }

    public func getUnversionedDependencies(productFilter: ProductFilter, _ enabledTraits: Set<String>?) throws -> [PackageContainerConstraint] {
        throw InternalError("getUnversionedDependencies not supported by RegistryPackageContainer")
    }

    public func loadPackageReference(at boundVersion: BoundVersion) throws -> PackageReference {
        return self.package
    }

    // marked internal for testing
    internal func loadManifest(version: Version) async throws -> Manifest {
        let result = try await self.getAvailableManifestsFilesystem(version: version)

        let manifests = result.manifests
        let fileSystem = result.fileSystem

        // first, decide the tools-version we should use
        guard let defaultManifestToolsVersion = manifests.first(where: { $0.key == Manifest.filename })?.value.toolsVersion else {
            throw StringError("Could not find the '\(Manifest.filename)' file for '\(self.package.identity)' '\(version)'")
        }
        // find the preferred manifest path and parse it's tools-version
        let preferredToolsVersionManifestPath = try ManifestLoader.findManifest(packagePath: .root, fileSystem: fileSystem, currentToolsVersion: self.currentToolsVersion)
        let preferredToolsVersion = try ToolsVersionParser.parse(manifestPath: preferredToolsVersionManifestPath, fileSystem: fileSystem)
        // load the manifest content
        let loadManifest = {
            try await self.manifestLoader.load(
                packagePath: .root,
                packageIdentity: self.package.identity,
                packageKind: self.package.kind,
                packageLocation: self.package.locationString,
                packageVersion: (version: version, revision: nil),
                currentToolsVersion: self.currentToolsVersion,
                identityResolver: self.identityResolver,
                dependencyMapper: self.dependencyMapper,
                fileSystem: result.fileSystem,
                observabilityScope: self.observabilityScope,
                delegateQueue: .sharedConcurrent,
                callbackQueue: .sharedConcurrent
            )
        }

        if preferredToolsVersion == defaultManifestToolsVersion {
            // default tools version - we already have the content on disk from getAvailableManifestsFileSystem()
            return try await loadManifest()
        } else {
            // custom tools-version, we need to fetch the content from the server
            let manifestContent = try await self.registryClient.getManifestContent(
                package: self.package.identity,
                version: version,
                customToolsVersion: preferredToolsVersion,
                observabilityScope: self.observabilityScope
            )
            // find the fake manifest so we can replace it with the real manifest content
            guard let placeholderManifestFileName = try fileSystem.getDirectoryContents(.root).first(where: { file in
                if file == Manifest.basename + "@swift-\(preferredToolsVersion).swift" {
                    return true
                } else if preferredToolsVersion.patch == 0, file == Manifest.basename + "@swift-\(preferredToolsVersion.major).\(preferredToolsVersion.minor).swift" {
                    return true
                } else if preferredToolsVersion.patch == 0, preferredToolsVersion.minor == 0, file == Manifest.basename + "@swift-\(preferredToolsVersion.major).swift" {
                    return true
                } else {
                    return false
                }
            }) else {
                throw StringError("failed locating placeholder manifest for \(preferredToolsVersion)")
            }
            // replace the fake manifest with the real manifest content
            let manifestPath = Basics.AbsolutePath.root.appending(component: placeholderManifestFileName)
            try fileSystem.removeFileTree(manifestPath)
            try fileSystem.writeFileContents(manifestPath, string: manifestContent)
            // finally, load the manifest
            return try await loadManifest()
        }
    }

    private func getAvailableManifestsFilesystem(version: Version) async throws -> (manifests: [String: (toolsVersion: ToolsVersion, content: String?)], fileSystem: FileSystem) {
        // try cached first
        if let availableManifests = self.availableManifestsCache[version] {
            return availableManifests
        }

        // get from server
        let manifests = try await self.registryClient.getAvailableManifests(
            package: self.package.identity,
            version: version,
            observabilityScope: self.observabilityScope
        )

        // ToolsVersionLoader is designed to scan files to decide which is the best tools-version
        // as such, this writes a fake manifest based on the information returned by the registry
        // with only the header line which is all that is needed by ToolsVersionLoader
        let fileSystem = Basics.InMemoryFileSystem()
        for manifest in manifests {
            let content = manifest.value.content ?? "// swift-tools-version:\(manifest.value.toolsVersion)"
            try fileSystem.writeFileContents(AbsolutePath.root.appending(component: manifest.key), string: content)
        }
        self.availableManifestsCache[version] = (manifests: manifests, fileSystem: fileSystem)
        return (manifests: manifests, fileSystem: fileSystem)
    }

    public func getEnabledTraits(traitConfiguration: TraitConfiguration?, at version: Version?) async throws -> Set<String> {
        guard let version else {
            throw InternalError("Version needed to compute enabled traits for registry package \(self.package.identity.description)")
        }
        let manifest = try await loadManifest(version: version)
        guard manifest.packageKind.isRoot else {
            return []
        }
        let enabledTraits = try manifest.enabledTraits(using: traitConfiguration?.enabledTraits, enableAllTraits: traitConfiguration?.enableAllTraits ?? false)
        return enabledTraits ?? []
    }
}

// MARK: - CustomStringConvertible

extension RegistryPackageContainer: CustomStringConvertible {
    public var description: String {
        return "RegistryPackageContainer(\(package.identity))"
    }
}
