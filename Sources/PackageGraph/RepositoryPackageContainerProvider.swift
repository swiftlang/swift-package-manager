/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Dispatch

import Basic
import PackageLoading
import PackageModel
import SourceControl
import class PackageDescription4.Package
import Utility

/// Adaptor for exposing repositories as PackageContainerProvider instances.
///
/// This is the root class for bridging the manifest & SCM systems into the
/// interfaces used by the `DependencyResolver` algorithm.
public class RepositoryPackageContainerProvider: PackageContainerProvider {
    public typealias Container = BasePackageContainer

    let repositoryManager: RepositoryManager
    let manifestLoader: ManifestLoaderProtocol

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
        // If the container is local, just create and return a local package container.
        if identifier.isLocal {
            callbacksQueue.async {
                let container = LocalPackageContainer(identifier,
                    manifestLoader: self.manifestLoader,
                    toolsVersionLoader: self.toolsVersionLoader,
                    currentToolsVersion: self.currentToolsVersion)
                completion(Result(container))
            }
            return
        }

        // Resolve the container using the repository manager.
        repositoryManager.lookup(repository: identifier.repository, skipUpdate: skipUpdate, diagnostics: DiagnosticsEngine()) { result in
//            // Create the container wrapper.
//            let container = result.mapAny { handle -> Container in
//                // Open the repository.
//                //
//                // FIXME: Do we care about holding this open for the lifetime of the container.
//                let repository = handle.open(diagnostics: DiagnosticsEngine())!
//                return RepositoryPackageContainer(
//                    identifier: identifier,
//                    repository: repository,
//                    manifestLoader: self.manifestLoader,
//                    toolsVersionLoader: self.toolsVersionLoader,
//                    currentToolsVersion: self.currentToolsVersion
//                )
//            }
//            completion(container)
        }
    }
}

enum RepositoryPackageResolutionError: Swift.Error {
    /// A requested repository could not be cloned.
    case unavailableRepository
}

/// A package reference.
///
/// This represents a reference to a package containing its identity and location.
public struct PackageReference: PackageContainerIdentifier, JSONMappable, JSONSerializable {

    /// Compute identity of a package given its URL.
    public static func computeIdentity(packageURL: String) -> String {
        // Get the last path component of the URL.
        var lastComponent = packageURL.split(separator: "/", omittingEmptySubsequences: true).last!

        // Strip `.git` suffix if present.
        //
        // FIXME: We need String() here because of https://bugs.swift.org/browse/SR-5627
        if String(lastComponent).hasSuffix(".git") {
            lastComponent = lastComponent[...lastComponent.index(lastComponent.endIndex, offsetBy: -5)]
        }

        return String(lastComponent).lowercased()
    }

    /// The identity of the package.
    public let identity: String

    /// The repository of the package.
    ///
    /// This should only be accessed when the reference is not local.
    public var repository: RepositorySpecifier {
        precondition(!isLocal)
        return RepositorySpecifier(url: path)
    }

    /// The path of the package.
    /// 
    /// This could be a remote repository, local repository or local package.
    public let path: String

    /// The package reference is a local package, i.e., it does not reference
    /// a git repository.
    public let isLocal: Bool

    /// Create a package reference given its identity and repository.
    public init(identity: String, path: String, isLocal: Bool = false) {
		assert(identity == identity.lowercased(), "The identity is expected to be lowercased")
        self.identity = identity
        self.path = path
        self.isLocal = isLocal
    }

    public static func ==(lhs: PackageReference, rhs: PackageReference) -> Bool {
        return lhs.identity == rhs.identity
    }

    public var hashValue: Int {
        return identity.hashValue
    }

    public init(json: JSON) throws {
        self.identity = try json.get("identity")
        self.path = try json.get("path")
        self.isLocal = try json.get("isLocal")
    }

    public func toJSON() -> JSON {
        return .init([
            "identity": identity,
            "path": path,
            "isLocal": isLocal,
        ])
    }
}

public typealias RepositoryPackageConstraint = PackageContainerConstraint<PackageReference>

/// Base class for the package container.
public class BasePackageContainer: PackageContainer {
    public typealias Identifier = PackageReference

    public let identifier: Identifier

    /// The manifest loader.
    let manifestLoader: ManifestLoaderProtocol

    /// The tools version loader.
    let toolsVersionLoader: ToolsVersionLoaderProtocol

    /// The current tools version in use.
    let currentToolsVersion: ToolsVersion

    public func versions(filter isIncluded: (Version) -> Bool) -> AnySequence<Version> {
        fatalError("This should never be called")
    }

    public func getDependencies(at version: Version) throws -> [PackageContainerConstraint<Identifier>] {
        fatalError("This should never be called")
    }

    public func getDependencies(at revision: String) throws -> [PackageContainerConstraint<Identifier>] {
        fatalError("This should never be called")
    }

    public func getUnversionedDependencies() throws -> [PackageContainerConstraint<Identifier>] {
        fatalError("This should never be called")
    }

    fileprivate init(
        _ identifier: Identifier,
        manifestLoader: ManifestLoaderProtocol,
        toolsVersionLoader: ToolsVersionLoaderProtocol,
        currentToolsVersion: ToolsVersion
    ) {
        self.identifier = identifier
        self.manifestLoader = manifestLoader
        self.toolsVersionLoader = toolsVersionLoader
        self.currentToolsVersion = currentToolsVersion
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

    public override func getUnversionedDependencies() throws -> [PackageContainerConstraint<Identifier>] {
        // Load the tools version.
        let toolsVersion = try toolsVersionLoader.load(at: AbsolutePath(identifier.path), fileSystem: fs)

        // Ensure current tools supports this package.
        guard self.currentToolsVersion >= toolsVersion else {
            // FIXME: Throw from here
            fatalError()
        }

        // Load the manifest.
        let manifest = try manifestLoader.load(
            packagePath: AbsolutePath(identifier.path),
            baseURL: identifier.path,
            version: nil,
            manifestVersion: toolsVersion.manifestVersion,
            fileSystem: fs)

        return manifest.package.dependencyConstraints()
    }

    public init(
        _ identifier: Identifier,
        manifestLoader: ManifestLoaderProtocol,
        toolsVersionLoader: ToolsVersionLoaderProtocol,
        currentToolsVersion: ToolsVersion,
        fs: FileSystem = localFileSystem
    ) {
        assert(URL.scheme(identifier.path) == nil)
        self.fs = fs
        super.init(
            identifier,
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

    /// The available version list (in reverse order).
    public override func versions(filter isIncluded: (Version) -> Bool) -> AnySequence<Version> {
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

    /// The versions in the repository and their corresponding tags.
    let knownVersions: [Version: String]

    /// The versions in the repository sorted by latest first.
    let reversedVersions: [Version]

    /// The cached dependency information.
    private var dependenciesCache: [String: [RepositoryPackageConstraint]] = [:]
    private var dependenciesCacheLock = Lock()

    init(
        identifier: PackageReference,
        repository: Repository,
        manifestLoader: ManifestLoaderProtocol,
        toolsVersionLoader: ToolsVersionLoaderProtocol,
        currentToolsVersion: ToolsVersion
    ) {
        self.repository = repository

        // Compute the map of known versions.
        //
        // FIXME: Move this utility to a more stable location.
        let knownVersions = Git.convertTagsToVersionMap(repository.tags)
        self.knownVersions = knownVersions
        self.reversedVersions = [Version](knownVersions.keys).sorted().reversed()
        super.init(
            identifier,
            manifestLoader: manifestLoader,
            toolsVersionLoader: toolsVersionLoader,
            currentToolsVersion: currentToolsVersion
        )
    }

    public var description: String {
        return "RepositoryPackageContainer(\(identifier.repository.url.debugDescription))"
    }

    public func getTag(for version: Version) -> String? {
        return knownVersions[version]
    }

    /// Returns revision for the given tag.
    public func getRevision(forTag tag: String) throws -> Revision {
        return repository.resolveRevision(tag: tag, diagnostics: DiagnosticsEngine())!
    }

    /// Returns revision for the given identifier.
    public func getRevision(forIdentifier identifier: String) throws -> Revision {
        return repository.resolveRevision(identifier: identifier, diagnostics: DiagnosticsEngine())!
    }

    /// Returns the tools version of the given version of the package.
    private func toolsVersion(for version: Version) throws -> ToolsVersion {
        let tag = knownVersions[version]!
        let revision = repository.resolveRevision(tag: tag, diagnostics: DiagnosticsEngine())!
        let fs = repository.openFileView(revision: revision, diagnostics: DiagnosticsEngine())!
        return try toolsVersionLoader.load(at: .root, fileSystem: fs)
    }

    public override func getDependencies(at version: Version) throws -> [RepositoryPackageConstraint] {
        do {
            return try cachedDependencies(forIdentifier: version.description) {
                let tag = knownVersions[version]!
                let revision = repository.resolveRevision(tag: tag, diagnostics: DiagnosticsEngine())!
                return try getDependencies(at: revision, version: version)
            }
        } catch {
            throw GetDependenciesErrorWrapper(
                containerIdentifier: identifier.repository.url, reference: version.description, underlyingError: error)
        }
    }

    public override func getDependencies(at revision: String) throws -> [RepositoryPackageConstraint] {
        do {
            return try cachedDependencies(forIdentifier: revision) {
                // resolve the revision identifier and return its dependencies.
                let revision = repository.resolveRevision(identifier: revision, diagnostics: DiagnosticsEngine())!
                return try getDependencies(at: revision)
            }
        } catch {
            throw GetDependenciesErrorWrapper(
                containerIdentifier: identifier.repository.url, reference: revision, underlyingError: error)
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
        let fs = repository.openFileView(revision: revision, diagnostics: DiagnosticsEngine())!

        // Load the tools version.
        let toolsVersion = try toolsVersionLoader.load(at: .root, fileSystem: fs)

        // Load the manifest.
        let manifest = try manifestLoader.load(
            package: AbsolutePath.root,
            baseURL: identifier.repository.url,
            version: version,
            manifestVersion: toolsVersion.manifestVersion,
            fileSystem: fs)

        return manifest.package.dependencyConstraints()
    }

    public override func getUnversionedDependencies() throws -> [PackageContainerConstraint<Identifier>] {
        // We just return an empty array if requested for unversioned dependencies.
        return []
    }
}
