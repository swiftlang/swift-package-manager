/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageLoading
import PackageModel
import SourceControl
import Utility

/// Adaptor for exposing repositories as PackageContainerProvider instances.
///
/// This is the root class for bridging the manifest & SCM systems into the
/// interfaces used by the `DependencyResolver` algorithm.
public class RepositoryPackageContainerProvider: PackageContainerProvider {
    public typealias Container = RepositoryPackageContainer

    let repositoryManager: RepositoryManager
    let manifestLoader: ManifestLoaderProtocol

    /// The tools version currently in use. Only the container versions less than and equal to this will be provided by
    /// the container.
    let currentToolsVersion: ToolsVersion

    /// The tools version loader.
    let toolsVersionLoader: ToolsVersionLoaderProtocol

    /// Create a repository-based package provider.
    ///
    /// - Parameters:
    ///   - repositoryManager: The repository manager responsible for providing repositories.
    ///   - manifestLoader: The manifest loader instance.
    ///   - currentToolsVersion: The current tools version in use.
    ///   - toolsVersionLoader: The tools version loader.
    public init(
        repositoryManager: RepositoryManager,
        manifestLoader: ManifestLoaderProtocol,
        currentToolsVersion: ToolsVersion = ToolsVersion.currentToolsVersion,
        toolsVersionLoader: ToolsVersionLoaderProtocol = ToolsVersionLoader()
    ) {
        self.repositoryManager = repositoryManager
        self.manifestLoader = manifestLoader
        self.currentToolsVersion = currentToolsVersion
        self.toolsVersionLoader = toolsVersionLoader
    }

    public func getContainer(
        for identifier: Container.Identifier,
        skipUpdate: Bool,
        completion: @escaping (Result<Container, AnyError>) -> Void
    ) {
        // Resolve the container using the repository manager.
        repositoryManager.lookup(repository: identifier, skipUpdate: skipUpdate) { result in
            // Create the container wrapper.
            let container = result.mapAny { handle -> Container in
                // Open the repository.
                //
                // FIXME: Do we care about holding this open for the lifetime of the container.
                let repository = try handle.open()
                return RepositoryPackageContainer(
                    identifier: identifier,
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

/// Abstract repository identifier.
extension RepositorySpecifier: PackageContainerIdentifier {}

public typealias RepositoryPackageConstraint = PackageContainerConstraint<RepositorySpecifier>

/// Adaptor to expose an individual repository as a package container.
public class RepositoryPackageContainer: PackageContainer, CustomStringConvertible {
    public typealias Identifier = RepositorySpecifier

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

    /// The identifier of the repository.
    public let identifier: RepositorySpecifier

    /// The available version list (in reverse order).
    public func versions(filter isIncluded: (Version) -> Bool) -> AnySequence<Version> {
        return AnySequence(reversedVersions.filter(isIncluded).lazy.filter({
            guard let toolsVersion = try? self.toolsVersion(for: $0),
                  self.currentToolsVersion >= toolsVersion else {
                return false
            }
            return true
        }))
    }
    /// The opened repository.
    let repository: Repository

    /// The manifest loader.
    let manifestLoader: ManifestLoaderProtocol

    /// The tools version loader.
    let toolsVersionLoader: ToolsVersionLoaderProtocol

    /// The current tools version in use.
    let currentToolsVersion: ToolsVersion

    /// The versions in the repository and their corresponding tags.
    let knownVersions: [Version: String]

    /// The versions in the repository sorted by latest first.
    let reversedVersions: [Version]

    /// The cached dependency information.
    private var dependenciesCache: [String: [RepositoryPackageConstraint]] = [:]
    private var dependenciesCacheLock = Lock()

    init(
        identifier: RepositorySpecifier,
        repository: Repository,
        manifestLoader: ManifestLoaderProtocol,
        toolsVersionLoader: ToolsVersionLoaderProtocol,
        currentToolsVersion: ToolsVersion
    ) {
        self.identifier = identifier
        self.repository = repository
        self.manifestLoader = manifestLoader
        self.toolsVersionLoader = toolsVersionLoader
        self.currentToolsVersion = currentToolsVersion

        // Compute the map of known versions.
        //
        // FIXME: Move this utility to a more stable location.
        self.knownVersions = Git.convertTagsToVersionMap(repository.tags)
        self.reversedVersions = [Version](self.knownVersions.keys).sorted().reversed()
    }

    public var description: String {
        return "RepositoryPackageContainer(\(identifier.url.debugDescription))"
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

    public func getDependencies(at version: Version) throws -> [RepositoryPackageConstraint] {
        do {
            return try cachedDependencies(forIdentifier: version.description) {
                let tag = knownVersions[version]!
                let revision = try repository.resolveRevision(tag: tag)
                return try getDependencies(at: revision, version: version)
            }
        } catch {
            throw GetDependenciesErrorWrapper(
                containerIdentifier: identifier.url, reference: version.description, underlyingError: error)
        }
    }

    public func getDependencies(at revision: String) throws -> [RepositoryPackageConstraint] {
        do {
            return try cachedDependencies(forIdentifier: revision) {
                // resolve the revision identifier and return its dependencies.
                let revision = try repository.resolveRevision(identifier: revision)
                return try getDependencies(at: revision)
            }
        } catch {
            throw GetDependenciesErrorWrapper(
                containerIdentifier: identifier.url, reference: revision, underlyingError: error)
        }
    }

    private func cachedDependencies(
        forIdentifier identifier: String,
        getDependencies: () throws -> [RepositoryPackageConstraint]
    ) throws -> [RepositoryPackageConstraint] {
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
        version: Version? = nil
    ) throws -> [RepositoryPackageConstraint] {
        let fs = try repository.openFileView(revision: revision)

        // Load the tools version.
        let toolsVersion = try toolsVersionLoader.load(at: .root, fileSystem: fs)

        // Load the manifest.
        let manifest = try manifestLoader.load(
            package: AbsolutePath.root,
            baseURL: identifier.url,
            version: version,
            manifestVersion: toolsVersion.manifestVersion,
            fileSystem: fs)

        return manifest.package.dependencyConstraints()
    }
}
