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
    func packageGraphWillLoad(currentGraph: PackageGraph, dependencies: AnySequence<ManagedDependency>, missingURLs: Set<String>)

    /// The workspace has started fetching this repository.
    func fetchingWillBegin(repository: String)

    /// The workspace has finished fetching this repository.
    func fetchingDidFinish(repository: String, diagnostic: Diagnostic?)

    /// The workspace has started cloning this repository.
    func cloning(repository: String)

    /// The workspace is checking out a repository.
    func checkingOut(repository: String, atReference reference: String, to path: AbsolutePath)

    /// The workspace is removing this repository because it is no longer needed.
    func removing(repository: String)

    /// The workspace operation emitted this warning.
    func warning(message: String)

    /// Called when the managed dependencies are updated.
    func managedDependenciesDidUpdate(_ dependencies: AnySequence<ManagedDependency>)
}

public extension WorkspaceDelegate {
    func checkingOut(repository: String, atReference: String, to path: AbsolutePath) {
        // Empty default implementation.
    }
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

        fileprivate init(root: PackageGraphRoot, dependencies: [(Manifest, ManagedDependency)]) {
            self.root = root
            self.dependencies = dependencies
        }

        /// Find a package given its name.
        public func lookup(package name: String) -> (manifest: Manifest, dependency: ManagedDependency)? {
            return dependencies.first(where: { $0.manifest.name == name })
        }

        /// Find a manifest given its name.
        public func lookup(manifest name: String) -> Manifest? {
            return lookup(package: name)?.manifest
        }

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

        /// Returns constraints of the dependencies.
        fileprivate func createDependencyConstraints() -> [RepositoryPackageConstraint] {
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
        fileprivate func unversionedConstraints() -> [RepositoryPackageConstraint] {
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

    /// Ends the edit mode of a dependency which is in edit mode.
    ///
    /// - Parameters:
    ///     - packageName: The name of the package to edit.
    ///     - forceRemove: If true, the dependency will be unedited even if has
    /// unpushed and uncommited changes. Otherwise will throw respective errors.
    ///
    /// - throws: WorkspaceError
    public func unedit(packageName: String, forceRemove: Bool) throws {
        let dependency = try managedDependencies.dependency(forName: packageName)
        try unedit(dependency: dependency, forceRemove: forceRemove)
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
    ///   - root: The workspace's root input.
    ///   - version: The version to pin at.
    ///   - branch: The branch to pin at.
    ///   - revision: The revision to pin at.
    ///   - diagnostics: The diagnostics engine that reports errors, warnings
    ///     and notes.
    public func pin(
        packageName: String,
        root: WorkspaceRoot,
        version: Version? = nil,
        branch: String? = nil,
        revision: String? = nil,
        diagnostics: DiagnosticsEngine
    ) {
        // Look up the dependency and check if we can pin it.
        guard let dependency = diagnostics.wrap({ try managedDependencies.dependency(forName: packageName) }) else {
            return
        }
        guard case .checkout(let currentState) = dependency.state else {
            let error = WorkspaceDiagnostics.DependencyAlreadyInEditMode(dependencyURL: dependency.repository.url)
            return diagnostics.emit(error)
        }

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

        // Load the root manifests and currently checked out manifests.
        let rootManifests = loadRootManifests(packages: root.packages, diagnostics: diagnostics) 

        // Load the current manifests.
        let graphRoot = PackageGraphRoot(manifests: rootManifests, dependencies: root.dependencies)
        let currentManifests = loadDependencyManifests(root: graphRoot, diagnostics: diagnostics)

        // Abort if we're unable to load the pinsStore or have any diagnostics.
        guard let pinsStore = diagnostics.wrap({ try self.pinsStore.load() }) else {
            return
        }

        // Ensure we don't have any error at this point.
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
        constraints += root.constraints

        var pins = pinsStore.createConstraints().filter({ $0.identifier != dependency.repository })
        pins.append(
            RepositoryPackageConstraint(
                container: dependency.repository, requirement: requirement))

        // Resolve the dependencies.
        let results = resolveDependencies(dependencies: constraints, pins: pins, diagnostics: diagnostics)
        guard !diagnostics.hasErrors else { return }

        // Update the checkouts based on new dependency resolution.
        updateCheckouts(with: results, diagnostics: diagnostics)
        guard !diagnostics.hasErrors else { return }

        // Get the updated dependency.
        let newDependency = managedDependencies[dependency.repository]!

        // Assert that the dependency is at the pinned checkout state now.
        if case .checkout(let checkoutState) = newDependency.state {
            assert(checkoutState.requirement() == requirement)
        } else {
            assertionFailure()
        }

        // Load the updated manifests.
        let updatedManifests = loadDependencyManifests(root: graphRoot, diagnostics: diagnostics)
        guard !diagnostics.hasErrors else { return }

        // Update the pins store.
        self.pinAll(
             pinsStore: pinsStore,
             dependencyManifests: updatedManifests,
             diagnostics: diagnostics)
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
            fileSystem.removeFileTree(dataPath.appending(RelativePath(name)))
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
        fileSystem.removeFileTree(dataPath)
    }

    /// Updates the current dependencies.
    ///
    /// - Parameters:
    ///     - diagnostics: The diagnostics engine that reports errors, warnings
    ///       and notes.
    public func updateDependencies(
        root: WorkspaceRoot,
        diagnostics: DiagnosticsEngine
    ) {
        // Create cache directories.
        createCacheDirectories(with: diagnostics)

        // Load the root manifests and currently checked out manifests.
        let rootManifests = loadRootManifests(packages: root.packages, diagnostics: diagnostics) 

        // Load the current manifests.
        let graphRoot = PackageGraphRoot(manifests: rootManifests, dependencies: root.dependencies)
        var currentManifests = loadDependencyManifests(root: graphRoot, diagnostics: diagnostics)

        // Abort if we're unable to load the pinsStore or have any diagnostics.
        guard let pinsStore = diagnostics.wrap({ try self.pinsStore.load() }) else {
            return
        }

        // Ensure we don't have any error at this point.
        guard !diagnostics.hasErrors else { return }

        // Create constraints based on root manifest and pins for the update resolution.
        var updateConstraints = rootManifests.flatMap({ $0.package.dependencyConstraints() })
        updateConstraints += root.constraints
        // Add unversioned constraints for edited packages.
        updateConstraints += currentManifests.unversionedConstraints()

        // Resolve the dependencies.
        let updateResults = resolveDependencies(dependencies: updateConstraints, pins: [], diagnostics: diagnostics)
        guard !diagnostics.hasErrors else { return }

		// Update the checkouts based on new dependency resolution.
        updateCheckouts(with: updateResults, updateBranches: true, diagnostics: diagnostics)
        guard !diagnostics.hasErrors else { return }

        // Get updated manifests.
        currentManifests = loadDependencyManifests(root: graphRoot, diagnostics: diagnostics)

        // Update the pins store.
        if !diagnostics.hasErrors {
            return pinAll(
                pinsStore: pinsStore,
                dependencyManifests: currentManifests,
                diagnostics: diagnostics)
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
        createMultipleTestProducts: Bool = false,
        diagnostics: DiagnosticsEngine
    ) -> PackageGraph {
        // Ensure the cache path exists and validate that edited dependencies.
        createCacheDirectories(with: diagnostics)

        // Load the root manifests and currently checked out manifests.
        let rootManifests = loadRootManifests(packages: root.packages, diagnostics: diagnostics) 

        // Load the current manifests.
        let graphRoot = PackageGraphRoot(manifests: rootManifests, dependencies: root.dependencies)
        let currentManifests = loadDependencyManifests(root: graphRoot, diagnostics: diagnostics)

        // Compute the missing URLs.
        let missingURLs = currentManifests.missingURLs()

        // When loading current package graph, we can't use the diagnostic
        // engine passed by clients because we will end up adding diagnostics
        // which might go away after a complete loading.
        let partialDiagnostics = DiagnosticsEngine()

        // Load the current package graph.
        let currentGraph = PackageGraphLoader().load(
            root: graphRoot,
            externalManifests: currentManifests.dependencies.map({ $0.manifest }),
            diagnostics: partialDiagnostics,
            fileSystem: fileSystem,
            shouldCreateMultipleTestProducts: createMultipleTestProducts)

        // If there are no missing URLs or if we encountered some errors, return the current graph.
        if diagnostics.hasErrors || missingURLs.isEmpty {
            // FIXME: Add API to append one engine to another.
            for diag in partialDiagnostics.diagnostics {
                diagnostics.emit(data: diag.data, location: diag.location)
            }
            return currentGraph
        }

        // Start by informing the delegate of what is happening.
        delegate.packageGraphWillLoad(
            currentGraph: currentGraph,
            dependencies: managedDependencies.values,
            missingURLs: missingURLs)

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
            updateCheckouts(with: result, diagnostics: diagnostics)
            guard !diagnostics.hasErrors else { break resolve }

            // Load the updated manifests.
            updatedManifests = loadDependencyManifests(root: graphRoot, diagnostics: diagnostics)

            // Reset and pin everything.
            if !diagnostics.hasErrors {
                self.pinAll(
                     pinsStore: pinsStore,
                     dependencyManifests: updatedManifests!,
                     diagnostics: diagnostics)
            }
        }

        return PackageGraphLoader().load(
            root: PackageGraphRoot(manifests: rootManifests, dependencies: root.dependencies),
            externalManifests: updatedManifests?.dependencies.map({ $0.manifest }) ?? [],
            diagnostics: diagnostics,
            fileSystem: fileSystem,
            shouldCreateMultipleTestProducts: createMultipleTestProducts
        )
    }

	/// Load the package graph data.
	///
	/// This method returns the package graph, and the mapping between each
	/// package and its corresponding managed dependency.
	///
	/// The current managed dependencies will be reported via the delegate
	/// before and after loading the package graph.
    public func loadGraphData(
        root: WorkspaceRoot,
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
        let managedDependenciesByName = Dictionary(items: managedDependencies.values.map({ ($0.name, $0) }))
        let dependencyMap = Dictionary(items: graph.packages.map({ package in
            (package, managedDependenciesByName[package.name])
        }))

        return (graph, dependencyMap)
    }

    /// Loads and returns manifests at the given paths.
    public func loadRootManifests(
        packages: [AbsolutePath],
        diagnostics: DiagnosticsEngine
    ) -> [Manifest] {
        return packages.flatMap({ package in
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
        let dependency = try managedDependencies.dependency(forName: packageName)

        guard case .checkout(let checkoutState) = dependency.state else {
            throw WorkspaceDiagnostics.DependencyAlreadyInEditMode(dependencyURL: dependency.repository.url)
        }

        // If a path is provided then we use it as destination. If not, we
        // use the folder with packageName inside editablesPath.
        let destination = path ?? editablesPath.appending(component: packageName)

        // If there is something present at the destination, we confirm it has
        // a valid manifest with name same as the package we are trying to edit.
        if fileSystem.exists(destination) {
            let manifest = loadManifest(
                packagePath: destination, url: dependency.repository.url, diagnostics: diagnostics)

            guard manifest?.name == packageName else {
                let error = WorkspaceDiagnostics.MismatchingDestinationPackage(
                    editPath: destination,
                    expectedPackage: packageName,
                    destinationPackage: manifest?.name)
                return diagnostics.emit(error)
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
        managedDependencies[dependency.repository] = dependency.editedDependency(
            subpath: RelativePath(packageName), unmanagedPath: path)
        try managedDependencies.saveState()
    }

    /// Unedit a managed dependency. See public API unedit(packageName:forceRemove:).
    fileprivate func unedit(dependency: ManagedDependency, forceRemove: Bool) throws {

        // Compute if we need to force remove.
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
        // Restore the dependency state.
        managedDependencies[dependency.repository] = dependency.basedOn
        // Save the state.
        try managedDependencies.saveState()
    }

}

// MARK: - Pinning Functions

extension Workspace {

    /// Pins the managed dependency.
    fileprivate func pin(
        pinsStore: PinsStore,
        dependency: ManagedDependency,
        package: String
    ) {
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
        pinsStore.pin(
            package: package,
            repository: dependency.repository,
            state: checkoutState)
    }

    /// Pins all of the dependencies to the loaded version.
    fileprivate func pinAll(
        pinsStore: PinsStore,
        dependencyManifests: DependencyManifests,
        diagnostics: DiagnosticsEngine
    ) {
		pinsStore.unpinAll()

        // Start pinning each dependency.
        for dependencyManifest in dependencyManifests.dependencies {
            pin(
                pinsStore: pinsStore,
                dependency: dependencyManifest.dependency,
                package: dependencyManifest.manifest.name)
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

        // Try to load current managed dependencies, or emit and return.
        do {
            try fixManagedDependencies()
        } catch {
            diagnostics.emit(error)
            return DependencyManifests(root: root, dependencies: [])
        }

        let rootDependencyManifests = root.dependencies.flatMap({
            return loadManifest(forDependencyURL: $0.url, diagnostics: diagnostics)
        })
        let inputManifests = root.manifests + rootDependencyManifests

        // Compute the transitive closure of available dependencies.
        let dependencies = transitiveClosure(inputManifests.map({ KeyedPair($0, key: $0.url) })) { node in
            return node.item.package.dependencies.flatMap({ dependency in
                let manifest = loadManifest(forDependencyURL: dependency.url, diagnostics: diagnostics)
                return manifest.flatMap({ KeyedPair($0, key: $0.url) })
            })
        }
        let deps = (rootDependencyManifests + dependencies.map({ $0.item })).map({ ($0, managedDependencies[$0.url]!) })
        return DependencyManifests(root: root, dependencies: deps)
    }


    /// Loads the given manifest, if it is present in the managed dependencies.
    fileprivate func loadManifest(forDependencyURL url: String, diagnostics: DiagnosticsEngine) -> Manifest? {
        // Check if this dependency is available.
        guard let managedDependency = managedDependencies[url] else {
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
        return loadManifest(packagePath: packagePath, url: url, version: version, diagnostics: diagnostics)
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

    /// This enum represents state of an external package.
    fileprivate enum PackageStateChange {
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

    /// Computes states of the packages based on last stored state.
    fileprivate func computePackageStateChanges(
        resolvedDependencies: [(RepositorySpecifier, BoundVersion)],
        updateBranches: Bool
    ) throws -> [RepositorySpecifier: PackageStateChange] {
        // Load pins store and managed dependendencies.
        let pinsStore = try self.pinsStore.load()

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

        // Run the resolver.
        let resolver = DependencyResolver(containerProvider, resolverDelegate,
            isPrefetchingEnabled: isResolverPrefetchingEnabled)
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
    fileprivate func fixManagedDependencies() throws {
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
        with updateResults: [(RepositorySpecifier, BoundVersion)],
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
        for (specifier, state) in packageStateChanges {
            diagnostics.wrap {
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
    }

    /// Fetch a given `repository` and create a local checkout for it.
    ///
    /// This will first clone the repository into the canonical repositories
    /// location, if necessary, and then check it out from there.
    ///
    /// - Returns: The path of the local repository.
    /// - Throws: If the operation could not be satisfied.
    private func fetch(repository: RepositorySpecifier) throws -> AbsolutePath {
        // If we already have it, fetch to update the repo from its remote.
        if let dependency = managedDependencies[repository] {
            let path = checkoutsPath.appending(dependency.subpath)

            // Make sure the directory is not missing (we will have to clone again
            // if not).
            if fileSystem.isDirectory(path) {
                // Fetch the checkout in case there are updates available.
                let workingRepo = try repositoryManager.provider.openCheckout(at: path)

                // The fetch operation may update contents of the checkout, so
                // we need do mutable-immutable dance.
                try fileSystem.chmod(.userWritable, path: path, options: [.recursive, .onlyFiles])
                try workingRepo.fetch()
                try? fileSystem.chmod(.userUnWritable, path: path, options: [.recursive, .onlyFiles])

                return path
            }
        }

        // If not, we need to get the repository from the checkouts.
        let handle = try repositoryManager.lookupSynchronously(repository: repository)

        // Clone the repository into the checkouts.
        let path = checkoutsPath.appending(component: repository.fileSystemIdentifier)

        try fileSystem.chmod(.userWritable, path: path, options: [.recursive, .onlyFiles])
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
    // FIXME: @testable internal
    func clone(
        repository: RepositorySpecifier,
        at checkoutState: CheckoutState
    ) throws -> AbsolutePath {
        // Get the repository.
        let path = try fetch(repository: repository)

        // Check out the given revision.
        let workingRepo = try repositoryManager.provider.openCheckout(at: path)
        // Inform the delegate.
        delegate.checkingOut(repository: repository.url, atReference: checkoutState.description, to: path)

        // Do mutable-immutable dance because checkout operation modifies the disk state.
        try fileSystem.chmod(.userWritable, path: path, options: [.recursive, .onlyFiles])
        try workingRepo.checkout(revision: checkoutState.revision)
        try? fileSystem.chmod(.userUnWritable, path: path, options: [.recursive, .onlyFiles])

        // Load the manifest.
        let diagnostics = DiagnosticsEngine()
        let manifest = loadManifest(
            packagePath: path, url: repository.url, version: checkoutState.version, diagnostics: diagnostics)

        // FIXME: We don't really expect to ever fail here but we should still handle any errors gracefully.
        guard let loadedManifest = manifest else {
            fatalError("Unexpected manifest loading failure \(diagnostics)")
        }

        // Write the state record.
        managedDependencies[repository] = ManagedDependency(
            name: loadedManifest.name,
            repository: repository,
            subpath: path.relative(to: checkoutsPath),
            checkoutState: checkoutState)
        try managedDependencies.saveState()

        return path
    }

    private func clone(
        specifier: RepositorySpecifier,
        requirement: PackageStateChange.Requirement
    ) throws -> AbsolutePath {
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

    /// Removes the clone and checkout of the provided specifier.
    private func remove(specifier: RepositorySpecifier) throws {
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

        try fileSystem.chmod(.userWritable, path: dependencyPath, options: [.recursive, .onlyFiles])
        fileSystem.removeFileTree(dependencyPath)

        // Remove the clone.
        try repositoryManager.remove(repository: dependency.repository)

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
