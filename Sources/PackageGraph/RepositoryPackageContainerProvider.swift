/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageLoading
import SourceControl
import Utility

import struct PackageDescription.Version

/// Adaptor for exposing repositories as PackageContainerProvider instances.
///
/// This is the root class for bridging the manifest & SCM systems into the
/// interfaces used by the `DependencyResolver` algorithm.
public class RepositoryPackageContainerProvider: PackageContainerProvider {
    public typealias Container = RepositoryPackageContainer

    let repositoryManager: RepositoryManager
    let manifestLoader: ManifestLoaderProtocol
    
    /// Create a repository-based package provider.
    ///
    /// - Parameters:
    ///   - repositoryManager: The repository manager responsible for providing repositories.
    ///   - manifestLoader: The manifest loader instance.
    public init(repositoryManager: RepositoryManager, manifestLoader: ManifestLoaderProtocol) {
        self.repositoryManager = repositoryManager
        self.manifestLoader = manifestLoader
    }

    public func getContainer(for identifier: RepositorySpecifier) throws -> Container {
        // Resolve the container using the repository manager.
        //
        // FIXME: We need to move this to an async interface, or document the interface as thread safe.
        let handle = repositoryManager.lookup(repository: identifier)

        // Wait for the repository to be fetched.
        let wasAvailableCondition = Condition()
        var wasAvailableOpt: Bool? = nil
        handle.addObserver { handle in
            wasAvailableCondition.whileLocked{
                wasAvailableOpt = handle.isAvailable
                wasAvailableCondition.signal()
            }
        }
        while wasAvailableCondition.whileLocked({ wasAvailableOpt == nil}) {
            wasAvailableCondition.wait()
        }
        let wasAvailable = wasAvailableOpt!
        if !wasAvailable {
            throw RepositoryPackageResolutionError.unavailableRepository
        }

        // Open the repository.
        //
        // FIXME: Do we care about holding this open for the lifetime of the container.
        let repository = try handle.open()

        // Create the container wrapper.
        return RepositoryPackageContainer(identifier: identifier, repository: repository, manifestLoader: manifestLoader)
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

    /// The identifier of the repository.
    public let identifier: RepositorySpecifier

    /// The available version list (in order).
    public let versions: [Version]

    /// The opened repository.
    let repository: Repository

    /// The manifest loader.
    let manifestLoader: ManifestLoaderProtocol

    /// The versions in the repository and their corresponding tags.
    let knownVersions: [Version: String]
    
    /// The cached dependency information.
    private var dependenciesCache: [Version: [RepositoryPackageConstraint]] = [:]
    private var dependenciesCacheLock = Lock()
    
    init(identifier: RepositorySpecifier, repository: Repository, manifestLoader: ManifestLoaderProtocol) {
        self.identifier = identifier
        self.repository = repository
        self.manifestLoader = manifestLoader

        // Compute the map of known versions and sorted version set.
        //
        // FIXME: Move this utility to a more stable location.
        self.knownVersions = Git.convertTagsToVersionMap(repository.tags)
        self.versions = [Version](knownVersions.keys).sorted()
    }

    public var description: String {
        return "RepositoryPackageContainer(\(identifier.url.debugDescription))"
    }

    public func getTag(for version: Version) -> String? {
        return knownVersions[version]
    }

    public func getRevision(for tag: String) throws -> Revision {
        return try repository.resolveRevision(tag: tag)
    }

    public func getDependencies(at version: Version) throws -> [RepositoryPackageConstraint] {
        // FIXME: Get a caching helper for this.
        return try dependenciesCacheLock.withLock{
            if let result = dependenciesCache[version] {
                return result
            }

            // FIXME: We should have a persistent cache for these.
            let tag = knownVersions[version]!
            let revision = try repository.resolveRevision(tag: tag)
            let fs = try repository.openFileView(revision: revision)
            let manifest = try manifestLoader.load(packagePath: AbsolutePath.root, baseURL: identifier.url, version: version, fileSystem: fs)
            let result = manifest.package.dependencies.map{
                RepositoryPackageConstraint(container: RepositorySpecifier(url: $0.url), versionRequirement: .range($0.versionRange))
            }
            dependenciesCache[version] = result

            return result
        }
    }
}
