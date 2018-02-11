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

/// The delegate interface used by the workspace to report status information.
public protocol WorkspaceDelegate: class {

    /// The workspace is about to load the complete package graph.
    ///
    /// This delegate will only be called if we actually need to fetch and resolve dependencies. 
    ///
    /// - Parameters:
    ///   - currentGraph: The current package graph. This is most likely a partial package graph.
    ///   - dependencies: The current managed dependencies in the workspace.
    ///   - missingURLs: The top-level missing packages we need to fetch. This will never be empty.
    // FIXME: This is defunct.
    func packageGraphWillLoad(currentGraph: PackageGraph, dependencies: AnySequence<ManagedDependency>, missingURLs: Set<String>)

    /// The workspace has started fetching this repository.
    func fetchingWillBegin(repository: String)

    /// The workspace has finished fetching this repository.
    func fetchingDidFinish(repository: String, diagnostic: Diagnostic?)

    /// The workspace has started updating this repository.
    func repositoryWillUpdate(_ repository: String)

    /// The workspace has finished updating this repository.
    func repositoryDidUpdate(_ repository: String)

    /// The workspace has finished updating and all the dependencies are already up-to-date.
    func dependenciesUpToDate()

    /// The workspace has started cloning this repository.
    func cloning(repository: String)

    /// The workspace is checking out a repository.
    func checkingOut(repository: String, atReference reference: String, to path: AbsolutePath)

    /// The workspace is removing this repository because it is no longer needed.
    func removing(repository: String)

    /// Called when the managed dependencies are updated.
    func managedDependenciesDidUpdate(_ dependencies: AnySequence<ManagedDependency>)

    /// Called when the resolver is about to be run.
    func willResolveDependencies()
}

public extension WorkspaceDelegate {
    func checkingOut(repository: String, atReference: String, to path: AbsolutePath) {}
    func repositoryWillUpdate(_ repository: String) {}
    func repositoryDidUpdate(_ repository: String) {}
    func willResolveDependencies() {}
    func dependenciesUpToDate() {}
}

private class WorkspaceResolverDelegate: DependencyResolverDelegate {
    typealias Identifier = RepositoryPackageContainer.Identifier
}

private class WorkspaceRepositoryManagerDelegate: RepositoryManagerDelegate {
    unowned let workspaceDelegate: WorkspaceDelegate

    init(workspaceDelegate: WorkspaceDelegate) {
        self.workspaceDelegate = workspaceDelegate
    }

    func fetchingWillBegin(handle: RepositoryManager.RepositoryHandle) {
        workspaceDelegate.fetchingWillBegin(repository: handle.repository.url)
    }

    func fetchingDidFinish(handle: RepositoryManager.RepositoryHandle, error: Swift.Error?) {
        let diagnostic: Diagnostic? = error.flatMap({
            let engine = DiagnosticsEngine()
            engine.emit($0)
            return engine.diagnostics.first
        })
        workspaceDelegate.fetchingDidFinish(repository: handle.repository.url, diagnostic: diagnostic)
    }

    func handleWillUpdate(handle: RepositoryManager.RepositoryHandle) {
        workspaceDelegate.repositoryWillUpdate(handle.repository.url)
    }

    func handleDidUpdate(handle: RepositoryManager.RepositoryHandle) {
        workspaceDelegate.repositoryDidUpdate(handle.repository.url)
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
    struct DependencyManifests {
        /// The package graph root.
        let root: PackageGraphRoot

        /// The dependency manifests in the transitive closure of root manifest.
        let dependencies: [(manifest: Manifest, dependency: ManagedDependency)]

        let workspace: Workspace

        fileprivate init(root: PackageGraphRoot, dependencies: [(Manifest, ManagedDependency)], workspace: Workspace) {
            self.root = root
            self.dependencies = dependencies
            self.workspace = workspace
        }

        /// Find a package given its name.
        func lookup(package name: String) -> (manifest: Manifest, dependency: ManagedDependency)? {
            return dependencies.first(where: { $0.manifest.name == name })
        }

        /// Find a manifest given its name.
        func lookup(manifest name: String) -> Manifest? {
            return lookup(package: name)?.manifest
        }

        /// Computes the identities which are declared in the manifests but aren't present in dependencies.
        func missingPackageIdentities() -> Set<String> {
            let manifestsMap = Dictionary(items:
                root.manifests.map({ ($0.name.lowercased(), $0) }) +
                dependencies.map({ (PackageReference.computeIdentity(packageURL: $0.manifest.url), $0.manifest) }))

            let inputIdentities = root.manifests.map({ $0.name.lowercased() }) +
                root.dependencies.map({ PackageReference.computeIdentity(packageURL: $0.url) })

            var requiredIdentities = transitiveClosure(inputIdentities) { identity in
                guard let manifest = manifestsMap[identity] else { return [] }
                return manifest.package.dependencies.map({ PackageReference.computeIdentity(packageURL: $0.url) })
            }
            requiredIdentities.formUnion(inputIdentities)

            let availableIdentities = Set<String>(manifestsMap.keys)
            // We should never have loaded a manifest we don't need.
            assert(availableIdentities.isSubset(of: requiredIdentities))
            // These are the missing package identities.
            return requiredIdentities.subtracting(availableIdentities)
        }

        /// Returns constraints of the dependencies, including edited package constraints.
        fileprivate func dependencyConstraints() -> [RepositoryPackageConstraint] {
            var allConstraints = [RepositoryPackageConstraint]()

            for (externalManifest, managedDependency) in dependencies {

                switch managedDependency.state {
                case .edited:
                    // FIXME: We shouldn't need to construct a new package reference object here.
                    // We should get the correct one from managed dependency object.
                    let ref = PackageReference(
                        identity: managedDependency.packageRef.identity,
                        path: workspace.path(for: managedDependency).asString,
                        isLocal: true
                    )
                    // Add an unversioned constraint if the dependency is in edited state.
                    let constraint = RepositoryPackageConstraint(
                        container: ref,
                        requirement: .unversioned)
                    allConstraints.append(constraint)

                case .checkout: 
                    // For checkouts, add all the constraints in the manifest.
                    allConstraints += externalManifest.package.dependencyConstraints()
                }
            }
            return allConstraints
        }

        /// Returns a list of constraints for all 'edited' package.
        fileprivate func editedPackagesConstraints() -> [RepositoryPackageConstraint] {
            var constraints = [RepositoryPackageConstraint]()

            for (_, managedDependency) in dependencies {
                switch managedDependency.state {
                case .checkout: continue
                case .edited: break
                }
                // FIXME: We shouldn't need to construct a new package reference object here.
                // We should get the correct one from managed dependency object.
                let ref = PackageReference(
                    identity: managedDependency.packageRef.identity,
                    path: workspace.path(for: managedDependency).asString,
                    isLocal: true
                )
                let constraint = RepositoryPackageConstraint(
                    container: ref,
                    requirement: .unversioned)
                constraints.append(constraint)
            }
            return constraints
        }
    }

    /// The delegate interface.
    public let delegate: WorkspaceDelegate

    /// The path of the workspace data.
    public let dataPath: AbsolutePath

    /// The current state of managed dependencies.
    public let managedDependencies: ManagedDependencies

    /// The Pins store. The pins file will be created when first pin is added to pins store.
    public let pinsStore: LoadableResult<PinsStore>

    /// The path for working repository clones (checkouts).
    public let checkoutsPath: AbsolutePath

    /// The path where packages which are put in edit mode are checked out.
    public let editablesPath: AbsolutePath

    /// The file system on which the workspace will operate.
    fileprivate var fileSystem: FileSystem

    /// The manifest loader to use.
    fileprivate let manifestLoader: ManifestLoaderProtocol

    /// The tools version currently in use.
    fileprivate let currentToolsVersion: ToolsVersion

    /// The manifest loader to use.
    fileprivate let toolsVersionLoader: ToolsVersionLoaderProtocol

    /// The repository manager.
    fileprivate let repositoryManager: RepositoryManager

    /// The package container provider.
    fileprivate let containerProvider: RepositoryPackageContainerProvider

    /// Enable prefetching containers in resolver.
    fileprivate let isResolverPrefetchingEnabled: Bool

    /// Typealias for dependency resolver we use in the workspace.
    fileprivate typealias PackageDependencyResolver = DependencyResolver<RepositoryPackageContainerProvider, WorkspaceResolverDelegate>

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
        self.managedDependencies = ManagedDependencies(dataPath: dataPath, fileSystem: fileSystem)
    }
}

// MARK: - Public API

extension Workspace {

    /// Puts a dependency in edit mode creating a checkout in editables directory.
    ///
    /// - Parameters:
    ///     - packageName: The name of the package to edit.
    ///     - path: If provided, creates or uses the checkout at this location.
    ///     - revision: If provided, the revision at which the dependency
    ///       should be checked out to otherwise current revision.
    ///     - checkoutBranch: If provided, a new branch with this name will be
    ///       created from the revision provided.
    ///     - diagnostics: The diagnostics engine that reports errors, warnings
    ///       and notes.
    public func edit(
        packageName: String,
        path: AbsolutePath? = nil,
        revision: Revision? = nil,
        checkoutBranch: String? = nil,
        diagnostics: DiagnosticsEngine
    ) {
        do {
            try _edit(
                packageName: packageName,
                path: path,
                revision: revision,
                checkoutBranch: checkoutBranch,
                diagnostics: diagnostics)
        } catch {
            diagnostics.emit(error)
        }
    }

    /// Ends the edit mode of an edited dependency.
    ///
    /// This will re-resolve the dependencies after ending edit as the original
    /// checkout may be outdated.
    ///
    /// - Parameters:
    ///     - packageName: The name of the package to edit.
    ///     - forceRemove: If true, the dependency will be unedited even if has unpushed
    ///           or uncommited changes. Otherwise will throw respective errors.
    ///     - root: The workspace root. This is used to resolve the dependencies post unediting.
    ///     - diagnostics: The diagnostics engine that reports errors, warnings
    ///           and notes.
    public func unedit(
        packageName: String,
        forceRemove: Bool,
        root: PackageGraphRootInput,
        diagnostics: DiagnosticsEngine
    ) throws {
        let dependency = try managedDependencies.dependency(forNameOrIdentity: packageName)
        try unedit(dependency: dependency, forceRemove: forceRemove, root: root, diagnostics: diagnostics)
    }

    /// Resolve a package at the given state.
    ///
    /// Only one of version, branch and revision will be used and in the same
    /// order. If none of these is provided, the dependency will be pinned at
    /// the current checkout state.
    ///
    /// - Parameters:
    ///   - packageName: The name of the package which is being resolved.
    ///   - root: The workspace's root input.
    ///   - version: The version to pin at.
    ///   - branch: The branch to pin at.
    ///   - revision: The revision to pin at.
    ///   - diagnostics: The diagnostics engine that reports errors, warnings
    ///     and notes.
    public func resolve(
        packageName: String,
        root: PackageGraphRootInput,
        version: Version? = nil,
        branch: String? = nil,
        revision: String? = nil,
        diagnostics: DiagnosticsEngine
    ) {
        // Look up the dependency and check if we can pin it.
        guard let dependency = diagnostics.wrap({ try managedDependencies.dependency(forNameOrIdentity: packageName) }) else {
            return
        }
        guard case .checkout(let currentState) = dependency.state else {
            let error = WorkspaceDiagnostics.DependencyAlreadyInEditMode(dependencyName: packageName)
            return diagnostics.emit(error)
        }

        // Compute the custom or extra constraint we need to impose.
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
        let constraint = RepositoryPackageConstraint(
                container: dependency.packageRef, requirement: requirement)

        // Run the resolution.
        _resolve(root: root, extraConstraints: [constraint], diagnostics: diagnostics)
    }

    /// Cleans the build artefacts from workspace data.
    ///
    /// - Parameters:
    ///     - diagnostics: The diagnostics engine that reports errors, warnings
    ///       and notes.
    public func clean(with diagnostics: DiagnosticsEngine) {

        // These are the things we don't want to remove while cleaning.
        let protectedAssets = Set<String>([
            repositoryManager.path,
            checkoutsPath,
            managedDependencies.statePath,
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
            try? fileSystem.removeFileTree(dataPath.appending(RelativePath(name)))
        }
    }

    /// Resets the entire workspace by removing the data directory.
    ///
    /// - Parameters:
    ///     - diagnostics: The diagnostics engine that reports errors, warnings
    ///       and notes.
    public func reset(with diagnostics: DiagnosticsEngine) {
        let removed = diagnostics.wrap({
            try fileSystem.chmod(.userWritable, path: checkoutsPath, options: [.recursive, .onlyFiles])
            // Reset manaked dependencies.
            try managedDependencies.reset()
        })

        guard removed else { return }

        repositoryManager.reset()
        try? fileSystem.removeFileTree(dataPath)
    }

    /// Updates the current dependencies.
    ///
    /// - Parameters:
    ///     - diagnostics: The diagnostics engine that reports errors, warnings
    ///       and notes.
    public func updateDependencies(
        root: PackageGraphRootInput,
        diagnostics: DiagnosticsEngine
    ) {
        // Create cache directories.
        createCacheDirectories(with: diagnostics)

        // Load the root manifests and currently checked out manifests.
        let rootManifests = loadRootManifests(packages: root.packages, diagnostics: diagnostics) 

        // Load the current manifests.
        let graphRoot = PackageGraphRoot(input: root, manifests: rootManifests)
        let currentManifests = loadDependencyManifests(root: graphRoot, diagnostics: diagnostics)

        // Abort if we're unable to load the pinsStore or have any diagnostics.
        guard let pinsStore = diagnostics.wrap({ try self.pinsStore.load() }) else {
            return
        }

        // Ensure we don't have any error at this point.
        guard !diagnostics.hasErrors else { return }

        // Add unversioned constraints for edited packages.
        var updateConstraints = currentManifests.editedPackagesConstraints()

        // Create constraints based on root manifest and pins for the update resolution.
        updateConstraints += graphRoot.constraints

        // Resolve the dependencies.
        let updateResults = resolveDependencies(dependencies: updateConstraints, diagnostics: diagnostics)
        guard !diagnostics.hasErrors else { return }

		// Update the checkouts based on new dependency resolution.
        updateCheckouts(with: updateResults, updateBranches: true, diagnostics: diagnostics)
        guard !diagnostics.hasErrors else { return }

        // Update the pins store.
        return pinAll(
            pinsStore: pinsStore,
            diagnostics: diagnostics)
    }

    /// Fetch and load the complete package at the given path.
    ///
    /// This will implicitly cause any dependencies not yet present in the
    /// working checkouts to be resolved, cloned, and checked out.
    ///
    /// - Returns: The loaded package graph.
    @discardableResult
    public func loadPackageGraph(
        root: PackageGraphRootInput,
        createMultipleTestProducts: Bool = false,
        diagnostics: DiagnosticsEngine
    ) -> PackageGraph {

        // Perform dependency resolution, if required.
        let manifests = self._resolve(root: root, diagnostics: diagnostics)

        // Load the graph.
        return PackageGraphLoader().load(
            root: manifests.root,
            externalManifests: manifests.dependencies.map({ $0.manifest }),
            diagnostics: diagnostics,
            fileSystem: fileSystem,
            shouldCreateMultipleTestProducts: createMultipleTestProducts
        )
    }

    /// Perform dependency resolution if needed.
    ///
    /// This method will perform dependency resolution based on the root
    /// manifests and pins file.  Pins are respected as long as they are
    /// satisfied by the root manifest closure requirements.  Any outdated
    /// checkout will be restored according to its pin.
    public func resolve(
        root: PackageGraphRootInput,
        diagnostics: DiagnosticsEngine
    ) {
        _resolve(root: root, diagnostics: diagnostics)
    }

	/// Load the package graph data.
	///
	/// This method returns the package graph, and the mapping between each
	/// package and its corresponding managed dependency.
	///
	/// The current managed dependencies will be reported via the delegate
	/// before and after loading the package graph.
    public func loadGraphData(
        root: PackageGraphRootInput,
        createMultipleTestProducts: Bool = false,
        diagnostics: DiagnosticsEngine
    ) -> (graph: PackageGraph, dependencyMap: [ResolvedPackage: ManagedDependency]) {

        // Load the package graph.
        let graph = loadPackageGraph(
            root: root,
            createMultipleTestProducts: createMultipleTestProducts,
            diagnostics: diagnostics)

        // Report the updated managed dependencies.
        delegate.managedDependenciesDidUpdate(managedDependencies.values)

        // Create the dependency map by associating each resolved package with its corresponding managed dependency.
        let managedDependenciesByIdentity = Dictionary(items: managedDependencies.values.map({ ($0.packageRef.identity, $0) }))
        let dependencyMap = graph.packages.compactMap({ package -> (ResolvedPackage, ManagedDependency)? in
            // FIXME: We should use package name directly once this radar is fixed:
            // <rdar://problem/33693433> Ensure that identity and package name
            // are the same once we have an API to specify identity in the
            // manifest file
            let identity = PackageReference.computeIdentity(packageURL: package.manifest.url)
            guard let dependency = managedDependenciesByIdentity[identity] else { return nil }
            return (package, dependency)
        })

        return (graph, Dictionary(items: dependencyMap))
    }

    /// Loads and returns manifests at the given paths.
    public func loadRootManifests(
        packages: [AbsolutePath],
        diagnostics: DiagnosticsEngine
    ) -> [Manifest] {
        return packages.compactMap({ package -> Manifest? in
			loadManifest(packagePath: package, url: package.asString, diagnostics: diagnostics)
        })
    }
}

// MARK: - Editing Functions

extension Workspace {

    /// Edit implementation.
    fileprivate func _edit(
        packageName: String,
        path: AbsolutePath? = nil,
        revision: Revision? = nil,
        checkoutBranch: String? = nil,
        diagnostics: DiagnosticsEngine
    ) throws {
        // Look up the dependency and check if we can edit it.
        let dependency = try managedDependencies.dependency(forNameOrIdentity: packageName)

        guard case .checkout(let checkoutState) = dependency.state else {
            throw WorkspaceDiagnostics.DependencyAlreadyInEditMode(dependencyName: packageName)
        }

        // If a path is provided then we use it as destination. If not, we
        // use the folder with packageName inside editablesPath.
        let destination = path ?? editablesPath.appending(component: packageName)

        // If there is something present at the destination, we confirm it has
        // a valid manifest with name same as the package we are trying to edit.
        if fileSystem.exists(destination) {
            let manifest = loadManifest(
                packagePath: destination, url: dependency.packageRef.repository.url, diagnostics: diagnostics)

            guard manifest?.name == packageName else {
                let error = WorkspaceDiagnostics.MismatchingDestinationPackage(
                    editPath: destination,
                    expectedPackage: packageName,
                    destinationPackage: manifest?.name)
                return diagnostics.emit(error)
            }

            // Emit warnings for branch and revision, if they're present.
            if let checkoutBranch = checkoutBranch {
                diagnostics.emit(WorkspaceDiagnostics.EditBranchNotCheckedOut(
                    packageName: packageName,
                    branchName: checkoutBranch))
            }
            if let revision = revision {
                diagnostics.emit(WorkspaceDiagnostics.EditRevisionNotUsed(
                    packageName: packageName,
                    revisionIdentifier: revision.identifier))
            }
        } else {
            // Otherwise, create a checkout at the destination from our repository store.
            //
            // Get handle to the repository.
            let handle = try await {
                repositoryManager.lookup(repository: dependency.packageRef.repository, skipUpdate: true, completion: $0)
            }
            let repo = try handle.open()

            // Do preliminary checks on branch and revision, if provided.
            if let branch = checkoutBranch, repo.exists(revision: Revision(identifier: branch)) {
                throw WorkspaceDiagnostics.BranchAlreadyExists(branch: branch)
            }
            if let revision = revision, !repo.exists(revision: revision) {
                throw WorkspaceDiagnostics.RevisionDoesNotExist(revision: revision.identifier)
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
            if !(fileSystem is InMemoryFileSystem) {
                try createSymlink(
                    editablesPath.appending(component: packageName),
                    pointingAt: path,
                    relative: false)
            }
        }

        // Remove the existing checkout.
        do {
            let oldCheckoutPath = checkoutsPath.appending(dependency.subpath)
            try fileSystem.chmod(.userWritable, path: oldCheckoutPath, options: [.recursive, .onlyFiles])
            try fileSystem.removeFileTree(oldCheckoutPath)
        }

        // Save the new state.
        let identity = dependency.packageRef.identity
        managedDependencies[forIdentity: identity] = dependency.editedDependency(
            subpath: RelativePath(packageName), unmanagedPath: path)
        try managedDependencies.saveState()
    }

    /// Unedit a managed dependency. See public API unedit(packageName:forceRemove:).
    fileprivate func unedit(
        dependency: ManagedDependency,
        forceRemove: Bool,
        root: PackageGraphRootInput? = nil,
        diagnostics: DiagnosticsEngine
    ) throws {

        // Compute if we need to force remove.
        var forceRemove = forceRemove

        switch dependency.state {
        // If the dependency isn't in edit mode, we can't unedit it.
        case .checkout:
            throw WorkspaceDiagnostics.DependencyNotInEditMode(dependencyName: dependency.packageRef.identity)

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
            guard !workingRepo.hasUncommittedChanges() else {
                throw WorkspaceDiagnostics.UncommitedChanges(repositoryPath: path)
            }
            guard try !workingRepo.hasUnpushedCommits() else {
                throw WorkspaceDiagnostics.UnpushedChanges(repositoryPath: path)
            }
        }
        // Remove the editable checkout from disk.
        if fileSystem.exists(path) {
            try fileSystem.removeFileTree(path)
        }
        // If this was the last editable dependency, remove the editables directory too.
        if fileSystem.exists(editablesPath), try fileSystem.getDirectoryContents(editablesPath).isEmpty {
            try fileSystem.removeFileTree(editablesPath)
        }

        if let checkoutState = dependency.basedOn?.checkoutState {
            // Restore the original checkout.
            //
            // The clone method will automatically update the managed dependency state.
            _ = try clone(package: dependency.packageRef, at: checkoutState)
        } else {
            // The original dependency was removed, update the managed dependency state.
            managedDependencies[forIdentity: dependency.packageRef.identity] = nil
            try managedDependencies.saveState()
        }

        // Resolve the dependencies if workspace root is provided. We do this to
        // ensure the unedited version of this dependency is resolved properly.
        if let root = root {
            resolve(root: root, diagnostics: diagnostics)
        }
    }

}

// MARK: - Pinning Functions

extension Workspace {

    /// Pins all of the current managed dependencies at their checkout state.
    fileprivate func pinAll(
        pinsStore: PinsStore,
        diagnostics: DiagnosticsEngine
    ) {
        // Reset the pinsStore and start pinning each dependency.
		pinsStore.unpinAll()
        for dependency in managedDependencies.values {
            pinsStore.pin(dependency)
        }
        diagnostics.wrap({ try pinsStore.saveState() })
    }
}

// MARK: - Utility Functions

extension Workspace {

    /// Create the cache directories.
    fileprivate func createCacheDirectories(with diagnostics: DiagnosticsEngine) {
        do {
            try fileSystem.createDirectory(repositoryManager.path, recursive: true)
            try fileSystem.createDirectory(checkoutsPath, recursive: true)
        } catch {
            diagnostics.emit(error)
        }
    }

    /// Returns the location of the dependency.
    ///
    /// Checkout dependencies will return the subpath inside `checkoutsPath` and
    /// edited dependencies will either return a subpath inside `editablesPath` or
    /// a custom path.
    public func path(for dependency: ManagedDependency) -> AbsolutePath {
        switch dependency.state {
        case .checkout:
            return checkoutsPath.appending(dependency.subpath)
        case .edited(let path):
            return path ?? editablesPath.appending(dependency.subpath)
        }
    }

    /// Returns manifest interpreter flags for a package.
    public func interpreterFlags(for packagePath: AbsolutePath) -> [String] {
        // We ignore all failures here and return empty array.
        guard let manifestLoader = self.manifestLoader as? ManifestLoader,
              let toolsVersion = try? toolsVersionLoader.load(at: packagePath, fileSystem: fileSystem),
              currentToolsVersion >= toolsVersion else {
            return []
        }
        return manifestLoader.interpreterFlags(for: toolsVersion.manifestVersion)
    }

    /// Load the manifests for the current dependency tree.
    ///
    /// This will load the manifests for the root package as well as all the
    /// current dependencies from the working checkouts.
    // @testable internal
    func loadDependencyManifests(
        root: PackageGraphRoot,
        diagnostics: DiagnosticsEngine
    ) -> DependencyManifests {

        // Remove any managed dependency which has become a root.
        for dependency in managedDependencies.values {
            if root.packageRefs.contains(dependency.packageRef) {
                diagnostics.wrap {
                    try self.remove(package: dependency.packageRef)
                }
            }
        }

        // Try to load current managed dependencies, or emit and return.
        fixManagedDependencies(with: diagnostics)
        guard !diagnostics.hasErrors else {
            return DependencyManifests(root: root, dependencies: [], workspace: self)
        }

        let rootDependencyManifests = root.dependencies.compactMap({
            return loadManifest(for: $0.createPackageRef().identity, diagnostics: diagnostics)
        })
        let inputManifests = root.manifests + rootDependencyManifests

        // Compute the transitive closure of available dependencies.
        let dependencies = transitiveClosure(inputManifests.map({ KeyedPair($0, key: $0.name) })) { node in
            return node.item.package.dependencies.compactMap({ dependency in
                let manifest = loadManifest(for: dependency.createPackageRef().identity, diagnostics: diagnostics)
                return manifest.flatMap({ KeyedPair($0, key: $0.name) })
            })
        }
        // It is possible that some root dependency is also present as a regular dependency, so we
        // form a unique set of all dependency manifests.
        let allManifests = Set(rootDependencyManifests.map({ KeyedPair($0, key: $0.name) }) + dependencies).map({ $0.item })
        let deps: [(Manifest, ManagedDependency)] = allManifests.map({
            // FIXME: We should use package name directly once this radar is fixed:
            // <rdar://problem/33693433> Ensure that identity and package name
            // are the same once we have an API to specify identity in the
            // manifest file
            let identity = PackageReference.computeIdentity(packageURL: $0.url)
            return ($0, managedDependencies[forIdentity: identity]!) 
        })
        return DependencyManifests(root: root, dependencies: deps, workspace: self)
    }


    /// Loads the given manifest, if it is present in the managed dependencies.
    fileprivate func loadManifest(for package: String, diagnostics: DiagnosticsEngine) -> Manifest? {
        // Check if this dependency is available.
        guard let managedDependency = managedDependencies[forIdentity: package] else {
            return nil
        }

        // The version, if known.
        let version: Version?
        switch managedDependency.state {
        case .checkout(let checkoutState):
            version = checkoutState.version
        case .edited:
            version = nil
        }

        // Get the path of the package.
        let packagePath = path(for: managedDependency)

        // Load and return the manifest.
        return loadManifest(
            packagePath: packagePath,
            url: managedDependency.packageRef.repository.url,
            version: version,
            diagnostics: diagnostics
        )
    }

    /// Load the manifest at a given path.
    ///
    /// This is just a helper wrapper to the manifest loader.
    fileprivate func loadManifest(
        packagePath: AbsolutePath,
        url: String,
        version: Version? = nil,
        diagnostics: DiagnosticsEngine
    ) -> Manifest? {
        return diagnostics.wrap(with: PackageLocation.Local(packagePath: packagePath), {
            // Load the tools version for the package.
            let toolsVersion = try toolsVersionLoader.load(
                at: packagePath, fileSystem: fileSystem)

            // Ensure that the tools version is compatible.
            guard currentToolsVersion >= toolsVersion else {
                throw WorkspaceDiagnostics.IncompatibleToolsVersion(
                    rootPackagePath: packagePath,
                    requiredToolsVersion: toolsVersion,
                    currentToolsVersion: currentToolsVersion)
            }

            // Load the manifest.
            // FIXME: We should have a cache for this.
            return try manifestLoader.load(
                package: packagePath,
                baseURL: url,
                version: version,
                manifestVersion: toolsVersion.manifestVersion
            )
        })
    }
}

// MARK: - Dependency Management

extension Workspace {

    /// Implementation of resolve(root:diagnostics:).
    ///
    /// The extra constraints will be added to the main requirements.
    /// It is useful in situations where a requirement is being
    /// imposed outside of manifest and pins file. E.g., when using a command
    /// like `$ swift package resolve foo --version 1.0.0`.
    @discardableResult
    fileprivate func _resolve(
        root: PackageGraphRootInput,
        extraConstraints: [RepositoryPackageConstraint] = [],
        diagnostics: DiagnosticsEngine
    ) -> DependencyManifests {

        // Ensure the cache path exists and validate that edited dependencies.
        createCacheDirectories(with: diagnostics)

        // Load the root manifests and currently checked out manifests.
        let rootManifests = loadRootManifests(packages: root.packages, diagnostics: diagnostics) 

        // Load the current manifests.
        let graphRoot = PackageGraphRoot(input: root, manifests: rootManifests)
        let currentManifests = loadDependencyManifests(root: graphRoot, diagnostics: diagnostics)

        // Abort if pinsStore is unloadable or if diagnostics has errors.
        guard let pinsStore = diagnostics.wrap({ try pinsStore.load() }), !diagnostics.hasErrors else {
            return currentManifests
        }

        // Compute the missing package identities.
        let missingPackageIdentities = currentManifests.missingPackageIdentities()

        // The pins to use in case we need to run the resolution.
        var validPins = pinsStore.createConstraints()

        // Compute if we need to run the resolver. We always run the resolver if
        // there are extra constraints.
        if missingPackageIdentities.isEmpty {
            // Use root constraints, dependency manifest constraints and extra
            // constraints to compute if a new resolution is required.
            let dependencies =
                graphRoot.constraints +
                // Include constraints from the manifests in the graph root.
                graphRoot.manifests.flatMap({ $0.package.dependencyConstraints() }) +
                currentManifests.dependencyConstraints() +
                extraConstraints

            let result = isResolutionRequired(dependencies: dependencies, pinsStore: pinsStore)

            // If we don't need resolution and there are no extra constraints,
            // just validate pinsStore and return.
            if !result.resolve && extraConstraints.isEmpty {
                validatePinsStore(with: diagnostics)
                return currentManifests
            }

            validPins = result.validPins
        }

        // Inform delegate that we will resolve dependencies now.
        delegate.willResolveDependencies()

        // Create the constraints.
        var constraints = [RepositoryPackageConstraint]()
        constraints += currentManifests.editedPackagesConstraints()
        constraints += graphRoot.constraints + extraConstraints

        // Perform dependency resolution.
        let resolverDiagnostics = DiagnosticsEngine()
        let resolver = createResolver()
        var result = resolveDependencies(
            resolver: resolver, dependencies: constraints, pins: validPins, diagnostics: resolverDiagnostics)

        // If we fail, we just try again without any pins because the pins might
        // be completely incompatible.
        //
        // FIXME: We should only do this if resolver emits "unresolvable" error.
        if resolverDiagnostics.hasErrors {
            // If there are no pins, merge diagnostics and return now.
            if validPins.isEmpty {
                diagnostics.merge(resolverDiagnostics)
                return currentManifests
            }

            // Run using the same resolver so we don't re-add the containers, we already have.
            result = resolveDependencies(resolver: resolver, dependencies: constraints, diagnostics: diagnostics)
            guard !diagnostics.hasErrors else {
                return currentManifests
            }
        }

        // Update the checkouts with dependency resolution result.
        updateCheckouts(with: result, diagnostics: diagnostics)
        guard !diagnostics.hasErrors else {
            return currentManifests
        }

        // Update the pinsStore.
        self.pinAll(pinsStore: pinsStore, diagnostics: diagnostics)

        return loadDependencyManifests(root: graphRoot, diagnostics: diagnostics)
    }

    /// Computes if dependency resolution is required based on input constraints and pins.
    ///
    /// A resolution is required if:
    ///
    /// * The input dependencies are not mergable. E.g.: root manifest have
    ///   unmergable constraints.
    ///
    /// * Pins are not mergable into the input dependencies. E.g.: if root
    ///   manifest was updated with constraints such that the current pin does not
    ///   statisfy it.
    ///
    /// * If any of the managed dependency is out of sync with its pin. E.g.:
    ///   pulling from remote updates the pin file..
    ///
    /// - Returns: A tuple with two elements.
    ///       resolve: If resolution is required.
    ///       validPins: The pins which are still valid.
    // @testable internal
    func isResolutionRequired(
        dependencies: [RepositoryPackageConstraint],
        pinsStore: PinsStore
    ) -> (resolve: Bool, validPins: [RepositoryPackageConstraint]) {

        // Create pinned constraints.
        let pinConstraints = pinsStore.createConstraints()

        // Create a constraint set to check constraints are mergable.
        var constraintSet = PackageContainerConstraintSet<RepositoryPackageContainer>()

        // The input dependencies should be mergable, otherwise we have bigger problems.
        for constraint in dependencies {
            guard let mergedSet = constraintSet.merging(constraint) else {
                return (true, pinConstraints)
            }
            constraintSet = mergedSet
        }

        // Compute the pins which are valid w.r.t dependencies.
        let validPins: [RepositoryPackageConstraint]
        validPins = pinConstraints.compactMap { pin in
            if let mergedSet = constraintSet.merging(pin) {
                constraintSet = mergedSet
                return pin
            }
            return nil
        }

        // If there are pins which are not valid anymore, we need to resolve.
        if pinConstraints.count != validPins.count {
            return (true, validPins)
        }

        // Otherwise, just check if all checkouts and pins are in sync.
        for pin in pinsStore.pins {
            let dependency = managedDependencies[forIdentity: pin.packageRef.identity]

            switch dependency?.state {
            case let .checkout(dependencyState)?:
                // If this pin is not same as the checkout state, we need to re-resolve.
                if pin.state != dependencyState {
                    return (true, validPins)
                }
            case .edited?:
                // Ignore edited dependencies.
                continue
            case nil:
                // We don't have a checkout.
                return (true, validPins)
            }
        }

        return (false, [])
    }

    /// Validates that each checked out managed dependency has an entry in pinsStore.
    private func validatePinsStore(with diagnostics: DiagnosticsEngine) {
        guard let pinsStore = diagnostics.wrap({ try pinsStore.load() }) else {
            return
        }

        for dependency in managedDependencies.values {
            switch dependency.state {
            case .checkout: break
            case .edited: continue
            }
            // If we find any checkout that is not in pins store, invoke pin all and return.
            if pinsStore.pinsMap[dependency.packageRef.identity] == nil {
                return self.pinAll(pinsStore: pinsStore, diagnostics: diagnostics)
            }
        }
    }

    /// This enum represents state of an external package.
    fileprivate enum PackageStateChange: Equatable {
        /// The requirement imposed by the the state.
        enum Requirement: Equatable {
            /// A version requirement.
            case version(Version)

            /// A revision requirement.
            case revision(Revision, branch: String?)
            
            static func == (lhs: Requirement, rhs: Requirement) -> Bool {
                switch (lhs, rhs) {
                case (.version(let a), .version(let b)): return a == b
                case (.revision(let a), .revision(let b)): return (a.0 == b.0) && (a.1 == b.1)
                case (.version(_), _): return false
                case (.revision(_), _): return false
                }
            }
        }

        /// The package is added.
        case added(Requirement)

        /// The package is removed.
        case removed

        /// The package is unchanged.
        case unchanged

        /// The package is updated.
        case updated(Requirement)
        
        static func == (lhs: PackageStateChange, rhs: PackageStateChange) -> Bool {
            switch (lhs, rhs) {
            case (.added(let a), .added(let b)): return a == b
            case (.removed, .removed): return true
            case (.unchanged, .unchanged): return true
            case (.updated(let a), .updated(let b)): return a == b
            case (.added, _): return false
            case (.removed, _): return false
            case (.unchanged, _): return false
            case (.updated, _): return false
            }
        }
    }

    /// Computes states of the packages based on last stored state.
    fileprivate func computePackageStateChanges(
        resolvedDependencies: [(PackageReference, BoundVersion)],
        updateBranches: Bool
    ) throws -> [PackageReference: PackageStateChange] {
        // Load pins store and managed dependendencies.
        let pinsStore = try self.pinsStore.load()

        var packageStateChanges = [PackageReference: PackageStateChange]()
        // Set the states from resolved dependencies results.
        for (packageRef, binding) in resolvedDependencies {
            switch binding {
            case .excluded:
                fatalError("Unexpected excluded binding")

            case .unversioned:
                packageStateChanges[packageRef] = .unchanged

            case .revision(let identifier):
                // Get the latest revision from the container.
                let container = try await {
                    containerProvider.getContainer(for: packageRef, skipUpdate: true, completion: $0) 
                } as! RepositoryPackageContainer 
                var revision = try container.getRevision(forIdentifier: identifier)
                let branch = identifier == revision.identifier ? nil : identifier

                // If we have a branch and we shouldn't be updating the
                // branches, use the revision from pin instead (if present).
                if branch != nil {
                    if let pin = pinsStore.pins.first(where: { $0.packageRef == packageRef }),
                        !updateBranches,
                        pin.state.branch == branch {
                        revision = pin.state.revision
                    }
                }

                // First check if we have this dependency.
                if let currentDependency = managedDependencies[forIdentity: packageRef.identity] {
                    // If current state and new state are equal, we don't need
                    // to do anything.
                    let newState = CheckoutState(revision: revision, branch: branch)
                    if case .checkout(let checkoutState) = currentDependency.state, checkoutState == newState {
                        packageStateChanges[packageRef] = .unchanged
                    } else {
                        // Otherwise, we need to update this dependency to this revision.
                        packageStateChanges[packageRef] = .updated(.revision(revision, branch: branch))
                    }
                } else {
                    packageStateChanges[packageRef] = .added(.revision(revision, branch: branch))
                }

            case .version(let version):
                if let currentDependency = managedDependencies[forIdentity: packageRef.identity] {
                    if case .checkout(let checkoutState) = currentDependency.state, checkoutState.version == version {
                        packageStateChanges[packageRef] = .unchanged
                    } else {
                        packageStateChanges[packageRef] = .updated(.version(version))
                    }
                } else {
                    packageStateChanges[packageRef] = .added(.version(version))
                }
            }
        }
        // Set the state of any old package that might have been removed.
        let dependencies = managedDependencies.values
        for packageRef in dependencies.lazy.map({ $0.packageRef }) where packageStateChanges[packageRef] == nil {
            packageStateChanges[packageRef] = .removed
        }
        return packageStateChanges
    }

    /// Creates resolver for the workspace.
    fileprivate func createResolver() -> PackageDependencyResolver {
        let resolverDelegate = WorkspaceResolverDelegate()
        return DependencyResolver(containerProvider, resolverDelegate,
            isPrefetchingEnabled: isResolverPrefetchingEnabled)
    }

    /// Runs the dependency resolver based on constraints provided and returns the results.
    fileprivate func resolveDependencies(
        resolver: PackageDependencyResolver? = nil,
        dependencies: [RepositoryPackageConstraint],
        pins: [RepositoryPackageConstraint] = [],
        diagnostics: DiagnosticsEngine
    ) -> [(container: WorkspaceResolverDelegate.Identifier, binding: BoundVersion)] {
        let resolver = resolver ?? createResolver()

        let result = resolver.resolve(dependencies: dependencies, pins: pins)

        // Take an action based on the result.
        switch result {
        case .success(let bindings):
            return bindings

        case .unsatisfiable(let dependencies, let pins):
            diagnostics.emit(data: ResolverDiagnostics.Unsatisfiable(dependencies: dependencies, pins: pins))
            return []

        case .error(let error):
            switch error {
            // Emit proper error if we were not able to parse some manifest during dependency resolution.
            case let error as RepositoryPackageContainer.GetDependenciesErrorWrapper:
                let location = PackageLocation.Remote(url: error.containerIdentifier, reference: error.reference)
                diagnostics.emit(error.underlyingError, location: location)

            default:
                diagnostics.emit(error)
            }

            return []
        }
    }

    /// Validates that all the edited dependencies are still present in the file system.
    /// If some checkout dependency is reomved form the file system, clone it again.
    /// If some edited dependency is removed from the file system, mark it as unedited and
    /// fallback on the original checkout.
    fileprivate func fixManagedDependencies(with diagnostics: DiagnosticsEngine) {
        for dependency in managedDependencies.values {
            diagnostics.wrap {

                // If the dependency is present, we're done.
                let dependencyPath = path(for: dependency)
                guard !fileSystem.isDirectory(dependencyPath) else { return }

                switch dependency.state {
                case .checkout(let checkoutState):
                    // If some checkout dependency has been removed, clone it again.
                    _ = try clone(package: dependency.packageRef, at: checkoutState)
                    diagnostics.emit(WorkspaceDiagnostics.CheckedOutDependencyMissing(packageName: dependency.packageRef.identity))

                case .edited:
                    // If some edited dependency has been removed, mark it as unedited.
                    //
                    // Note: We don't resolve the dependencies when unediting
                    // here because we expect this method to be called as part
                    // of some other resolve operation (i.e. resolve, update, etc).
                    try unedit(dependency: dependency, forceRemove: true, diagnostics: diagnostics)

                    diagnostics.emit(WorkspaceDiagnostics.EditedDependencyMissing(packageName: dependency.packageRef.identity))
                }
            }
        }
    }
}

// MARK: - Repository Management

extension Workspace {

    /// Updates the current working checkouts i.e. clone or remove based on the
    /// provided dependency resolution result.
    ///
    /// - Parameters:
    ///   - updateResults: The updated results from dependency resolution.
    ///   - diagnostics: The diagnostics engine that reports errors, warnings
    ///     and notes.
    ///   - updateBranches: If the branches should be updated in case they're pinned.
    fileprivate func updateCheckouts(
        with updateResults: [(PackageReference, BoundVersion)],
        updateBranches: Bool = false,
        diagnostics: DiagnosticsEngine
    ) {
        // Get the update package states from resolved results.
        guard let packageStateChanges = diagnostics.wrap({
            try computePackageStateChanges(resolvedDependencies: updateResults, updateBranches: updateBranches)
        }) else {
            return
        }

        // Update or clone new packages.
        for (packageRef, state) in packageStateChanges {
            diagnostics.wrap {
                switch state {
                case .added(let requirement):
                    _ = try clone(package: packageRef, requirement: requirement)
                case .updated(let requirement):
                    _ = try clone(package: packageRef, requirement: requirement)
                case .removed:
                    try remove(package: packageRef)
                case .unchanged: break
                }
            }
        }
        
        // Inform the delegate if nothing was updated.
        if packageStateChanges.filter({ $0.value == .unchanged }).count == packageStateChanges.count {
            delegate.dependenciesUpToDate()
        }
    }

    /// Fetch a given `repository` and create a local checkout for it.
    ///
    /// This will first clone the repository into the canonical repositories
    /// location, if necessary, and then check it out from there.
    ///
    /// - Returns: The path of the local repository.
    /// - Throws: If the operation could not be satisfied.
    private func fetch(package: PackageReference) throws -> AbsolutePath {
        // If we already have it, fetch to update the repo from its remote.
        if let dependency = managedDependencies[forIdentity: package.identity] {
            let path = checkoutsPath.appending(dependency.subpath)

            // Make sure the directory is not missing (we will have to clone again
            // if not).
            fetch: if fileSystem.isDirectory(path) {
                // Fetch the checkout in case there are updates available.
                let workingRepo = try repositoryManager.provider.openCheckout(at: path)

                // Ensure that the alternative object store is still valid.
                //
                // This can become invalid if the build directory is moved.
                guard workingRepo.isAlternateObjectStoreValid() else {
                    break fetch
                }

                // The fetch operation may update contents of the checkout, so
                // we need do mutable-immutable dance.
                try fileSystem.chmod(.userWritable, path: path, options: [.recursive, .onlyFiles])
                try workingRepo.fetch()
                try? fileSystem.chmod(.userUnWritable, path: path, options: [.recursive, .onlyFiles])

                return path
            }
        }

        // If not, we need to get the repository from the checkouts.
        let handle = try await {
            repositoryManager.lookup(repository: package.repository, skipUpdate: true, completion: $0)
        }

        // Clone the repository into the checkouts.
        let path = checkoutsPath.appending(component: package.repository.fileSystemIdentifier)

        try fileSystem.chmod(.userWritable, path: path, options: [.recursive, .onlyFiles])
        try fileSystem.removeFileTree(path)

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
    ///   - package: The package to clone.
    ///   - checkoutState: The state to check out.
    /// - Returns: The path of the local repository.
    /// - Throws: If the operation could not be satisfied.
    // FIXME: @testable internal
    func clone(
        package: PackageReference,
        at checkoutState: CheckoutState
    ) throws -> AbsolutePath {
        // Get the repository.
        let path = try fetch(package: package)

        // Check out the given revision.
        let workingRepo = try repositoryManager.provider.openCheckout(at: path)
        // Inform the delegate.
        delegate.checkingOut(repository: package.repository.url, atReference: checkoutState.description, to: path)

        // Do mutable-immutable dance because checkout operation modifies the disk state.
        try fileSystem.chmod(.userWritable, path: path, options: [.recursive, .onlyFiles])
        try workingRepo.checkout(revision: checkoutState.revision)
        try? fileSystem.chmod(.userUnWritable, path: path, options: [.recursive, .onlyFiles])

        // Write the state record.
        managedDependencies[forIdentity: package.identity] = ManagedDependency(
            packageRef: package,
            subpath: path.relative(to: checkoutsPath),
            checkoutState: checkoutState)
        try managedDependencies.saveState()

        return path
    }

    private func clone(
        package: PackageReference,
        requirement: PackageStateChange.Requirement
    ) throws -> AbsolutePath {
        // FIXME: We need to get the revision here, and we don't have a
        // way to get it back out of the resolver which is very
        // annoying. Maybe we should make an SPI on the provider for
        // this?
        let container = try await { containerProvider.getContainer(for: package, skipUpdate: true, completion: $0) } as! RepositoryPackageContainer
        let checkoutState: CheckoutState

        switch requirement {
        case .version(let version):
            let tag = container.getTag(for: version)!
            let revision = try container.getRevision(forTag: tag)
            checkoutState = CheckoutState(revision: revision, version: version)

        case .revision(let revision, let branch):
            checkoutState = CheckoutState(revision: revision, branch: branch)
        }

        return try self.clone(package: package, at: checkoutState)
    }

    /// Removes the clone and checkout of the provided specifier.
    fileprivate func remove(package: PackageReference) throws {
        
        guard let dependency = managedDependencies[forIdentity: package.identity] else {
            fatalError("This should never happen, trying to remove \(package.identity) which isn't in workspace")
        }
        
        // Inform the delegate.
        delegate.removing(repository: dependency.packageRef.repository.url)
        
        // Compute the dependency which we need to remove.
        let dependencyToRemove: ManagedDependency

        if let basedOn = dependency.basedOn {
            // Remove the underlying dependency for edited packages.
            dependencyToRemove = basedOn
            dependency.basedOn = nil
            managedDependencies[forIdentity: dependency.packageRef.identity] = dependency
        } else {
            dependencyToRemove = dependency
            managedDependencies[forIdentity: dependencyToRemove.packageRef.identity] = nil
        }
        
        // Remove the checkout.
        let dependencyPath = checkoutsPath.appending(dependencyToRemove.subpath)
        let checkedOutRepo = try repositoryManager.provider.openCheckout(at: dependencyPath)
        guard !checkedOutRepo.hasUncommittedChanges() else {
            throw WorkspaceDiagnostics.UncommitedChanges(repositoryPath: dependencyPath)
        }

        try fileSystem.chmod(.userWritable, path: dependencyPath, options: [.recursive, .onlyFiles])
        try fileSystem.removeFileTree(dependencyPath)

        // Remove the clone.
        try repositoryManager.remove(repository: dependencyToRemove.packageRef.repository)

        // Save the state.
        try managedDependencies.saveState()
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
