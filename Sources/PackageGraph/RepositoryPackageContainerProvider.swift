/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Dispatch

import TSCBasic
import PackageLoading
import PackageModel
import SourceControl
import TSCUtility

/// Adaptor for exposing repositories as PackageContainerProvider instances.
///
/// This is the root class for bridging the manifest & SCM systems into the
/// interfaces used by the `DependencyResolver` algorithm.
public class RepositoryPackageContainerProvider: PackageContainerProvider {
    let repositoryManager: RepositoryManager
    let manifestLoader: ManifestLoaderProtocol
    let config: SwiftPMConfig

    /// The tools version currently in use. Only the container versions less than and equal to this will be provided by
    /// the container.
    let currentToolsVersion: ToolsVersion

    /// The tools version loader.
    let toolsVersionLoader: ToolsVersionLoaderProtocol

    /// Queue for callbacks.
    private let callbacksQueue = DispatchQueue(label: "org.swift.swiftpm.container-provider")

    /// Create a repository-based package provider.
    ///
    /// - Parameters:
    ///   - repositoryManager: The repository manager responsible for providing repositories.
    ///   - manifestLoader: The manifest loader instance.
    ///   - currentToolsVersion: The current tools version in use.
    ///   - toolsVersionLoader: The tools version loader.
    public init(
        repositoryManager: RepositoryManager,
        config: SwiftPMConfig = SwiftPMConfig(),
        manifestLoader: ManifestLoaderProtocol,
        currentToolsVersion: ToolsVersion = ToolsVersion.currentToolsVersion,
        toolsVersionLoader: ToolsVersionLoaderProtocol = ToolsVersionLoader()
    ) {
        self.repositoryManager = repositoryManager
        self.config = config
        self.manifestLoader = manifestLoader
        self.currentToolsVersion = currentToolsVersion
        self.toolsVersionLoader = toolsVersionLoader
    }

    public func getContainer(
        for identifier: PackageReference,
        skipUpdate: Bool,
        completion: @escaping (Result<PackageContainer, Swift.Error>) -> Void
    ) {
        // If the container is local, just create and return a local package container.
        if identifier.kind != .remote {
            callbacksQueue.async {
                let container = LocalPackageContainer(identifier,
                    config: self.config,
                    manifestLoader: self.manifestLoader,
                    toolsVersionLoader: self.toolsVersionLoader,
                    currentToolsVersion: self.currentToolsVersion,
                    fs: self.repositoryManager.fileSystem)
                completion(.success(container))
            }
            return
        }

        // Resolve the container using the repository manager.
        repositoryManager.lookup(repository: identifier.repository, skipUpdate: skipUpdate) { result in
            // Create the container wrapper.
            let container = result.tryMap { handle -> PackageContainer in
                // Open the repository.
                //
                // FIXME: Do we care about holding this open for the lifetime of the container.
                let repository = try handle.open()
                return RepositoryPackageContainer(
                    identifier: identifier,
                    config: self.config,
                    repository: repository,
                    manifestLoader: self.manifestLoader,
                    toolsVersionLoader: self.toolsVersionLoader,
                    currentToolsVersion: self.currentToolsVersion
                )
            }
            completion(container)
        }
    }
}

enum RepositoryPackageResolutionError: Swift.Error {
    /// A requested repository could not be cloned.
    case unavailableRepository
}

extension PackageReference {
    /// The repository of the package.
    ///
    /// This should only be accessed when the reference is not local.
    public var repository: RepositorySpecifier {
        precondition(kind == .remote)
        return RepositorySpecifier(url: path)
    }
}

public typealias RepositoryPackageConstraint = PackageContainerConstraint

/// Base class for the package container.
public class BasePackageContainer: PackageContainer {
    public typealias Identifier = PackageReference

    public let identifier: Identifier

    let config: SwiftPMConfig

    /// The manifest loader.
    let manifestLoader: ManifestLoaderProtocol

    /// The tools version loader.
    let toolsVersionLoader: ToolsVersionLoaderProtocol

    /// The current tools version in use.
    let currentToolsVersion: ToolsVersion

    public func versions(filter isIncluded: (Version) -> Bool) -> AnySequence<Version> {
        fatalError("This should never be called")
    }

    public var reversedVersions: [Version] {
        fatalError("This should never be called")
    }

    public func getDependencies(at version: Version, productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        fatalError("This should never be called")
    }

    public func getDependencies(at revision: String, productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        fatalError("This should never be called")
    }

    public func getUnversionedDependencies(productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        fatalError("This should never be called")
    }

    public func getUpdatedIdentifier(at boundVersion: BoundVersion) throws -> Identifier {
        fatalError("This should never be called")
    }

    public func isToolsVersionCompatible(at version: Version) -> Bool {
        fatalError("This should never be called")
    }

    fileprivate init(
        _ identifier: Identifier,
        config: SwiftPMConfig,
        manifestLoader: ManifestLoaderProtocol,
        toolsVersionLoader: ToolsVersionLoaderProtocol,
        currentToolsVersion: ToolsVersion
    ) {
        self.identifier = identifier
        self.config = config
        self.manifestLoader = manifestLoader
        self.toolsVersionLoader = toolsVersionLoader
        self.currentToolsVersion = currentToolsVersion
    }

    public var _isRemoteContainer: Bool? {
        return nil
    }
}

/// Local package container.
///
/// This class represent packages that are referenced locally in the file system.
/// There is no need to perform any git operations on such packages and they
/// should be used as-is. Infact, they might not even have a git repository.
/// Examples: Root packages, local dependencies, edited packages.
public class LocalPackageContainer: BasePackageContainer, CustomStringConvertible  {

    /// The file system that shoud be used to load this package.
    let fs: FileSystem

    private var _manifest: Manifest? = nil
    private func loadManifest() throws -> Manifest {
        if let manifest = _manifest {
            return manifest
        }

        // Load the tools version.
        let toolsVersion = try toolsVersionLoader.load(at: AbsolutePath(identifier.path), fileSystem: fs)

        // Validate the tools version.
        try toolsVersion.validateToolsVersion(self.currentToolsVersion, packagePath: identifier.path)

        // Load the manifest.
        _manifest = try manifestLoader.load(
            package: AbsolutePath(identifier.path),
            baseURL: identifier.path,
            version: nil,
            toolsVersion: toolsVersion,
            packageKind: identifier.kind,
            fileSystem: fs)
        return _manifest!
    }

    public override func getUnversionedDependencies(productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        return try loadManifest().dependencyConstraints(productFilter: productFilter, config: config)
    }

    public override func getUpdatedIdentifier(at boundVersion: BoundVersion) throws -> Identifier {
        assert(boundVersion == .unversioned, "Unexpected bound version \(boundVersion)")
        let manifest = try loadManifest()
        return identifier.with(newName: manifest.name)
    }

    public init(
        _ identifier: Identifier,
        config: SwiftPMConfig,
        manifestLoader: ManifestLoaderProtocol,
        toolsVersionLoader: ToolsVersionLoaderProtocol,
        currentToolsVersion: ToolsVersion,
        fs: FileSystem = localFileSystem
    ) {
        assert(URL.scheme(identifier.path) == nil, "unexpected scheme \(URL.scheme(identifier.path)!) in \(identifier.path)")
        self.fs = fs
        super.init(
            identifier,
            config: config,
            manifestLoader: manifestLoader,
            toolsVersionLoader: toolsVersionLoader,
            currentToolsVersion: currentToolsVersion
        )
    }

    public var description: String {
        return "LocalPackageContainer(\(identifier.path))"
    }
}

/// Adaptor to expose an individual repository as a package container.
public class RepositoryPackageContainer: BasePackageContainer, CustomStringConvertible {

    // A wrapper for getDependencies() errors. This adds additional information
    // about the container to identify it for diagnostics.
    public struct GetDependenciesErrorWrapper: Swift.Error {

        /// The container which had this error.
        public let containerIdentifier: String

        /// The source control reference i.e. version, branch, revsion etc.
        public let reference: String

        /// The actual error that occurred.
        public let underlyingError: Swift.Error
    }

    /// This is used to remember if tools version of a particular version is
    /// valid or not.
    public private(set) var validToolsVersionsCache: [Version: Bool] = [:]

    /// The available version list (in reverse order).
    public override func versions(filter isIncluded: (Version) -> Bool) -> AnySequence<Version> {
        return AnySequence(_reversedVersions.filter(isIncluded).lazy.filter({
            // If we have the result cached, return that.
            if let result = self.validToolsVersionsCache[$0] {
                return result
            }

            // Otherwise, compute and cache the result.
            let isValid = (try? self.toolsVersion(for: $0)).flatMap(self.isValidToolsVersion(_:)) ?? false
            self.validToolsVersionsCache[$0] = isValid
            return isValid
        }))
    }

    public override var reversedVersions: [Version] { _reversedVersions }

    /// The opened repository.
    let repository: Repository

    /// The versions in the repository and their corresponding tags.
    let knownVersions: [Version: String]

    /// The versions in the repository sorted by latest first.
    let _reversedVersions: [Version]

    /// The cached dependency information.
    private var dependenciesCache: [String: (Manifest, [RepositoryPackageConstraint])] = [:]
    private var dependenciesCacheLock = Lock()

    init(
        identifier: PackageReference,
        config: SwiftPMConfig,
        repository: Repository,
        manifestLoader: ManifestLoaderProtocol,
        toolsVersionLoader: ToolsVersionLoaderProtocol,
        currentToolsVersion: ToolsVersion
    ) {
        self.repository = repository

        // Compute the map of known versions.
        //
        // FIXME: Move this utility to a more stable location.
        let knownVersionsWithDuplicates = Git.convertTagsToVersionMap(repository.tags)

        let knownVersions = knownVersionsWithDuplicates.mapValues({ tags -> String in
            if tags.count == 2 {
                // FIXME: Warn if the two tags point to different git references.
                return tags.first(where: { !$0.hasPrefix("v") })!
            }
            assert(tags.count == 1, "Unexpected number of tags")
            return tags[0]
        })

        self.knownVersions = knownVersions
        self._reversedVersions = [Version](knownVersions.keys).sorted().reversed()
        super.init(
            identifier,
            config: config,
            manifestLoader: manifestLoader,
            toolsVersionLoader: toolsVersionLoader,
            currentToolsVersion: currentToolsVersion
        )
    }

    public var description: String {
        return "RepositoryPackageContainer(\(identifier.repository.url.debugDescription))"
    }

    public override var _isRemoteContainer: Bool? {
        return true
    }

    public func getTag(for version: Version) -> String? {
        return knownVersions[version]
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
    private func toolsVersion(for version: Version) throws -> ToolsVersion {
        let tag = knownVersions[version]!
        let revision = try repository.resolveRevision(tag: tag)
        let fs = try repository.openFileView(revision: revision)
        return try toolsVersionLoader.load(at: .root, fileSystem: fs)
    }

    public override func getDependencies(at version: Version, productFilter: ProductFilter) throws -> [RepositoryPackageConstraint] {
        do {
            return try cachedDependencies(forIdentifier: version.description) {
                let tag = knownVersions[version]!
                let revision = try repository.resolveRevision(tag: tag)
                return try getDependencies(at: revision, version: version, productFilter: productFilter)
            }.1
        } catch {
            throw GetDependenciesErrorWrapper(
                containerIdentifier: identifier.repository.url, reference: version.description, underlyingError: error)
        }
    }

    public override func getDependencies(at revision: String, productFilter: ProductFilter) throws -> [RepositoryPackageConstraint] {
        do {
            return try cachedDependencies(forIdentifier: revision) {
                // resolve the revision identifier and return its dependencies.
                let revision = try repository.resolveRevision(identifier: revision)
                return try getDependencies(at: revision, productFilter: productFilter)
            }.1
        } catch {
            throw GetDependenciesErrorWrapper(
                containerIdentifier: identifier.repository.url, reference: revision, underlyingError: error)
        }
    }

    private func cachedDependencies(
        forIdentifier identifier: String,
        getDependencies: () throws -> (Manifest, [RepositoryPackageConstraint])
    ) throws -> (Manifest, [RepositoryPackageConstraint]) {
        return try dependenciesCacheLock.withLock {
            if let result = dependenciesCache[identifier] {
                return result
            }
            let result = try getDependencies()
            dependenciesCache[identifier] = result
            return result
        }
    }

    /// Returns dependencies of a container at the given revision.
    private func getDependencies(
        at revision: Revision,
        version: Version? = nil,
        productFilter: ProductFilter
    ) throws -> (Manifest, [RepositoryPackageConstraint]) {
        let manifest = try loadManifest(at: revision, version: version)
        return (manifest, manifest.dependencyConstraints(productFilter: productFilter, config: config))
    }

    public override func getUnversionedDependencies(productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        // We just return an empty array if requested for unversioned dependencies.
        return []
    }

    public override func getUpdatedIdentifier(at boundVersion: BoundVersion) throws -> Identifier {
        let revision: Revision
        var version: Version?
        switch boundVersion {
        case .version(let v):
            let tag = knownVersions[v]!
            version = v
            revision = try repository.resolveRevision(tag: tag)
        case .revision(let identifier):
            revision = try repository.resolveRevision(identifier: identifier)
        case .unversioned, .excluded:
            assertionFailure("Unexpected type requirement \(boundVersion)")
            return self.identifier
        }

        let manifest = try loadManifest(at: revision, version: version)
        return self.identifier.with(newName: manifest.name)
    }

    /// Returns true if the tools version is valid and can be used by this
    /// version of the package manager.
    private func isValidToolsVersion(_ toolsVersion: ToolsVersion) -> Bool {
        do {
            try toolsVersion.validateToolsVersion(currentToolsVersion, packagePath: "")
            return true
        } catch {
            return false
        }
    }

    public override func isToolsVersionCompatible(at version: Version) -> Bool {
        return (try? self.toolsVersion(for: version)).flatMap(self.isValidToolsVersion(_:)) ?? false
    }

    private func loadManifest(at revision: Revision, version: Version?) throws -> Manifest {
        let fs = try repository.openFileView(revision: revision)
        let packageURL = identifier.repository.url

        // Load the tools version.
        let toolsVersion = try toolsVersionLoader.load(at: .root, fileSystem: fs)

        // Validate the tools version.
        try toolsVersion.validateToolsVersion(
            self.currentToolsVersion, version: revision.identifier, packagePath: packageURL)

        // Load the manifest.
        return try manifestLoader.load(
            package: AbsolutePath.root,
            baseURL: packageURL,
            version: version,
            toolsVersion: toolsVersion,
            packageKind: identifier.kind,
            fileSystem: fs)
    }
}
