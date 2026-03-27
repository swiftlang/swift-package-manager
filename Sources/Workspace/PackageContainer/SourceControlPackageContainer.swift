//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import _Concurrency
import Dispatch
import class Foundation.NSLock
import PackageFingerprint
import PackageGraph
import PackageLoading
import PackageModel
import SourceControl

import struct TSCBasic.RegEx

import struct TSCUtility.Version

/// Adaptor to expose an individual repository as a package container.
internal final class SourceControlPackageContainer: PackageContainer, CustomStringConvertible {
    public typealias Constraint = PackageContainerConstraint

    // A wrapper for getDependencies() errors. This adds additional information
    // about the container to identify it for diagnostics.
    public struct GetDependenciesError: Error, CustomStringConvertible {
        /// The repository  that encountered the error.
        public let repository: RepositorySpecifier

        /// The source control reference (version, branch, revision, etc) that was involved.
        public let reference: String

        /// The actual error that occurred.
        public let underlyingError: Error

        /// Optional suggestion for how to resolve the error.
        public let suggestion: String?

        /// Description shown for errors of this kind.
        public var description: String {
            var desc = "\(underlyingError) in \(self.repository.location)"
            if let suggestion {
                desc += " (\(suggestion))"
            }
            return desc
        }
    }

    public let package: PackageReference
    private let repositorySpecifier: RepositorySpecifier
    private let repository: Repository
    private let identityResolver: IdentityResolver
    private let dependencyMapper: DependencyMapper
    private let manifestLoader: ManifestLoaderProtocol
    private let currentToolsVersion: ToolsVersion
    private let fingerprintStorage: PackageFingerprintStorage?
    private let fingerprintCheckingMode: FingerprintCheckingMode
    private let observabilityScope: ObservabilityScope

    /// The cached dependency information.
    private var dependenciesCache = [String: [ProductFilter: (Manifest, [Constraint])]]()
    private var dependenciesCacheLock = NSLock()

    private var knownVersionsCache = ThreadSafeBox<[KnownVersionTag]?>()
    private var manifestsCache = ThrowingAsyncKeyValueMemoizer<String, Manifest>()
    private var toolsVersionsCache = ThreadSafeKeyValueStore<String, ToolsVersion>()

    /// This is used to remember if tools version of a particular version is
    /// valid or not.
    var validToolsVersionsCache = ThreadSafeKeyValueStore<String, Bool>()

    init(
        package: PackageReference,
        identityResolver: IdentityResolver,
        dependencyMapper: DependencyMapper,
        repositorySpecifier: RepositorySpecifier,
        repository: Repository,
        manifestLoader: ManifestLoaderProtocol,
        currentToolsVersion: ToolsVersion,
        fingerprintStorage: PackageFingerprintStorage?,
        fingerprintCheckingMode: FingerprintCheckingMode,
        observabilityScope: ObservabilityScope
    ) throws {
        self.package = package
        self.identityResolver = identityResolver
        self.dependencyMapper = dependencyMapper
        self.repositorySpecifier = repositorySpecifier
        self.repository = repository
        self.manifestLoader = manifestLoader
        self.currentToolsVersion = currentToolsVersion
        self.fingerprintStorage = fingerprintStorage
        self.fingerprintCheckingMode = fingerprintCheckingMode
        self.observabilityScope = observabilityScope.makeChildScope(
            description: "SourceControlPackageContainer",
            metadata: package.diagnosticsMetadata)
    }

    // Compute the map of known versions.
    private func knownVersions() throws -> [KnownVersionTag] {
        try self.knownVersionsCache.memoize {
            let knownVersionsWithDuplicates = try Self.convertTagsToVersionMap(
                tags: repository.getTags(),
                toolsVersion: self.currentToolsVersion
            )

            return knownVersionsWithDuplicates.values.map { value in
                KnownVersionTag(
                    version: value.version,
                    tag: Self.reconcilePreferredTag(value.tags)
                )
            }
        }
    }

    public func versionsAscending() throws -> [Version] {
        try self.knownVersions()
            .map(\.version)
            .sorted(by: Self.versionAscending)
    }

    /// The available version list (in reverse order).
    public func toolsVersionsAppropriateVersionsDescending() async throws -> [Version] {
        let reversedVersions = try await self.versionsDescending()
        return reversedVersions.lazy.filter {
            // If we have the result cached, return that.
            if let result = self.validToolsVersionsCache[$0.description] {
                return result
            }

            // Otherwise, compute and cache the result.
            let isValid = (try? self.toolsVersion(for: $0)).flatMap(self.isValidToolsVersion(_:)) ?? false
            self.validToolsVersionsCache[$0.description] = isValid
            return isValid
        }
    }

    public func getTag(for version: Version) -> String? {
        return try? self.tag(for: version)
    }

    func checkIntegrity(version: Version, revision: Revision) throws {
        guard let fingerprintStorage else {
            return
        }

        guard case .remoteSourceControl(let sourceControlURL) = self.package.kind else {
            return
        }

        let fingerprint: Fingerprint
        do {
            fingerprint = try fingerprintStorage.get(
                package: self.package,
                version: version,
                kind: .sourceControl,
                contentType: .sourceCode,
                observabilityScope: self.observabilityScope
            )
        } catch PackageFingerprintStorageError.notFound {
            fingerprint = Fingerprint(
                origin: .sourceControl(sourceControlURL),
                value: revision.identifier,
                contentType: .sourceCode
            )
            // Write to storage if fingerprint not yet recorded
            do {
                try fingerprintStorage.put(
                    package: self.package,
                    version: version,
                    fingerprint: fingerprint,
                    observabilityScope: self.observabilityScope
                )
            } catch PackageFingerprintStorageError.conflict(_, let existing) {
                let message = "Revision \(revision.identifier) for \(self.package) version \(version) does not match previously recorded value \(existing.value) from \(String(describing: existing.origin.url?.absoluteString))"
                switch self.fingerprintCheckingMode {
                case .strict:
                    throw StringError(message)
                case .warn:
                    observabilityScope.emit(warning: message)
                }
            }
        } catch {
            self.observabilityScope.emit(
                error: "Failed to get source control fingerprint for \(self.package) version \(version) from storage",
                underlyingError: error
            )
            throw error
        }

        // The revision (i.e., hash) must match that in fingerprint storage otherwise the integrity check fails
        if revision.identifier != fingerprint.value {
            let message = "Revision \(revision.identifier) for \(self.package) version \(version) does not match previously recorded value \(fingerprint.value)"
            switch self.fingerprintCheckingMode {
            case .strict:
                throw StringError(message)
            case .warn:
                observabilityScope.emit(warning: message)
            }
        }
    }

    /// Returns revision for the given tag.
    public func getRevision(forTag tag: String) throws -> Revision {
        return try repository.resolveRevision(tag: tag)
    }

    /// Returns revision for the given identifier.
    public func getRevision(forIdentifier identifier: String) throws -> Revision {
        return try repository.resolveRevision(identifier: identifier)
    }

    /// Returns the tools version of the given version of the package.
    public func toolsVersion(for version: Version) throws -> ToolsVersion {
        try self.toolsVersionsCache.memoize(version.description) {
            guard let tag = try self.tag(for: version) else {
                throw StringError("unknown tag \(version)")
            }
            let fileSystem = try repository.openFileView(tag: tag)
            // find the manifest path and parse it's tools-version
            let manifestPath = try ManifestLoader.findManifest(packagePath: .root, fileSystem: fileSystem, currentToolsVersion: self.currentToolsVersion)
            return try ToolsVersionParser.parse(manifestPath: manifestPath, fileSystem: fileSystem)
        }
    }

    public func getDependencies(at version: Version, productFilter: ProductFilter, _ enabledTraits: EnabledTraits = ["default"]) async throws -> [Constraint] {
        do {
            return try await self.getCachedDependencies(forIdentifier: version.description, productFilter: productFilter) {
                guard let tag = try self.tag(for: version) else {
                    throw StringError("unknown tag \(version)")
                }
                return try await self.loadDependencies(tag: tag, version: version, productFilter: productFilter, enabledTraits: enabledTraits)
            }.1
        } catch {
            throw GetDependenciesError(
                repository: self.repositorySpecifier,
                reference: version.description,
                underlyingError: error,
                suggestion: .none
            )
        }
    }

    public func getDependencies(at revision: String, productFilter: ProductFilter, _ enabledTraits: EnabledTraits = ["default"]) async throws -> [Constraint] {
        do {
            return try await self.getCachedDependencies(forIdentifier: revision, productFilter: productFilter) {
                // resolve the revision identifier and return its dependencies.
                let revision = try repository.resolveRevision(identifier: revision)
                return try await self.loadDependencies(at: revision, productFilter: productFilter, enabledTraits: enabledTraits)
            }.1
        } catch {
            // Examine the error to see if we can come up with a more informative and actionable error message.  We know that the revision is expected to be a branch name or a hash (tags are handled through a different code path).
            if let error = error as? GitRepositoryError, error.description.contains("Needed a single revision") {
                // It was a Git process invocation error.  Take a look at the repository to see if we can come up with a reasonable diagnostic.
                if let rev = try? repository.resolveRevision(identifier: revision), repository.exists(revision: rev) {
                    // Revision does exist, so something else must be wrong.
                    throw GetDependenciesError(
                        repository: self.repositorySpecifier,
                        reference: revision,
                        underlyingError: error,
                        suggestion: .none
                    )
                } else {
                    // Revision does not exist, so we customize the error.
                    let sha1RegEx = try! RegEx(pattern: #"\A[:xdigit:]{40}\Z"#)
                    let isBranchRev = sha1RegEx.matchGroups(in: revision).compactMap { $0 }.isEmpty
                    let errorMessage = "could not find " + (isBranchRev ? "a branch named ‘\(revision)’" : "the commit \(revision)")
                    let mainBranchExists = (try? repository.resolveRevision(identifier: "main")) != nil
                    let suggestion = (revision == "master" && mainBranchExists) ? "did you mean ‘main’?" : nil          //ignore-unacceptable-language
                    throw GetDependenciesError(
                        repository: self.repositorySpecifier,
                        reference: revision,
                        underlyingError: StringError(errorMessage),
                        suggestion: suggestion
                    )
                }
            }
            // If we get this far without having thrown an error, we wrap and throw the underlying error.
            throw GetDependenciesError(
                repository: self.repositorySpecifier,
                reference: revision,
                underlyingError: error,
                suggestion: .none
            )
        }
    }

    private func getCachedDependencies(
        forIdentifier identifier: String,
        productFilter: ProductFilter,
        getDependencies: () async throws -> (Manifest, [Constraint])
    ) async throws -> (Manifest, [Constraint]) {
        if let result = (self.dependenciesCacheLock.withLock { self.dependenciesCache[identifier, default: [:]][productFilter] }) {
            return result
        }
        let result = try await getDependencies()
        self.dependenciesCacheLock.withLock {
            self.dependenciesCache[identifier, default: [:]][productFilter] = result
        }
        return result
    }

    /// Returns dependencies of a container at the given revision.
    private func loadDependencies(
        tag: String,
        version: Version? = nil,
        productFilter: ProductFilter,
        enabledTraits: EnabledTraits
    ) async throws -> (Manifest, [Constraint]) {
        let manifest = try await self.loadManifest(tag: tag, version: version)
        return (manifest, try manifest.dependencyConstraints(productFilter: productFilter, enabledTraits))
    }

    /// Returns dependencies of a container at the given revision.
    private func loadDependencies(
        at revision: Revision,
        version: Version? = nil,
        productFilter: ProductFilter,
        enabledTraits: EnabledTraits
    ) async throws -> (Manifest, [Constraint]) {
        let manifest = try await self.loadManifest(at: revision, version: version)
        return (manifest, try manifest.dependencyConstraints(productFilter: productFilter, enabledTraits))
    }

    public func getUnversionedDependencies(productFilter: ProductFilter, _ enabledTraits: EnabledTraits = ["default"]) throws -> [Constraint] {
        // We just return an empty array if requested for unversioned dependencies.
        return []
    }

    public func loadPackageReference(at boundVersion: BoundVersion) async throws -> PackageReference {
        let revision: Revision
        var version: Version?
        switch boundVersion {
        case .version(let v):
            guard let tag = try self.tag(for: v) else {
                throw StringError("unknown tag \(v)")
            }
            version = v
            revision = try repository.resolveRevision(tag: tag)
        case .revision(let identifier, _):
            revision = try repository.resolveRevision(identifier: identifier)
        case .unversioned, .excluded:
            assertionFailure("Unexpected type requirement \(boundVersion)")
            return self.package
        }

        let manifest = try await self.loadManifest(at: revision, version: version)
        return self.package.withName(manifest.displayName)
    }

    /// Returns true if the tools version is valid and can be used by this
    /// version of the package manager.
    private func isValidToolsVersion(_ toolsVersion: ToolsVersion) -> Bool {
        do {
            try toolsVersion.validateToolsVersion(currentToolsVersion, packageIdentity: .plain("unknown"))
            return true
        } catch {
            return false
        }
    }

    public func isToolsVersionCompatible(at version: Version) -> Bool {
        return (try? self.toolsVersion(for: version)).flatMap(self.isValidToolsVersion(_:)) ?? false
    }

    private func loadManifest(tag: String, version: Version?) async throws -> Manifest {
        try await self.manifestsCache.memoize(tag) {
            let fileSystem = try self.repository.openFileView(tag: tag)
            return try await self.loadManifest(fileSystem: fileSystem, version: version, revision: tag)
        }
    }

    private func loadManifest(at revision: Revision, version: Version?) async throws -> Manifest {
        try await self.manifestsCache.memoize(revision.identifier) {
            let fileSystem = try self.repository.openFileView(revision: revision)
            return try await self.loadManifest(fileSystem: fileSystem, version: version, revision: revision.identifier)
        }
    }

    private func loadManifest(fileSystem: FileSystem, version: Version?, revision: String) async throws -> Manifest {
        // Load the manifest.
        return try await self.manifestLoader.load(
            packagePath: .root,
            packageIdentity: self.package.identity,
            packageKind: self.package.kind,
            packageLocation: self.package.locationString,
            packageVersion: (version: version, revision: revision),
            currentToolsVersion: self.currentToolsVersion,
            identityResolver: self.identityResolver,
            dependencyMapper: self.dependencyMapper,
            fileSystem: fileSystem,
            observabilityScope: self.observabilityScope,
            delegateQueue: .sharedConcurrent
        )
    }

    private func tag(for version: Version) throws -> String? {
        let knownVersions = try self.knownVersions()
        if !version.buildMetadataIdentifiers.isEmpty {
            if let exact = knownVersions.first(where: { $0.version.literalEqual(to: version) }) {
                return exact.tag
            }
        }

        let semanticMatches = knownVersions.filter { $0.version == version }
        guard !semanticMatches.isEmpty else {
            return nil
        }
        if semanticMatches.count == 1 {
            return semanticMatches[0].tag
        }

        return semanticMatches.sorted(by: { lhs, rhs in
            Self.versionAscending(lhs.version, rhs.version)
        }).first?.tag
    }

    private static func versionAscending(_ lhs: Version, _ rhs: Version) -> Bool {
        if lhs == rhs {
            return lhs.literalSortKey < rhs.literalSortKey
        }
        return lhs < rhs
    }

    private static func convertTagsToVersionMap(
        tags: [String],
        toolsVersion: ToolsVersion
    ) -> [LiteralVersionKey: (version: Version, tags: [String])] {
        // First, check if we need to restrict the tag set to version-specific tags.
        var knownVersions: [LiteralVersionKey: (version: Version, tags: [String])] = [:]
        var versionSpecificKnownVersions: [LiteralVersionKey: (version: Version, tags: [String])] = [:]

        for tag in tags {
            for versionSpecificKey in toolsVersion.versionSpecificKeys {
                if tag.hasSuffix(versionSpecificKey) {
                    let trimmedTag = String(tag.dropLast(versionSpecificKey.count))
                    if let version = Version(tag: trimmedTag) {
                        let key = LiteralVersionKey(version)
                        if versionSpecificKnownVersions[key] == nil {
                            versionSpecificKnownVersions[key] = (version, [])
                        }
                        versionSpecificKnownVersions[key]?.tags.append(tag)
                    }
                    break
                }
            }

            if let version = Version(tag: tag) {
                let key = LiteralVersionKey(version)
                if knownVersions[key] == nil {
                    knownVersions[key] = (version, [])
                }
                knownVersions[key]?.tags.append(tag)
            }
        }
        // Check if any version specific tags were found.
        // If true, then return the version specific tags,
        // or else return the version independent tags.
        if !versionSpecificKnownVersions.isEmpty {
            return versionSpecificKnownVersions
        } else {
            return knownVersions
        }
    }

    private static func reconcilePreferredTag(_ tags: [String]) -> String {
        if tags.count > 1 {
            // FIXME: Warn if the two tags point to different git references.
            // If multiple tags are present with the same semantic version (e.g. v1.0.0, 1.0.0, 1.0) reconcile which one
            // we prefer.
            // Prefer the most specific tag, e.g. 1.0.0 is preferred over 1.0.
            let tagsSortedBySpecificity = tags.sorted {
                let componentCounts = ($0.components(separatedBy: ".").count, $1.components(separatedBy: ".").count)
                if componentCounts.0 == componentCounts.1 {
                    // If they have the same number of components, favor the one without a `v` prefix.
                    // This matches previously defined behavior.
                    return $0.hasPrefix("v")
                }
                return componentCounts.0 < componentCounts.1
            }
            return tagsSortedBySpecificity.last!
        }

        assert(tags.count == 1, "Unexpected number of tags")
        return tags[0]
    }

    public var isRemoteContainer: Bool? {
        true
    }

    public var description: String {
        "SourceControlPackageContainer(\(self.repositorySpecifier))"
    }
}

private struct KnownVersionTag {
    let version: Version
    let tag: String
}

private struct LiteralVersionKey: Hashable {
    let major: Int
    let minor: Int
    let patch: Int
    let prereleaseIdentifiers: [String]
    let buildMetadataIdentifiers: [String]

    init(_ version: Version) {
        self.major = version.major
        self.minor = version.minor
        self.patch = version.patch
        self.prereleaseIdentifiers = version.prereleaseIdentifiers
        self.buildMetadataIdentifiers = version.buildMetadataIdentifiers
    }
}

extension Version {
    fileprivate var literalSortKey: String {
        if self.buildMetadataIdentifiers.isEmpty {
            return ""
        }
        return self.buildMetadataIdentifiers.joined(separator: ".")
    }
}
