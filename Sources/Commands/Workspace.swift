/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageLoading
import PackageModel
import SourceControl
import Utility

/// An error in one of the workspace operations
public enum WorkspaceOperationError: Swift.Error {
    /// The requested repository could not be accessed.
    case unavailableRepository
}

/// A workspace represents the state of a working project directory.
///
/// This class is responsible for managing the persistent working state of a
/// project directory (e.g., the active set of checked out repositories) and for
/// coordinating the changes to that state.
///
/// This class does *not* support concurrent operations.
public class Workspace {
    public struct ManagedDependency {
        /// The specifier for the dependency.
        public let repository: RepositorySpecifier

        /// The checked out path of the dependency on disk, relative to the workspace checkouts path.
        public let subpath: RelativePath

        /// The current revision of the dependency.
        ///
        /// This should always be a revision corresponding to the version in the
        /// repository, but in certain circumstances it may not be the *current*
        /// one (e.g., if this data is accessed with a different version of the
        /// package manager, which would cause an alternate version to be
        /// resolved).
        public let currentRevision: Revision

        fileprivate init(repository: RepositorySpecifier, subpath: RelativePath, currentRevision: Revision) {
            self.repository = repository
            self.subpath = subpath
            self.currentRevision = currentRevision
        }
            
        // MARK: Persistence

        /// Create an instance from JSON data.
        fileprivate init?(json data: JSON) {
            guard case let .dictionary(contents) = data,
                  case let .string(repositoryURL)? = contents["repositoryURL"],
                  case let .string(subpathString)? = contents["subpath"],
                  case let .string(currentRevisionString)? = contents["currentRevision"] else {
                return nil
            }
            self.repository = RepositorySpecifier(url: repositoryURL)
            self.subpath = RelativePath(subpathString)
            self.currentRevision = Revision(identifier: currentRevisionString)
        }

        fileprivate func toJSON() -> JSON {
            return .dictionary([
                    "repositoryURL": .string(repository.url),
                    "subpath": .string(subpath.asString),
                    "currentRevision": .string(currentRevision.identifier),
                ])
        }
    }
    
    /// The path of the root package.
    public let rootPackagePath: AbsolutePath

    /// The path of the workspace data.
    public let dataPath: AbsolutePath

    /// The path for working repository clones (checkouts).
    let checkoutsPath: AbsolutePath

    /// The manifest loader to use.
    let manifestLoader: ManifestLoaderProtocol

    /// The checkout manager.
    private let checkoutManager: CheckoutManager

    /// The current state of managed dependencies.
    private var dependencyMap: [RepositorySpecifier: ManagedDependency]

    /// The known set of dependencies.
    public var dependencies: AnySequence<ManagedDependency> {
        return AnySequence<ManagedDependency>(dependencyMap.values)
    }
    
    /// Create a new workspace for the package at the given path.
    ///
    /// This will automatically load the persisted state for the package, if
    /// present. If the state isn't present then a default state will be
    /// constructed.
    ///
    /// - Parameters:
    ///   - path: The path of the root package.
    ///   - dataPath: The path for the workspace data files, if explicitly provided.
    ///   - manifestLoader: The manifest loader.
    /// - Throws: If the state was present, but could not be loaded.
    public init(
        rootPackage path: AbsolutePath,
        dataPath: AbsolutePath? = nil,
        manifestLoader: ManifestLoaderProtocol
    ) throws {
        self.rootPackagePath = path
        self.dataPath = dataPath ?? path.appending(component: ".build")
        self.manifestLoader = manifestLoader

        let repositoriesPath = self.dataPath.appending(component: "repositories")
        self.checkoutManager = CheckoutManager(path: repositoriesPath, provider: GitRepositoryProvider())
        self.checkoutsPath = self.dataPath.appending(component: "checkouts")

        // Ensure the cache path exists.
        try localFileSystem.createDirectory(repositoriesPath, recursive: true)
        try localFileSystem.createDirectory(checkoutsPath, recursive: true)
        
        // Initialize the default state.
        self.dependencyMap = [:]

        // Load the state from disk, if possible.
        if try !restoreState() {
            // There was no state, write the default state immediately.
            try saveState()
        }
    }

    // MARK: Low-level Operations

    /// Fetch a given `repository` and create a local checkout for it.
    ///
    /// This will first clone the repository into the canonical repositories
    /// location, if necessary, and then check it out from there.
    ///
    /// - Returns: The path of the local repository.
    /// - Throws: If the operation could not be satisfied.
    private func fetch(repository: RepositorySpecifier) throws -> AbsolutePath {
        // If we already have it, we are done.
        if let dependency = dependencyMap[repository] {
            return checkoutsPath.appending(dependency.subpath)
        }

        // If not, we need to get the repository from the checkouts.
        let handle = checkoutManager.lookup(repository: repository)

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
            throw WorkspaceOperationError.unavailableRepository
        }

        // Clone the repository into the checkouts.
        let path = checkoutsPath.appending(component: repository.fileSystemIdentifier)
        // Ensure the destination is free.
        _ = try? removeFileTree(path)
        try handle.cloneCheckout(to: path)

        return path
    }
    
    /// Create a local clone of the given `repository` checked out to `version`.
    ///
    /// If an existing clone is present, the repository will be reset to the
    /// requested revision, if necessary.
    ///
    /// - Parameters:
    ///   - repository: The repository to clone.
    ///   - revision: The revision to check out.
    /// - Returns: The path of the local repository.
    /// - Throws: If the operation could not be satisfied.
    //
    // FIXME: We are probably going to need a delegate interface so we have a
    // mechanism for observing the actions.
    func clone(repository: RepositorySpecifier, at revision: Revision) throws -> AbsolutePath {
        // Get the repository.
        let path = try fetch(repository: repository)

        // Check out the given revision.
        let workingRepo = try checkoutManager.provider.openCheckout(at: path)
        try workingRepo.checkout(revision: revision)

        // Write the state record.
        dependencyMap[repository] = ManagedDependency(
            repository: repository, subpath: path.relative(to: checkoutsPath), currentRevision: revision)
        try saveState()

        return path
    }

    /// Load the manifests for the current dependency tree.
    ///
    /// This will load the manifests for the root package as well as all the
    /// current dependencies from the working checkouts.
    ///
    /// Throws: If the root manifest could not be loaded.
    func loadDependencyManifests() throws -> (root: Manifest, dependencies: [Manifest]) {
        // Load the root manifest.
        let rootManifest = try manifestLoader.load(packagePath: rootPackagePath, baseURL: rootPackagePath.asString, version: nil)

        // Compute the transitive closure of available dependencies.
        let dependencies = transitiveClosure([KeyedPair(rootManifest, key: rootManifest.url)]) { node in
            return node.item.package.dependencies.flatMap{ dependency in
                // Check if this dependency is available.
                guard let managedDependency = dependencyMap[RepositorySpecifier(url: dependency.url)] else {
                    return nil
                }

                // If so, load its manifest.
                //
                // This should *never* fail, because we should only have ever
                // got this checkout via loading its manifest successfully.
                //
                // FIXME: Nevertheless, we should handle this failure explicitly.
                //
                // FIXME: We need to have the correct version to pass here.
                let manifest: Manifest = try! manifestLoader.load(packagePath: checkoutsPath.appending(managedDependency.subpath), baseURL: managedDependency.repository.url, version: nil)

                return KeyedPair(manifest, key: manifest.url)
            }
        }

        return (root: rootManifest, dependencies: dependencies.map{ $0.item })
    }

    // MARK: Persistence

    // FIXME: A lot of the persistence mechanism here is copied from
    // `CheckoutManager`. It would be nice to get actual infrastructure around
    // persistence to handle the boilerplate parts.
    
    private enum PersistenceError: Swift.Error {
        /// The schema does not match the current version.
        case invalidVersion
        
        /// There was a missing or malformed key.
        case unexpectedData
    }

    /// The current schema version for the persisted information.
    ///
    /// We currently discard any restored state if we detect a schema change.
    private static let currentSchemaVersion = 1

    /// The path at which we persist the manager state.
    var statePath: AbsolutePath {
        return dataPath.appending(component: "workspace-state.json")
    }

    /// Restore the manager state from disk.
    ///
    /// - Throws: A PersistenceError if the state was available, but could not
    /// be restored.
    ///
    /// - Returns: True if the state was restored, or false if the state wasn't
    /// available.
    private func restoreState() throws -> Bool {
        // If the state doesn't exist, don't try to load and fail.
        if !exists(statePath) {
            return false
        }

        // Load the state.
        //
        // FIXME: Build out improved file reading support.
        try fopen(statePath) { handle in
            let json = try JSON(bytes: ByteString(encodingAsUTF8: try handle.readFileContents()))

            // Load the state from JSON.
            guard case let .dictionary(contents) = json,
                  case let .int(version)? = contents["version"] else {
                throw PersistenceError.unexpectedData
            }
            guard version == Workspace.currentSchemaVersion else {
                throw PersistenceError.invalidVersion
            }
            guard case let .array(dependenciesData)? = contents["dependencies"] else {
                throw PersistenceError.unexpectedData
            }

            // Load the repositories.
            var dependencies = [RepositorySpecifier: ManagedDependency]()
            for dependencyData in dependenciesData {
                guard let repo = ManagedDependency(json: dependencyData) else {
                    throw PersistenceError.unexpectedData
                }
                dependencies[repo.repository] = repo
            }

            self.dependencyMap = dependencies
        }

        return true
    }
    
    /// Write the manager state to disk.
    private func saveState() throws {
        var data = [String: JSON]()
        data["version"] = .int(Workspace.currentSchemaVersion)
        data["dependencies"] = .array(dependencies.map{ $0.toJSON() })

        // FIXME: This should write atomically.
        try localFileSystem.writeFileContents(statePath, bytes: JSON.dictionary(data).toBytes())
    }
}
