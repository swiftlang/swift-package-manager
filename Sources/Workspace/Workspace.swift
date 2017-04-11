/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Foundation
import PackageLoading
import PackageModel
import PackageGraph
import SourceControl
import Utility

/// An error in one of the workspace operations.
public enum WorkspaceError: Swift.Error {
    /// The repository has uncommited changes.
    case hasUncommitedChanges(repo: AbsolutePath)

    /// The repository has unpushed changes.
    case hasUnpushedChanges(repo: AbsolutePath)

    /// The dependency is already in edit mode.
    case dependencyAlreadyInEditMode

    /// The dependency is not in edit mode.
    case dependencyNotInEditMode

    /// The branch already exists in repository.
    case branchAlreadyExists

    /// The revision doesn't exists in repository.
    case nonExistentRevision

    /// The root package has incompatible tools version.
    case incompatibleToolsVersion(rootPackage: AbsolutePath, required: ToolsVersion, current: ToolsVersion)

    /// The package at edit destination is not the one user is trying to edit.
    case mismatchingDestinationPackage(path: AbsolutePath, destPackage: String, expectedPackage: String)
}

/// The delegate interface used by the workspace to report status information.
public protocol WorkspaceDelegate: class {
    /// The workspace is fetching additional repositories in support of
    /// loading a complete package.
    func fetchingMissingRepositories(_ urls: Set<String>)

    /// The workspace has started fetching this repository.
    func fetching(repository: String)

    /// The workspace has started cloning this repository.
    func cloning(repository: String)

    /// The workspace is checking out this repository at a version or revision.
    func checkingOut(repository: String, at reference: String)

    /// The workspace is removing this repository because it is no longer needed.
    func removing(repository: String)

    /// The workspace operation emitted this warning.
    func warning(message: String)
}

private class WorkspaceResolverDelegate: DependencyResolverDelegate {
    typealias Identifier = RepositoryPackageContainer.Identifier

    func added(container identifier: Identifier) {
    }
}

private class WorkspaceRepositoryManagerDelegate: RepositoryManagerDelegate {
    unowned let workspaceDelegate: WorkspaceDelegate

    init(workspaceDelegate: WorkspaceDelegate) {
        self.workspaceDelegate = workspaceDelegate
    }

    func fetching(handle: RepositoryManager.RepositoryHandle, to path: AbsolutePath) {
        workspaceDelegate.fetching(repository: handle.repository.url)
    }
}

/// A workspace represents the state of a working project directory.
///
/// The workspace is responsible for managing the persistent working state of a
/// project directory (e.g., the active set of checked out repositories) and for
/// coordinating the changes to that state.
///
/// This class glues together the basic facilities provided by the dependency
/// resolution, source control, and package graph loading subsystems into a
/// cohesive interface for exposing the high-level operations for the package
/// manager to maintain working package directories.
///
/// This class does *not* support concurrent operations.
public class Workspace {
    /// A struct representing all the current manifests (root + external) in a package graph.
    public struct DependencyManifests {
        /// The package graph root.
        let root: PackageGraphRoot

        /// The dependency manifests in the transitive closure of root manifest.
        let dependencies: [(manifest: Manifest, dependency: ManagedDependency)]

        /// Computes the URLs which are declared in the manifests but aren't present in dependencies.
        func missingURLs() -> Set<String> {
            let manifestsMap = Dictionary(items:
                root.manifests.map({ ($0.url, $0) }) +
                dependencies.map({ ($0.manifest.url, $0.manifest) }))

            let inputURLs = root.manifests.map({ $0.url }) + root.dependencies.map({ $0.url })

            var requiredURLs = transitiveClosure(inputURLs) { url in
                guard let manifest = manifestsMap[url] else { return [] }
                return manifest.package.dependencies.map({ $0.url })
            }
            requiredURLs.formUnion(inputURLs)

            let availableURLs = Set<String>(manifestsMap.keys)
            // We should never have loaded a manifest we don't need.
            assert(availableURLs.isSubset(of: requiredURLs))
            // These are the missing URLs.
            return requiredURLs.subtracting(availableURLs)
        }

        /// Find a package given its name.
        public func lookup(package name: String) -> (manifest: Manifest, dependency: ManagedDependency)? {
            return dependencies.first(where: { $0.manifest.name == name })
        }

        /// Find a manifest given its name.
        public func lookup(manifest name: String) -> Manifest? {
            return lookup(package: name)?.manifest
        }

        /// Returns constraints of the dependencies.
        func createDependencyConstraints() -> [RepositoryPackageConstraint] {
            var constraints = [RepositoryPackageConstraint]()
            // Iterate and add constraints from dependencies.
            for (externalManifest, managedDependency) in dependencies {
                let specifier = RepositorySpecifier(url: externalManifest.url)
                let constraint: RepositoryPackageConstraint

                switch managedDependency.state {
                case .edited:
                    // Create unversioned constraints for editable dependencies.
                    let dependencies = externalManifest.package.dependencyConstraints()

                    constraint = RepositoryPackageConstraint(
                        container: specifier, requirement: .unversioned(dependencies))

                case .checkout(let checkoutState):
                    // If we know the manifest is at a particular state, use that.
                    //
                    // FIXME: This backfires in certain cases when the
                    // graph is resolvable but this constraint makes the
                    // resolution unsatisfiable.
                    let requirement = checkoutState.requirement()

                    constraint = RepositoryPackageConstraint(
                        container: specifier, requirement: requirement)
                }

                constraints.append(constraint)
            }

            return constraints
        }

        /// Returns a list of constraints for any packages 'edited' or 'unmanaged'.
        func unversionedConstraints() -> [RepositoryPackageConstraint] {
            var constraints = [RepositoryPackageConstraint]()

            for (externalManifest, managedDependency) in dependencies {
                switch managedDependency.state {
                case .checkout: continue
                case .edited: break
                }
                let specifier = RepositorySpecifier(url: externalManifest.url)
                let dependencies = externalManifest.package.dependencyConstraints()
                constraints.append(RepositoryPackageConstraint(
                    container: specifier,
                    requirement: .unversioned(dependencies))
                )
            }
            return constraints
        }

        init(root: PackageGraphRoot, dependencies: [(Manifest, ManagedDependency)]) {
            self.root = root
            self.dependencies = dependencies
        }
    }

    /// The delegate interface.
    public let delegate: WorkspaceDelegate

    /// The path of the workspace data.
    public let dataPath: AbsolutePath

    /// The path for working repository clones (checkouts).
    let checkoutsPath: AbsolutePath

    /// The path where packages which are put in edit mode are checked out.
    let editablesPath: AbsolutePath

    /// The file system on which the workspace will operate.
    private var fileSystem: FileSystem

    /// The Pins store. The pins file will be created when first pin is added to pins store.
    public let pinsStore: LoadableResult<PinsStore>

    /// The manifest loader to use.
    let manifestLoader: ManifestLoaderProtocol

    /// The tools version currently in use.
    let currentToolsVersion: ToolsVersion

    /// The manifest loader to use.
    let toolsVersionLoader: ToolsVersionLoaderProtocol

    /// The repository manager.
    private let repositoryManager: RepositoryManager

    /// The package container provider.
    private let containerProvider: RepositoryPackageContainerProvider

    /// The current state of managed dependencies.
    public let managedDependencies: LoadableResult<ManagedDependencies>

    /// Enable prefetching containers in resolver.
    let isResolverPrefetchingEnabled: Bool

    /// Create a new package workspace.
    ///
    /// This will automatically load the persisted state for the package, if
    /// present. If the state isn't present then a default state will be
    /// constructed.
    ///
    /// - Parameters:
    ///   - dataPath: The path for the workspace data files.
    ///   - editablesPath: The path where editable packages should be placed.
    ///   - pinsFile: The path to pins file. If pins file is not present, it will be created.
    ///   - manifestLoader: The manifest loader.
    ///   - fileSystem: The file system to operate on.
    ///   - repositoryProvider: The repository provider to use in repository manager.
    /// - Throws: If the state was present, but could not be loaded.
    public init(
        dataPath: AbsolutePath,
        editablesPath: AbsolutePath,
        pinsFile: AbsolutePath,
        manifestLoader: ManifestLoaderProtocol,
        currentToolsVersion: ToolsVersion = ToolsVersion.currentToolsVersion,
        toolsVersionLoader: ToolsVersionLoaderProtocol = ToolsVersionLoader(),
        delegate: WorkspaceDelegate,
        fileSystem: FileSystem = localFileSystem,
        repositoryProvider: RepositoryProvider = GitRepositoryProvider(),
        isResolverPrefetchingEnabled: Bool = false
    ) {
        self.delegate = delegate
        self.dataPath = dataPath
        self.editablesPath = editablesPath
        self.manifestLoader = manifestLoader
        self.currentToolsVersion = currentToolsVersion
        self.toolsVersionLoader = toolsVersionLoader
        self.isResolverPrefetchingEnabled = isResolverPrefetchingEnabled

        let repositoriesPath = self.dataPath.appending(component: "repositories")
        self.repositoryManager = RepositoryManager(
            path: repositoriesPath,
            provider: repositoryProvider,
            delegate: WorkspaceRepositoryManagerDelegate(workspaceDelegate: delegate),
            fileSystem: fileSystem)
        self.checkoutsPath = self.dataPath.appending(component: "checkouts")
        self.containerProvider = RepositoryPackageContainerProvider(
            repositoryManager: repositoryManager,
            manifestLoader: manifestLoader,
            toolsVersionLoader: toolsVersionLoader)
        self.fileSystem = fileSystem

        self.pinsStore = LoadableResult {
            try PinsStore(pinsFile: pinsFile, fileSystem: fileSystem)
        }
        self.managedDependencies = LoadableResult {
            try ManagedDependencies(dataPath: dataPath, fileSystem: fileSystem)
        }
    }

    /// Create the cache directories.
    private func createCacheDirectories(diagnostics: DiagnosticsEngine) {
        do {
            try fileSystem.createDirectory(repositoryManager.path, recursive: true)
            try fileSystem.createDirectory(checkoutsPath, recursive: true)
        } catch {
            diagnostics.emit(error)
        }
    }

    /// Cleans the build artefacts from workspace data.
    ///
    /// - Parameters:
    ///     - diagnostics: The diagnostics engine that reports errors, warnings
    ///       and notes.
    public func clean(with diagnostics: DiagnosticsEngine) {
        guard let dependencies = diagnostics.wrap({ try managedDependencies.load() }) else {
            return
        }
        
        // These are the things we don't want to remove while cleaning.
        let protectedAssets = Set<String>([
            repositoryManager.path,
            checkoutsPath,
            dependencies.statePath
        ].map({ path in
            // Assert that these are present inside data directory.
            assert(path.parentDirectory == dataPath)
            return path.basename
        }))
        
        // If we have no data yet, we're done.
        guard fileSystem.exists(dataPath) else {
            return
        }
        
        guard let contents = diagnostics.wrap({ try fileSystem.getDirectoryContents(dataPath) }) else {
            return
        }
        
        // Remove all but protected paths.
        let contentsToRemove = Set(contents).subtracting(protectedAssets)
        for name in contentsToRemove {
            fileSystem.removeFileTree(dataPath.appending(RelativePath(name)))
        }
    }

    /// Resets the entire workspace by removing the data directory.
    public func reset() throws {
        try managedDependencies.load().reset()
        repositoryManager.reset()
        fileSystem.removeFileTree(dataPath)
    }

    /// Puts a dependency in edit mode creating a checkout in editables directory.
    ///
    /// - Parameters:
    ///     - dependency: The dependency to put in edit mode.
    ///     - packageName: The name of the package corresponding to the
    ///         dependency. This is used for the checkout directory name.
    ///     - path: If provided, creates or uses the checkout at this location.
    ///     - revision: If provided, the revision at which the dependency
    ///         should be checked out to otherwise current revision.
    ///     - checkoutBranch: If provided, a new branch with this name will be
    ///         created from the revision provided.
    /// - throws: WorkspaceError
    public func edit(
        dependency: ManagedDependency,
        packageName: String,
        path: AbsolutePath? = nil,
        revision: Revision?,
        checkoutBranch: String? = nil
    ) throws {
        // Check if we can edit this dependency.
        guard case .checkout(let checkoutState) = dependency.state else {
            throw WorkspaceDiagnostics.DependencyAlreadyInEditMode(dependencyURL: dependency.repository.url)
        }

        // If a path is provided then we use it as destination. If not, we
        // use the folder with packageName inside editablesPath.
        let destination = path ?? editablesPath.appending(component: packageName)

        // If there is something present at the destination, we confirm it has
        // a valid manifest with name same as the package we are trying to edit.
        if fileSystem.exists(destination) {
            // Get tools version and try to load the manifest.
            let toolsVersion = try toolsVersionLoader.load(
                at: destination, fileSystem: fileSystem)

            let manifest = try manifestLoader.load(
                package: destination,
                baseURL: dependency.repository.url,
                manifestVersion: toolsVersion.manifestVersion)

            guard manifest.name == packageName else {
                throw WorkspaceDiagnostics.MismatchingDestinationPackage(
                    editPath: destination,
                    expectedPackage: packageName,
                    destinationPackage: manifest.name)
            }
            // Emit warnings for branch and revision, if they're present.
            if let checkoutBranch = checkoutBranch {
                delegate.warning(message: "not checking out branch '\(checkoutBranch)' for dependency '\(packageName)'")
            }
            if let revision = revision {
                delegate.warning(message: "not using revsion '\(revision.identifier)' for dependency '\(packageName)'")
            }
        } else {
            // Otherwise, create a checkout at the destination from our repository store.
            //
            // Get handle to the repository.
            let handle = try repositoryManager.lookupSynchronously(repository: dependency.repository)
            let repo = try handle.open()

            // Do preliminary checks on branch and revision, if provided.
            if let branch = checkoutBranch, repo.exists(revision: Revision(identifier: branch)) {
                throw WorkspaceDiagnostics.BranchAlreadyExists(
                    dependencyURL: dependency.repository.url,
                    branch: branch)
            }
            if let revision = revision, !repo.exists(revision: revision) {
                throw WorkspaceDiagnostics.RevisionDoesNotExist(
                    dependencyURL: dependency.repository.url,
                    revision: revision.identifier)
            }

            try handle.cloneCheckout(to: destination, editable: true)
            let workingRepo = try repositoryManager.provider.openCheckout(at: destination)
            try workingRepo.checkout(revision: revision ?? checkoutState.revision)
            // Checkout to the new branch if provided.
            if let branch = checkoutBranch {
                try workingRepo.checkout(newBranch: branch)
            }
        }

        // For unmanaged dependencies, create the symlink under editables dir.
        if let path = path {
            try fileSystem.createDirectory(editablesPath)
            // FIXME: We need this to work with InMem file system too.
            try createSymlink(
                    editablesPath.appending(component: packageName),
                    pointingAt: path,
                    relative: false)
        }

        // Save the new state.
        // FIXME: We shouldn't need to reload the managed dependencies here.
        let managedDependencies = try self.managedDependencies.load()
        managedDependencies[dependency.repository] = dependency.editedDependency(
            subpath: RelativePath(packageName), unmanagedPath: path)
        try managedDependencies.saveState()
    }

    /// Ends the edit mode of a dependency which is in edit mode.
    ///
    /// - Parameters:
    ///     - dependency: The dependency to be unedited.
    ///     - forceRemove: If true, the dependency will be unedited even if has
    /// unpushed and uncommited changes. Otherwise will throw respective errors.
    ///
    /// - throws: WorkspaceError
    public func unedit(dependency: ManagedDependency, forceRemove: Bool) throws {
        var forceRemove = forceRemove

        switch dependency.state {
        // If the dependency isn't in edit mode, we can't unedit it.
        case .checkout:
            throw WorkspaceDiagnostics.DependencyNotInEditMode(dependencyURL: dependency.repository.url)
        case .edited(let path):
            if path != nil {
                // Set force remove to true for unmanaged dependencies.  Note that
                // this only removes the symlink under the editable directory and
                // not the actual unmanaged package.
                forceRemove = true
            }
        }

        // Form the edit working repo path.
        let path = editablesPath.appending(dependency.subpath)
        // Check for uncommited and unpushed changes if force removal is off.
        if !forceRemove {
            let workingRepo = try repositoryManager.provider.openCheckout(at: path)
            guard !workingRepo.hasUncommitedChanges() else {
                throw WorkspaceDiagnostics.UncommitedChanges(repositoryPath: path)
            }
            guard try !workingRepo.hasUnpushedCommits() else {
                throw WorkspaceDiagnostics.UnpushedChanges(repositoryPath: path)
            }
        }
        // Remove the editable checkout from disk.
        if fileSystem.exists(path) {
            fileSystem.removeFileTree(path)
        }
        // If this was the last editable dependency, remove the editables directory too.
        if fileSystem.exists(editablesPath), try fileSystem.getDirectoryContents(editablesPath).isEmpty {
            fileSystem.removeFileTree(editablesPath)
        }
        let managedDependencies = try self.managedDependencies.load()
        // Restore the dependency state.
        managedDependencies[dependency.repository] = dependency.basedOn
        // Save the state.
        try managedDependencies.saveState()
    }

    /// Pins a package at a given state.
    ///
    /// Only one of version, branch and revision will be used and in the same
    /// order. If none of these is provided, the dependency will be pinned at
    /// the current checkout state.
    ///
    /// - Parameters:
    ///   - dependency: The dependency to pin.
    ///   - packageName: The name of the package which is being pinned.
    ///   - version: The version to pin at.
    ///   - branch: The branch to pin at.
    ///   - revision: The revision to pin at.
    ///   - reason: The optional reason for pinning.
    /// - Throws: WorkspaceError, PinOperationError
    public func pin(
        dependency: ManagedDependency,
        packageName: String,
        rootPackages: [AbsolutePath],
        diagnostics: DiagnosticsEngine,
        version: Version? = nil,
        branch: String? = nil,
        revision: String? = nil,
        reason: String? = nil
    ) throws {
        assert(dependency.state.isCheckout, "Can not pin a dependency which is in being edited.")
        guard case .checkout(let currentState) = dependency.state else { fatalError() }

        // Compute the requirement.
        let requirement: RepositoryPackageConstraint.Requirement
        if let version = version {
            requirement = .versionSet(.exact(version))
        } else if let branch = branch {
            requirement = .revision(branch)
        } else if let revision = revision {
            requirement = .revision(revision)
        } else {
            requirement = currentState.requirement()
        }

        let pinsStore = try self.pinsStore.load()
        let rootManifests = loadRootManifests(packages: rootPackages, diagnostics: diagnostics)
        let currentManifests = loadDependencyManifests(rootManifests: rootManifests, diagnostics: diagnostics)
        guard !diagnostics.hasErrors else { return }

        // Compute constraints with the new pin and try to resolve
        // dependencies. We only commit the pin if the dependencies can be
        // resolved with new constraints.
        //
        // The constraints consist of three things:
        // * Unversioned constraints for edited packages.
        // * Root manifest contraints without pins.
        // * Exisiting pins except the dependency we're currently pinning.
        // * The constraint for the new pin we're trying to add.
        var constraints = currentManifests.unversionedConstraints()
        constraints += rootManifests.flatMap({ $0.package.dependencyConstraints() })

        var pins = pinsStore.createConstraints().filter({ $0.identifier != dependency.repository })
        pins.append(
            RepositoryPackageConstraint(
                container: dependency.repository, requirement: requirement))

        // Resolve the dependencies.
        let results = resolveDependencies(dependencies: constraints, pins: pins, diagnostics: diagnostics)
        guard !diagnostics.hasErrors else { return }

        // Update the checkouts based on new dependency resolution.
        try updateCheckouts(with: results)

        // Get the updated dependency.
        let managedDependencies = try self.managedDependencies.load()
        let newDependency = managedDependencies[dependency.repository]!

        // Assert that the dependency is at the pinned checkout state now.
        if case .checkout(let checkoutState) = newDependency.state {
            assert(checkoutState.requirement() == requirement)
        } else {
            assertionFailure()
        }

        // Add the record in pins store.
        try pin(
            pinsStore: pinsStore,
            dependency: newDependency,
            package: packageName,
            reason: reason)
    }

    /// Pins all of the dependencies to the loaded version.
    ///
    /// - Parameters:
    ///   - reason: The optional reason for pinning.
    ///   - reset: Remove all current pins before pinning dependencies.
    public func pinAll(
        pinsStore: PinsStore,
        dependencyManifests: DependencyManifests,
        reason: String? = nil,
        reset: Bool = false
    ) throws {
        if reset {
            try pinsStore.unpinAll()
        }
        // Start pinning each dependency.
        for dependencyManifest in dependencyManifests.dependencies {
            try pin(
                pinsStore: pinsStore,
                dependency: dependencyManifest.dependency,
                package: dependencyManifest.manifest.name,
                reason: reason)
        }
    }

    /// Pins the managed dependency.
    private func pin(
        pinsStore: PinsStore,
        dependency: ManagedDependency,
        package: String,
        reason: String?
    ) throws {
        let checkoutState: CheckoutState

        switch dependency.state {
        case .checkout(let state):
            checkoutState = state
        case .edited:
            // For editable dependencies, pin the underlying dependency if we have them.
            if let basedOn = dependency.basedOn, case .checkout(let state) = basedOn.state {
                checkoutState = state
            } else {
                return delegate.warning(message: "not pinning \(package). It is being edited but is no longer needed.")
            }
        }
        // Commit the pin.
        try pinsStore.pin(
            package: package,
            repository: dependency.repository,
            state: checkoutState,
            reason: reason)
    }

    // MARK: Low-level Operations

    /// Fetch a given `repository` and create a local checkout for it.
    ///
    /// This will first clone the repository into the canonical repositories
    /// location, if necessary, and then check it out from there.
    ///
    /// - Returns: The path of the local repository.
    /// - Throws: If the operation could not be satisfied.
    private func fetch(
        repository: RepositorySpecifier,
        managedDependencies: ManagedDependencies
    ) throws -> AbsolutePath {
        // If we already have it, fetch to update the repo from its remote.
        if let dependency = managedDependencies[repository] {
            let path = checkoutsPath.appending(dependency.subpath)

            // Make sure the directory is not missing (we will have to clone again
            // if not).
            if fileSystem.isDirectory(path) {
                // Fetch the checkout in case there are updates available.
                let workingRepo = try repositoryManager.provider.openCheckout(at: path)
                try workingRepo.fetch()
                return path
            }
        }

        // If not, we need to get the repository from the checkouts.
        let handle = try repositoryManager.lookupSynchronously(repository: repository)

        // Clone the repository into the checkouts.
        let path = checkoutsPath.appending(component: repository.fileSystemIdentifier)
        // Ensure the destination is free.
        fileSystem.removeFileTree(path)
        // Inform the delegate that we're starting cloning.
        delegate.cloning(repository: handle.repository.url)
        try handle.cloneCheckout(to: path, editable: false)

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
    ///   - version: The dependency version the repository is being checked out at, if known.
    /// - Returns: The path of the local repository.
    /// - Throws: If the operation could not be satisfied.
    func clone(
        repository: RepositorySpecifier,
        at checkoutState: CheckoutState
    ) throws -> AbsolutePath {
        let managedDependencies = try self.managedDependencies.load()
        // Get the repository.
        let path = try fetch(repository: repository, managedDependencies: managedDependencies)

        // Check out the given revision.
        let workingRepo = try repositoryManager.provider.openCheckout(at: path)
        // Inform the delegate.
        delegate.checkingOut(repository: repository.url, at: checkoutState.description)
        try workingRepo.checkout(revision: checkoutState.revision)

        // Write the state record.
        managedDependencies[repository] = ManagedDependency(
                repository: repository, subpath: path.relative(to: checkoutsPath),
                checkoutState: checkoutState)
        try managedDependencies.saveState()

        return path
    }

    func clone(specifier: RepositorySpecifier, requirement: PackageStateChange.Requirement) throws -> AbsolutePath {
        // FIXME: We need to get the revision here, and we don't have a
        // way to get it back out of the resolver which is very
        // annoying. Maybe we should make an SPI on the provider for
        // this?
        let container = try await { containerProvider.getContainer(for: specifier, completion: $0) }
        let checkoutState: CheckoutState

        switch requirement {
        case .version(let version):
            let tag = container.getTag(for: version)!
            let revision = try container.getRevision(forTag: tag)
            checkoutState = CheckoutState(revision: revision, version: version)

        case .revision(let revision, let branch):
            checkoutState = CheckoutState(revision: revision, branch: branch)
        }

        return try self.clone(repository: specifier, at: checkoutState)
    }

    /// This enum represents state of an external package.
    enum PackageStateChange {
        /// The requirement imposed by the the state.
        enum Requirement {
            /// A version requirement.
            case version(Version)

            /// A revision requirement.
            case revision(Revision, branch: String?)
        }

        /// The package is added.
        case added(Requirement)

        /// The package is removed.
        case removed

        /// The package is unchanged.
        case unchanged

        /// The package is updated.
        case updated(Requirement)
    }

    /// Updates the current dependencies.
    public func updateDependencies(
        rootPackages: [AbsolutePath],
        diagnostics: DiagnosticsEngine,
        repin: Bool = false
    ) {
        createCacheDirectories(diagnostics: diagnostics)
        // Load the root manifest and current manifests.
        let rootManifests = loadRootManifests(packages: rootPackages, diagnostics: diagnostics)
        let currentManifests = loadDependencyManifests(rootManifests: rootManifests, diagnostics: diagnostics)

        // Try to load pins store.
        // We can't proceed if there are errors at this point.
        guard let pinsStore = diagnostics.wrap({ try pinsStore.load() }),
              !diagnostics.hasErrors else {
            return
        }

        // Create constraints based on root manifest and pins for the update resolution.
        var updateConstraints = rootManifests.flatMap({ $0.package.dependencyConstraints() })
        // Add unversioned constraints for edited packages.
        updateConstraints += currentManifests.unversionedConstraints()

        var pins = [RepositoryPackageConstraint]()
        if !repin {
            pins += pinsStore.createConstraints()
        }

        // Resolve the dependencies.
        let updateResults = resolveDependencies(dependencies: updateConstraints, pins: pins, diagnostics: diagnostics)
        guard !diagnostics.hasErrors else { return }

        do {
            // Update the checkouts based on new dependency resolution.
            try updateCheckouts(with: updateResults, updateBranches: true)
            // Get updated manifests.
            let currentManifests = loadDependencyManifests(
                rootManifests: rootManifests, diagnostics: diagnostics)
            // If we're repinning, update the pins store.
            if repin && !diagnostics.hasErrors {
                try repinPackages(pinsStore, dependencyManifests: currentManifests)
            }
        } catch {
            diagnostics.emit(error)
        }
    }

    /// Repin the packages.
    ///
    /// This methods pins all packages if auto pinning is on.
    /// Otherwise, only currently pinned packages are repinned.
    private func repinPackages(_ pinsStore: PinsStore, dependencyManifests: DependencyManifests) throws {
        // If autopin is on, pin everything and return.
        if pinsStore.isAutoPinEnabled {
            return try pinAll(
                pinsStore: pinsStore,
                dependencyManifests: dependencyManifests,
                reset: true)
        }

        // Otherwise, we need to repin only the previous pins.
        let managedDependencies = try self.managedDependencies.load()
        for pin in pinsStore.pins {
            // Check if this is a stray pin.
            guard let dependency = managedDependencies[pin.repository] else {
                // FIXME: Use diagnostics engine when we have that.
                delegate.warning(message: "Consider unpinning \(pin.package), it is pinned at " +
                    "\(pin.state.description) but the dependency is not present.")
                continue
            }
            // Pin this dependency.
            try self.pin(
                pinsStore: pinsStore,
                dependency: dependency,
                package: pin.package,
                reason: pin.reason)
        }
    }

    /// Updates the current working checkouts i.e. clone or remove based on the
    /// provided dependency resolution result.
    ///
    /// - Parameters:
    ///   - updateResults: The updated results from dependency resolution.
    ///   - ignoreRemovals: Do not remove any checkouts.
    ///   - updateBranches: If the branches should be updated in case they're pinned.
    private func updateCheckouts(
        with updateResults: [(RepositorySpecifier, BoundVersion)],
        updateBranches: Bool = false
    ) throws {
        // Get the update package states from resolved results.
        let packageStateChanges = try computePackageStateChanges(
            resolvedDependencies: updateResults, updateBranches: updateBranches)
        // Update or clone new packages.
        for (specifier, state) in packageStateChanges {
            switch state {
            case .added(let requirement):
                _ = try clone(specifier: specifier, requirement: requirement)
            case .updated(let requirement):
                _ = try clone(specifier: specifier, requirement: requirement)
            case .removed:
                try remove(specifier: specifier)
            case .unchanged: break
            }
        }
    }

    /// Computes states of the packages based on last stored state.
    private func computePackageStateChanges(
        resolvedDependencies: [(RepositorySpecifier, BoundVersion)],
        updateBranches: Bool
    ) throws -> [RepositorySpecifier: PackageStateChange] {
        // Load pins store and managed dependendencies.
        let pinsStore = try self.pinsStore.load()
        let managedDependencies = try self.managedDependencies.load()

        var packageStateChanges = [RepositorySpecifier: PackageStateChange]()
        // Set the states from resolved dependencies results.
        for (specifier, binding) in resolvedDependencies {
            switch binding {
            case .excluded:
                fatalError("Unexpected excluded binding")

            case .unversioned:
                // Right not it is only possible to get unversioned binding if
                // a dependency is in editable state.
                assert(managedDependencies[specifier]?.state.isCheckout == false)
                packageStateChanges[specifier] = .unchanged

            case .revision(let identifier):
                // Get the latest revision from the container.
                let container = try await { containerProvider.getContainer(for: specifier, completion: $0) }
                var revision = try container.getRevision(forIdentifier: identifier)
                let branch = identifier == revision.identifier ? nil : identifier

                // If we have a branch and we shouldn't be updating the
                // branches, use the revision from pin instead (if present).
                if branch != nil {
                    if let pin = pinsStore.pins.first(where: { $0.repository == specifier }), !updateBranches {
                        revision = pin.state.revision
                    }
                }

                // First check if we have this dependency.
                if let currentDependency = managedDependencies[specifier] {
                    // If current state and new state are equal, we don't need
                    // to do anything.
                    let newState = CheckoutState(revision: revision, branch: branch)
                    if case .checkout(let checkoutState) = currentDependency.state, checkoutState == newState {
                        packageStateChanges[specifier] = .unchanged
                    } else {
                        // Otherwise, we need to update this dependency to this revision.
                        packageStateChanges[specifier] = .updated(.revision(revision, branch: branch))
                    }
                } else {
                    packageStateChanges[specifier] = .added(.revision(revision, branch: branch))
                }

            case .version(let version):
                if let currentDependency = managedDependencies[specifier] {
                    if case .checkout(let checkoutState) = currentDependency.state, checkoutState.version == version {
                        packageStateChanges[specifier] = .unchanged
                    } else {
                        packageStateChanges[specifier] = .updated(.version(version))
                    }
                } else {
                    packageStateChanges[specifier] = .added(.version(version))
                }
            }
        }
        // Set the state of any old package that might have been removed.
        let dependencies = managedDependencies.values
        for specifier in dependencies.lazy.map({$0.repository}) where packageStateChanges[specifier] == nil {
            packageStateChanges[specifier] = .removed
        }
        return packageStateChanges
    }

    /// Runs the dependency resolver based on constraints provided and returns the results.
    fileprivate func resolveDependencies(
        dependencies: [RepositoryPackageConstraint],
        pins: [RepositoryPackageConstraint],
        diagnostics: DiagnosticsEngine
    ) -> [(container: WorkspaceResolverDelegate.Identifier, binding: BoundVersion)] {
        let resolverDelegate = WorkspaceResolverDelegate()
        let resolver = DependencyResolver(
            containerProvider,
            resolverDelegate,
            isPrefetchingEnabled: isResolverPrefetchingEnabled)
        let result = resolver.resolve(dependencies: dependencies, pins: pins)
        switch result {
        case .success(let bindings):
            return bindings
        case .unsatisfiable(let dependencies, let pins):
            diagnostics.emit(data: ResolverDiagnostics.Unsatisfiable(dependencies: dependencies, pins: pins))
            return []
        case .error(let error):
            diagnostics.emit(error)
            return []
        }
    }

    // FIXME: Temporary shim while we transition to the new methods.
    public func loadDependencyManifests(
        rootManifests: [Manifest],
        diagnostics: DiagnosticsEngine
    ) -> DependencyManifests {
        return loadDependencyManifests(root: PackageGraphRoot(manifests: rootManifests), diagnostics: diagnostics)
    }

    /// Load the manifests for the current dependency tree.
    ///
    /// This will load the manifests for the root package as well as all the
    /// current dependencies from the working checkouts.
    public func loadDependencyManifests(
        root: PackageGraphRoot,
        diagnostics: DiagnosticsEngine
    ) -> DependencyManifests {

        // Try to load current managed dependencies, or emit and return.
        let managedDependencies: ManagedDependencies
        do {
            try fixManagedDependencies()
            managedDependencies = try self.managedDependencies.load()
        } catch {
            diagnostics.emit(error)
            return DependencyManifests(root: root, dependencies: [])
        }

        let rootDependencyManifests = root.dependencies.flatMap({
            // FIXME: We need to emit any errors here to the diagnostics (SR-4262).
            return loadManifest(forDependencyURL: $0.url, managedDependencies: managedDependencies)
        })
        let inputManifests = root.manifests + rootDependencyManifests

        // Compute the transitive closure of available dependencies.
        let dependencies = transitiveClosure(inputManifests.map({ KeyedPair($0, key: $0.url) })) { node in
            return node.item.package.dependencies.flatMap({ dependency in
                let manifest = loadManifest(forDependencyURL: dependency.url, managedDependencies: managedDependencies)
                return manifest.flatMap({ KeyedPair($0, key: $0.url) })
            })
        }
        // FIXME: Remove bang and emit errors (SR-4262).
        let deps = (rootDependencyManifests + dependencies.map({ $0.item })).map({ ($0, managedDependencies[$0.url]!) })
        return DependencyManifests(root: root, dependencies: deps)
    }

    /// Validates that all the edited dependencies are still present in the file system.
    /// If some checkout dependency is reomved form the file system, clone it again.
    /// If some edited dependency is removed from the file system, mark it as unedited and
    /// fallback on the original checkout.
    private func fixManagedDependencies() throws {
        let managedDependencies = try self.managedDependencies.load()
        for dependency in managedDependencies.values {
            let dependencyPath = path(for: dependency)
            if !fileSystem.isDirectory(dependencyPath) {
                switch dependency.state {
                case .checkout(let checkoutState):
                    // If some checkout dependency has been removed, clone it again.
                    _ = try clone(repository: dependency.repository, at: checkoutState)
                    // FIXME: Use diagnostics engine when we have that.
                    delegate.warning(message: "\(dependency.subpath.asString) is missing and has been cloned again.")
                case .edited:
                    // If some edited dependency has been removed, mark it as unedited.
                    try unedit(dependency: dependency, forceRemove: true)
                    // FIXME: Use diagnostics engine when we have that.
                    delegate.warning(message: "\(dependency.subpath.asString) was being edited but has been removed, " +
                        "falling back to original checkout.")
                }
            }
        }
    }

    /// Returns the location of the dependency.
    ///
    /// Checkout dependencies will return the subpath inside `checkoutsPath` and
    /// edited dependencies will either return a subpath inside `editablesPath` or
    /// a custom path.
    private func path(for dependency: ManagedDependency) -> AbsolutePath {
        switch dependency.state {
        case .checkout:
            return checkoutsPath.appending(dependency.subpath)
        case .edited(let path):
            return path ?? editablesPath.appending(dependency.subpath)
        }
    }

    /// Fetch and load the complete package at the given path.
    ///
    /// This will implicitly cause any dependencies not yet present in the
    /// working checkouts to be resolved, cloned, and checked out.
    ///
    /// When fetching additional dependencies, the existing checkout versions
    /// will never be re-bound (or even re-fetched) as a result of this
    /// operation. This implies that the resulting local state may not match
    /// what would be computed from a fresh clone, but this makes for a more
    /// consistent command line development experience.
    ///
    /// - Returns: The loaded package graph.
    @discardableResult
    public func loadPackageGraph(
        root: WorkspaceRoot,
        diagnostics: DiagnosticsEngine,
        createMultipleTestProducts: Bool = false
    ) -> PackageGraph {
        // Ensure the cache path exists and validate that edited dependencies.
        createCacheDirectories(diagnostics: diagnostics)

        // Load the root manifests and currently checked out manifests.
        let rootManifests = loadRootManifests(packages: root.packages, diagnostics: diagnostics) 

        // Load the current manifests.
        let graphRoot = PackageGraphRoot(manifests: rootManifests, dependencies: root.dependencies)
        let currentManifests = loadDependencyManifests(root: graphRoot, diagnostics: diagnostics)

        // Compute the missing URLs.
        let missingURLs = currentManifests.missingURLs()

        // Load the package graph if there are no missing URLs or if we
        // encountered some errors.
        if diagnostics.hasErrors || missingURLs.isEmpty {
            return PackageGraphLoader().load(
                root: PackageGraphRoot(manifests: rootManifests, dependencies: root.dependencies),
                externalManifests: currentManifests.dependencies.map({ $0.manifest }),
                diagnostics: diagnostics,
                fileSystem: fileSystem,
                shouldCreateMultipleTestProducts: createMultipleTestProducts
            )
        }

        // Start by informing the delegate of what is happening.
        delegate.fetchingMissingRepositories(missingURLs)

        var updatedManifests: DependencyManifests? = nil

        resolve: do {
            // Load the pins store.
            guard let pinsStore = diagnostics.wrap({ try pinsStore.load() }) else {
                break resolve
            }

            // Create the constraints.
            var constraints = [RepositoryPackageConstraint]()
            constraints += rootManifests.flatMap({ $0.package.dependencyConstraints() })
            constraints += root.constraints

            var pins = [RepositoryPackageConstraint]()
            pins += pinsStore.createConstraints()
            pins += currentManifests.createDependencyConstraints()

            // Perform dependency resolution.
            let result = resolveDependencies(dependencies: constraints, pins: pins, diagnostics: diagnostics)
            guard !diagnostics.hasErrors else { break resolve }

            // Update the checkouts with dependency resolution result.
            try updateCheckouts(with: result)

            // Load the updated manifests.
            updatedManifests = loadDependencyManifests(root: graphRoot, diagnostics: diagnostics)

            // If autopin is enabled, reset and pin everything.
            if pinsStore.isAutoPinEnabled && !diagnostics.hasErrors {
                try self.pinAll(
                     pinsStore: pinsStore,
                     dependencyManifests: updatedManifests!,
                     reset: true)
            }
        } catch {
            diagnostics.emit(error)
        }

        return PackageGraphLoader().load(
            root: PackageGraphRoot(manifests: rootManifests, dependencies: root.dependencies),
            externalManifests: updatedManifests?.dependencies.map({ $0.manifest }) ?? [],
            diagnostics: diagnostics,
            fileSystem: fileSystem,
            shouldCreateMultipleTestProducts: createMultipleTestProducts
        )
    }

    /// Removes the clone and checkout of the provided specifier.
    func remove(specifier: RepositorySpecifier) throws {
        let managedDependencies = try self.managedDependencies.load()
        guard var dependency = managedDependencies[specifier] else {
            fatalError("This should never happen, trying to remove \(specifier) which isn't in workspace")
        }

        // If this dependency is based on a dependency, switch to that because
        // we don't want to touch the editable checkout here.
        //
        // FIXME: This will remove also the data about the editable dependency
        // and it will not be possible to "unedit" that dependency anymore.  To
        // do that we need to persist the value of isInEditableState and also
        // store the package names in managed dependencies, because it will not
        // be possible to lookup these dependencies using their manifests as we
        // won't have them anymore.
        // https://bugs.swift.org/browse/SR-3689
        if let basedOn = dependency.basedOn {
            dependency = basedOn
        }

        // Inform the delegate.
        delegate.removing(repository: dependency.repository.url)

        // Remove the repository from dependencies.
        managedDependencies[dependency.repository] = nil

        // Remove the checkout.
        let dependencyPath = checkoutsPath.appending(dependency.subpath)
        let checkedOutRepo = try repositoryManager.provider.openCheckout(at: dependencyPath)
        guard !checkedOutRepo.hasUncommitedChanges() else {
            throw WorkspaceDiagnostics.UncommitedChanges(repositoryPath: dependencyPath)
        }
        fileSystem.removeFileTree(dependencyPath)

        // Remove the clone.
        try repositoryManager.remove(repository: dependency.repository)

        // Save the state.
        try managedDependencies.saveState()
    }

    /// Loads and returns manifests at the given paths.
    public func loadRootManifests(
        packages: [AbsolutePath],
        diagnostics: DiagnosticsEngine
    ) -> [Manifest] {

        func load(_ package: AbsolutePath) throws -> Manifest {
            let toolsVersion = try toolsVersionLoader.load(at: package, fileSystem: fileSystem)
            guard currentToolsVersion >= toolsVersion else {
                throw WorkspaceDiagnostics.IncompatibleToolsVersion(
                    rootPackagePath: package,
                    requiredToolsVersion: toolsVersion,
                    currentToolsVersion: currentToolsVersion)
            }
            return try manifestLoader.load(
                package: package, baseURL: package.asString, manifestVersion: toolsVersion.manifestVersion)
        }

        var manifests = [Manifest]()
        for package in packages {
            do {
                try manifests.append(load(package))
            } catch {
                diagnostics.emit(error)
            }
        }
        return manifests
    }

    /// Loads the given manifest, if it is present in the managed dependencies.
    private func loadManifest(
        forDependencyURL url: String,
        managedDependencies: ManagedDependencies
    ) -> Manifest? {
        // Check if this dependency is available.
        guard let managedDependency = managedDependencies[url] else {
            return nil
        }

        let packagePath = path(for: managedDependency)

        // The version, if known.
        let version: Version?
        switch managedDependency.state {
        case .checkout(let checkoutState):
            version = checkoutState.version
        case .edited:
            version = nil
        }

        // Load the tools version for the package.
        let toolsVersion = try! toolsVersionLoader.load(
            at: packagePath, fileSystem: localFileSystem)

        // Load the manifest.
        //
        // FIXME: We need to emit errors if this fails (SR-4262).
        //
        // FIXME: We should have a cache for this.
        let manifest: Manifest = try! manifestLoader.load(
            package: packagePath,
            baseURL: managedDependency.repository.url,
            version: version,
            manifestVersion: toolsVersion.manifestVersion)
        return manifest
    }
}

/// A result which can be loaded.
///
/// It is useful for objects that holds a state on disk and needs to be
/// loaded frequently.
public final class LoadableResult<Value> {

    /// The constructor closure for the value.
    private let construct: () throws -> Value

    /// Create a loadable result.
    public init(_ construct: @escaping () throws -> Value) {
        self.construct = construct
    }

    /// Load and return the result.
    public func loadResult() -> Result<Value, AnyError> {
        return Result(anyError: {
            try self.construct()
        })
    }

    /// Load and return the value.
    public func load() throws -> Value {
        return try loadResult().dematerialize()
    }
}
