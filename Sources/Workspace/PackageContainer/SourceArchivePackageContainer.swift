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

import Basics
import _Concurrency
import Foundation
import PackageGraph
import PackageLoading
import PackageModel

import struct TSCBasic.StringError
import struct TSCUtility.Version

/// A ``PackageContainer`` backed by a ``SourceArchiveProvider`` that resolves
/// versions, fetches manifests and discovers dependencies without cloning.
///
/// All heavy lifting (tag discovery, raw file fetching, submodule probing) is
/// delegated to ``SourceArchiveResolver`` and the provider; results are cached
/// in ``SourceArchiveMetadataCache``.
public final class SourceArchivePackageContainer: PackageContainer, CustomStringConvertible {
    public typealias Constraint = PackageContainerConstraint

    public let package: PackageReference
    public let provider: any SourceArchiveProvider
    private let resolver: SourceArchiveResolver
    private let metadataCache: SourceArchiveMetadataCache
    private let manifestLoader: ManifestLoaderProtocol
    private let identityResolver: IdentityResolver
    private let dependencyMapper: DependencyMapper
    private let currentToolsVersion: ToolsVersion
    private let observabilityScope: ObservabilityScope

    /// Lazy fallback to a git-backed container for revision/unversioned queries.
    /// PubGrub may call these entry points when a package graph mixes version
    /// and branch/revision constraints on the same package.
    private let gitContainerProvider: (@Sendable () async throws -> any PackageContainer)?
    private let _gitContainerMemoizer = ThrowingAsyncKeyValueMemoizer<String, any PackageContainer>()

    private struct TagCache {
        var tags: [ResolvedTag]
        var versionToTag: [Version: String]
        var tagToSHA: [String: String]
    }

    private let _tagCacheMemoizer = ThrowingAsyncKeyValueMemoizer<String, TagCache>()

    /// Cached tools versions keyed by semantic version.
    private var _toolsVersionCache = ThreadSafeKeyValueStore<Version, ToolsVersion>()

    /// Cached manifest content keyed by SHA.
    private var _manifestContentCache = ThreadSafeKeyValueStore<String, String>()

    /// Cached dependency constraints keyed by "version:productFilter".
    private var _dependenciesCache = ThreadSafeKeyValueStore<String, (Manifest, [Constraint])>()

    /// Cached loaded manifests keyed by version (different versions sharing
    /// the same commit SHA need distinct Manifest objects with their respective packageVersion).
    private var _manifestCache = ThreadSafeKeyValueStore<String, Manifest>()

    public init(
        package: PackageReference,
        provider: any SourceArchiveProvider,
        resolver: SourceArchiveResolver,
        metadataCache: SourceArchiveMetadataCache,
        manifestLoader: ManifestLoaderProtocol,
        identityResolver: IdentityResolver,
        dependencyMapper: DependencyMapper,
        currentToolsVersion: ToolsVersion,
        observabilityScope: ObservabilityScope,
        gitContainerProvider: (@Sendable () async throws -> any PackageContainer)? = nil
    ) {
        self.package = package
        self.provider = provider
        self.resolver = resolver
        self.metadataCache = metadataCache
        self.manifestLoader = manifestLoader
        self.identityResolver = identityResolver
        self.dependencyMapper = dependencyMapper
        self.currentToolsVersion = currentToolsVersion
        self.gitContainerProvider = gitContainerProvider
        self.observabilityScope = observabilityScope.makeChildScope(
            description: "SourceArchivePackageContainer",
            metadata: package.diagnosticsMetadata
        )
    }

    // MARK: - PackageContainer

    public var shouldInvalidatePinnedVersions: Bool {
        return false
    }

    public var description: String {
        "SourceArchivePackageContainer(\(package.identity))"
    }

    public func versionsAscending() async throws -> [Version] {
        let cache = try await self.resolvedTagCache()
        return cache.tags.compactMap { Version(tag: $0.name) }.sorted()
    }

    public func versionsDescending() async throws -> [Version] {
        try await self.versionsAscending().reversed()
    }

    public func toolsVersionsAppropriateVersionsDescending() async throws -> [Version] {
        let versions = try await self.versionsDescending()
        try await self.prefetchManifestContents(for: versions)
        var result: [Version] = []
        for version in versions {
            guard let tv = try? await self.toolsVersion(for: version) else {
                continue
            }
            if self.isValidToolsVersion(tv) {
                result.append(version)
            }
        }
        return result
    }

    public func toolsVersion(for version: Version) async throws -> ToolsVersion {
        if let cached = _toolsVersionCache[version] {
            return cached
        }
        let sha = try await self.sha(for: version)
        let content = try await self.fetchManifestContent(sha: sha)
        let toolsVersion = try ToolsVersionParser.parse(utf8String: content)
        _toolsVersionCache[version] = toolsVersion
        return toolsVersion
    }

    public func getDependencies(
        at version: Version,
        productFilter: ProductFilter,
        _ enabledTraits: EnabledTraits = ["default"]
    ) async throws -> [Constraint] {
        let cacheKey = "\(version):\(productFilter):\(enabledTraits.sorted())"
        if let cached = _dependenciesCache[cacheKey] {
            return cached.1
        }
        let sha = try await self.sha(for: version)
        let manifest = try await self.loadManifest(sha: sha, version: version)
        let constraints = try manifest.dependencyConstraints(
            productFilter: productFilter,
            enabledTraits
        )
        _dependenciesCache[cacheKey] = (manifest, constraints)
        return constraints
    }

    public func getDependencies(
        at revision: String,
        productFilter: ProductFilter,
        _ enabledTraits: EnabledTraits = ["default"]
    ) async throws -> [Constraint] {
        let container = try await self.getGitContainer()
        return try await container.getDependencies(
            at: revision, productFilter: productFilter, enabledTraits
        )
    }

    public func getUnversionedDependencies(
        productFilter: ProductFilter,
        _ enabledTraits: EnabledTraits = ["default"]
    ) async throws -> [Constraint] {
        let container = try await self.getGitContainer()
        return try await container.getUnversionedDependencies(
            productFilter: productFilter, enabledTraits
        )
    }

    private func getGitContainer() async throws -> any PackageContainer {
        guard let gitContainerProvider else {
            throw StringError(
                "source archive container does not support revision/unversioned dependencies for \(package.identity)"
            )
        }
        return try await _gitContainerMemoizer.memoize("git") {
            try await gitContainerProvider()
        }
    }

    public func isToolsVersionCompatible(at version: Version) async -> Bool {
        guard let tv = try? await self.toolsVersion(for: version) else {
            return false
        }
        return self.isValidToolsVersion(tv)
    }

    public func loadPackageReference(at boundVersion: BoundVersion) async throws -> PackageReference {
        switch boundVersion {
        case .version(let version):
            let sha = try await self.sha(for: version)
            let manifest = try await self.loadManifest(sha: sha, version: version)
            return self.package.withName(manifest.displayName)
        case .revision, .unversioned, .excluded:
            return self.package
        }
    }

    // MARK: - Public Helpers

    /// Returns the tag name for the given version, or `nil` if the version is
    /// not known.
    public func getTag(for version: Version) async throws -> String? {
        let cache = try await self.resolvedTagCache()
        return cache.versionToTag[version]
    }

    /// Returns the commit SHA for the given tag name.
    public func getRevision(forTag tag: String) async throws -> String {
        let cache = try await self.resolvedTagCache()
        guard let sha = cache.tagToSHA[tag] else {
            throw StringError("unknown tag '\(tag)'")
        }
        return sha
    }

    /// Checks whether the repository at the given version uses git submodules.
    public func hasSubmodules(at version: Version) async throws -> Bool {
        let sha = try await self.sha(for: version)

        let (owner, repo) = self.ownerAndRepo()
        if let metadata = try? metadataCache.getMetadata(owner: owner, repo: repo, sha: sha) {
            return metadata.hasSubmodules
        }

        let result = try await resolver.hasSubmodules(provider: provider, sha: sha)

        let metadata = SourceArchiveMetadata(hasSubmodules: result)
        try? metadataCache.setMetadata(owner: owner, repo: repo, sha: sha, metadata: metadata)

        return result
    }

    // MARK: - Internal (Test Support)

    /// Injects pre-resolved tags for testing, bypassing `git ls-remote`.
    /// This is internal so that `@testable import` tests can call it.
    func injectResolvedTags(_ tags: [ResolvedTag]) async throws {
        let cache = Self.buildTagCache(from: tags)
        _ = try await _tagCacheMemoizer.memoize(self.sourceControlURL().absoluteString) { cache }
    }

    // MARK: - Private

    private static func buildTagCache(from tags: [ResolvedTag]) -> TagCache {
        var versionToTag: [Version: String] = [:]
        var tagToSHA: [String: String] = [:]
        for tag in tags {
            tagToSHA[tag.name] = tag.sha
            if let version = Version(tag: tag.name) {
                if let existing = versionToTag[version] {
                    // Match SourceControlPackageContainer's tag preference:
                    // prefer the most specific tag (most dot-separated components),
                    // then non-v-prefixed when specificity is equal.
                    let newComponents = tag.name.components(separatedBy: ".").count
                    let existingComponents = existing.components(separatedBy: ".").count
                    if newComponents > existingComponents {
                        versionToTag[version] = tag.name
                    } else if newComponents == existingComponents && existing.hasPrefix("v") && !tag.name.hasPrefix("v") {
                        versionToTag[version] = tag.name
                    }
                } else {
                    versionToTag[version] = tag.name
                }
            }
        }
        return TagCache(tags: tags, versionToTag: versionToTag, tagToSHA: tagToSHA)
    }

    private func resolvedTagCache() async throws -> TagCache {
        let key = self.sourceControlURL().absoluteString
        return try await _tagCacheMemoizer.memoize(key) {
            let url = self.sourceControlURL()
            let tags = try await self.resolver.getTags(for: url)
            return Self.buildTagCache(from: tags)
        }
    }

    private func sha(for version: Version) async throws -> String {
        let cache = try await resolvedTagCache()
        guard let tag = cache.versionToTag[version] else {
            throw StringError("unknown version \(version)")
        }
        guard let sha = cache.tagToSHA[tag] else {
            throw StringError("unknown tag '\(tag)'")
        }
        return sha
    }

    /// Concurrently prefetches manifest contents for all versions, populating
    /// both the in-memory and disk caches. Subsequent calls to
    /// ``fetchManifestContent(sha:)`` will be cache hits.
    private func prefetchManifestContents(for versions: [Version]) async throws {
        var shasToFetch: [String] = []
        var seen = Set<String>()
        let (owner, repo) = self.ownerAndRepo()
        for version in versions {
            guard let sha = try? await self.sha(for: version),
                  !seen.contains(sha),
                  _manifestContentCache[sha] == nil else { continue }
            if (try? metadataCache.getManifest(
                owner: owner, repo: repo, sha: sha, filename: "Package.swift"
            )) != nil {
                seen.insert(sha)
                continue
            }
            seen.insert(sha)
            shasToFetch.append(sha)
        }

        guard !shasToFetch.isEmpty else { return }

        let swiftVersion = self.swiftVersion

        let maxConcurrent = shasToFetch.count > 500 ? 8 : 4
        let queue = AsyncOperationQueue(concurrentTasks: maxConcurrent)
        await withTaskGroup(of: (sha: String, filename: String, content: String)?.self) { group in
            for sha in shasToFetch {
                group.addTask {
                    try? await queue.withOperation {
                        try await self.fetchManifestFromRemote(
                            sha: sha, swiftVersion: swiftVersion
                        )
                    }
                }
            }
            for await result in group {
                if let (sha, filename, content) = result {
                    self._manifestContentCache[sha] = content
                    try? self.metadataCache.setManifest(
                        owner: owner, repo: repo, sha: sha,
                        filename: filename, content: content
                    )
                }
            }
        }
    }

    /// Fetches a manifest from the remote without touching any caches.
    private func fetchManifestFromRemote(
        sha: String,
        swiftVersion: Version
    ) async throws -> (sha: String, filename: String, content: String) {
        let variantFilename = try await resolver.probeManifestVariant(
            provider: provider, sha: sha, swiftVersion: swiftVersion
        )
        if let variantFilename {
            let content = try await resolver.fetchManifestFile(
                provider: provider, sha: sha, filename: variantFilename
            )
            return (sha, variantFilename, content)
        }
        let content = try await resolver.fetchManifest(provider: provider, sha: sha)
        return (sha, "Package.swift", content)
    }

    /// Fetches manifest content for a SHA, using cache.
    ///
    /// After fetching the base `Package.swift`, this method probes for a
    /// `Package@swift-X.Y.swift` variant matching the current tools version.
    /// If a variant is found, its content is fetched and used instead.
    private func fetchManifestContent(sha: String) async throws -> String {
        if let cached = _manifestContentCache[sha] {
            return cached
        }

        let (owner, repo) = self.ownerAndRepo()
        let swiftVersion = self.swiftVersion

        // Check disk cache before hitting the network. Probe variant filenames
        // (most specific first), then the base Package.swift.
        let variantCandidates = [
            "Package@swift-\(swiftVersion.major).\(swiftVersion.minor).\(swiftVersion.patch).swift",
            "Package@swift-\(swiftVersion.major).\(swiftVersion.minor).swift",
            "Package@swift-\(swiftVersion.major).swift",
        ]
        for candidate in variantCandidates {
            if let cached = try? metadataCache.getManifest(
                owner: owner, repo: repo, sha: sha, filename: candidate
            ) {
                _manifestContentCache[sha] = cached
                return cached
            }
        }
        if let cached = try? metadataCache.getManifest(
            owner: owner, repo: repo, sha: sha, filename: "Package.swift"
        ) {
            _manifestContentCache[sha] = cached
            return cached
        }

        // No cache hit — probe the network for a variant.
        let variantFilename = try await resolver.probeManifestVariant(
            provider: provider, sha: sha, swiftVersion: swiftVersion
        )

        if let variantFilename {
            let variantContent = try await resolver.fetchManifestFile(
                provider: provider, sha: sha, filename: variantFilename
            )
            _manifestContentCache[sha] = variantContent

            try? metadataCache.setManifest(
                owner: owner, repo: repo, sha: sha,
                filename: variantFilename, content: variantContent
            )
            return variantContent
        }

        let content = try await resolver.fetchManifest(provider: provider, sha: sha)
        _manifestContentCache[sha] = content

        try? metadataCache.setManifest(
            owner: owner, repo: repo, sha: sha,
            filename: "Package.swift", content: content
        )
        return content
    }

    /// Loads a full ``Manifest`` from the manifest content at the given SHA.
    private static func manifestCacheKey(version: Version?, sha: String) -> String {
        version?.description ?? sha
    }

    private func loadManifest(sha: String, version: Version?) async throws -> Manifest {
        let cacheKey = Self.manifestCacheKey(version: version, sha: sha)
        if let cached = _manifestCache[cacheKey] {
            return cached
        }

        let content = try await self.fetchManifestContent(sha: sha)
        let toolsVersion = try ToolsVersionParser.parse(utf8String: content)

        let fs = InMemoryFileSystem()
        try fs.writeFileContents(.root.appending(component: "Package.swift"), string: content)

        let manifest = try await self.manifestLoader.load(
            manifestPath: .root.appending(component: "Package.swift"),
            manifestToolsVersion: toolsVersion,
            packageIdentity: self.package.identity,
            packageKind: self.package.kind,
            packageLocation: self.package.locationString,
            packageVersion: (version: version, revision: sha),
            identityResolver: self.identityResolver,
            dependencyMapper: self.dependencyMapper,
            fileSystem: fs,
            observabilityScope: self.observabilityScope,
            delegateQueue: .sharedConcurrent
        )
        _manifestCache[cacheKey] = manifest
        return manifest
    }

    /// Extracts the source control URL from the package reference.
    private func sourceControlURL() -> SourceControlURL {
        switch self.package.kind {
        case .remoteSourceControl(let url):
            return url
        default:
            // This container should only be used for remote source control packages.
            return SourceControlURL(stringLiteral: self.package.locationString)
        }
    }

    private var swiftVersion: Version {
        Version(
            self.currentToolsVersion.major,
            self.currentToolsVersion.minor,
            self.currentToolsVersion.patch
        )
    }

    private func ownerAndRepo() -> (owner: String, repo: String) {
        self.provider.cacheKey
    }

    private func isValidToolsVersion(_ toolsVersion: ToolsVersion) -> Bool {
        do {
            try toolsVersion.validateToolsVersion(
                currentToolsVersion,
                packageIdentity: self.package.identity
            )
            return true
        } catch {
            return false
        }
    }
}
