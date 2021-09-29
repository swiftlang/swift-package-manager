/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import TSCBasic
import TSCUtility
import Foundation
import PackageLoading
import PackageModel
import PackageGraph
import SourceControl

public typealias Diagnostic = TSCBasic.Diagnostic

/// Enumeration of the different reasons for which the resolver needs to be run.
public enum WorkspaceResolveReason: Equatable {
    /// Resolution was forced.
    case forced

    /// Requirements were added for new packages.
    case newPackages(packages: [PackageReference])

    /// The requirement of a dependency has changed.
    case packageRequirementChange(
        package: PackageReference,
        state: Workspace.ManagedDependency.State?,
        requirement: PackageRequirement
    )

    /// An unknown reason.
    case other
}

/// The delegate interface used by the workspace to report status information.
public protocol WorkspaceDelegate: AnyObject {

    /// The workspace is about to load a package manifest (which might be in the cache, or might need to be parsed). Note that this does not include speculative loading of manifests that may occr during dependency resolution; rather, it includes only the final manifest loading that happens after a particular package version has been checked out into a working directory.
    func willLoadManifest(packagePath: AbsolutePath, url: String, version: Version?, packageKind: PackageReference.Kind)
    /// The workspace has loaded a package manifest, either successfully or not. The manifest is nil if an error occurs, in which case there will also be at least one error in the list of diagnostics (there may be warnings even if a manifest is loaded successfully).
    func didLoadManifest(packagePath: AbsolutePath, url: String, version: Version?, packageKind: PackageReference.Kind, manifest: Manifest?, diagnostics: [Diagnostic])

    /// The workspace has started fetching this repository.
    func fetchingWillBegin(repository: String, fetchDetails: RepositoryManager.FetchDetails?)
    /// The workspace has finished fetching this repository.
    func fetchingDidFinish(repository: String, fetchDetails: RepositoryManager.FetchDetails?, diagnostic: Diagnostic?, duration: DispatchTimeInterval)

    /// The workspace has started updating this repository.
    func repositoryWillUpdate(_ repository: String)
    /// The workspace has finished updating this repository.
    func repositoryDidUpdate(_ repository: String, duration: DispatchTimeInterval)

    /// The workspace has finished updating and all the dependencies are already up-to-date.
    func dependenciesUpToDate()

    /// The workspace is about to clone a repository from the local cache to a working directory.
    func willCreateWorkingCopy(repository url: String, at path: AbsolutePath)
    /// The workspace has cloned a repository from the local cache to a working directory. The error indicates whether the operation failed or succeeded.
    // deprecated 04/2021, remove once clients moved over
    func didCreateWorkingCopy(repository url: String, at path: AbsolutePath, error: Diagnostic?)

    /// The workspace is about to check out a particular revision of a working directory.
    func willCheckOut(repository url: String, revision: String, at path: AbsolutePath)
    /// The workspace has checked out a particular revision of a working directory. The error indicates whether the operation failed or succeeded.
    func didCheckOut(repository url: String, revision: String, at path: AbsolutePath, error: Diagnostic?)

    /// The workspace is removing this repository because it is no longer needed.
    func removing(repository: String)

    /// Called when the resolver is about to be run.
    func willResolveDependencies(reason: WorkspaceResolveReason)

    /// Called when the resolver begins to be compute the version for the repository.
    func willComputeVersion(package: PackageIdentity, location: String)
    /// Called when the resolver finished computing the version for the repository.
    func didComputeVersion(package: PackageIdentity, location: String, version: String, duration: DispatchTimeInterval)

    /// Called when the Package.resolved file is changed *outside* of libSwiftPM operations.
    ///
    /// This is only fired when activated using Workspace's watchResolvedFile() method.
    func resolvedFileChanged()

    /// The workspace is downloading a binary artifact.
    func downloadingBinaryArtifact(from url: String, bytesDownloaded: Int64, totalBytesToDownload: Int64?)

    /// The workspace finished downloading all binary artifacts.
    func didDownloadBinaryArtifacts()

    /// Called every time the progress of the git fetch operation updates.
    func fetchingRepository(from repository: String, objectsFetched: Int, totalObjectsToFetch: Int)
}

private class WorkspaceRepositoryManagerDelegate: RepositoryManagerDelegate {
    unowned let workspaceDelegate: WorkspaceDelegate

    init(workspaceDelegate: WorkspaceDelegate) {
        self.workspaceDelegate = workspaceDelegate
    }

    func fetchingWillBegin(handle: RepositoryManager.RepositoryHandle, fetchDetails details: RepositoryManager.FetchDetails?) {
        workspaceDelegate.fetchingWillBegin(repository: handle.repository.url, fetchDetails: details)
    }

    func fetchingDidFinish(handle: RepositoryManager.RepositoryHandle, fetchDetails details: RepositoryManager.FetchDetails?, error: Swift.Error?, duration: DispatchTimeInterval) {
        let diagnostic: Diagnostic? = error.flatMap({
            let engine = DiagnosticsEngine()
            engine.emit($0)
            return engine.diagnostics.first
        })
        workspaceDelegate.fetchingDidFinish(repository: handle.repository.url, fetchDetails: details, diagnostic: diagnostic, duration: duration)
    }

    func handleWillUpdate(handle: RepositoryManager.RepositoryHandle) {
        workspaceDelegate.repositoryWillUpdate(handle.repository.url)
    }

    func handleDidUpdate(handle: RepositoryManager.RepositoryHandle, duration: DispatchTimeInterval) {
        workspaceDelegate.repositoryDidUpdate(handle.repository.url, duration: duration)
    }

    func fetchingRepository(from repository: String, objectsFetched: Int, totalObjectsToFetch: Int) {
        workspaceDelegate.fetchingRepository(from: repository, objectsFetched: objectsFetched, totalObjectsToFetch: totalObjectsToFetch)
    }
}

private struct WorkspaceDependencyResolverDelegate: DependencyResolverDelegate {
    unowned let workspaceDelegate: WorkspaceDelegate

    init(_ delegate: WorkspaceDelegate) {
        self.workspaceDelegate = delegate
    }

    func willResolve(term: Term) {
        self.workspaceDelegate.willComputeVersion(package: term.node.package.identity, location: term.node.package.location)
    }

    func didResolve(term: Term, version: Version, duration: DispatchTimeInterval) {
        self.workspaceDelegate.didComputeVersion(package: term.node.package.identity, location: term.node.package.location, version: version.description, duration: duration)
    }

    // noop
    func derived(term: Term) {}
    func conflict(conflict: Incompatibility) {}
    func satisfied(term: Term, by assignment: Assignment, incompatibility: Incompatibility) {}
    func partiallySatisfied(term: Term, by assignment: Assignment, incompatibility: Incompatibility, difference: Term) {}
    func failedToResolve(incompatibility: Incompatibility) {}
    func solved(result: [(package: PackageReference, binding: BoundVersion, products: ProductFilter)]) {}
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
    /// The delegate interface.
    fileprivate weak var delegate: WorkspaceDelegate?

    /// The workspace location.
    public let location: Location

    /// The mirrors config.
    fileprivate let mirrors: DependencyMirrors

    /// The current persisted state of the workspace.
    // public visibility for testing
    public let state: WorkspaceState

    /// The Pins store. The pins file will be created when first pin is added to pins store.
    // public visibility for testing
    public let pinsStore: LoadableResult<PinsStore>

    /// The file system on which the workspace will operate.
    fileprivate let fileSystem: FileSystem

    /// The manifest loader to use.
    fileprivate let manifestLoader: ManifestLoaderProtocol

    /// The tools version currently in use.
    fileprivate let currentToolsVersion: ToolsVersion

    /// The manifest loader to use.
    fileprivate var toolsVersionLoader: ToolsVersionLoaderProtocol

    /// Utility to resolve package identifiers
    // var for backwards compatibility with deprecated initializers, remove with them
    fileprivate var identityResolver: IdentityResolver

    /// The repository manager.
    // var for backwards compatibility with deprecated initializers, remove with them
    fileprivate var repositoryManager: RepositoryManager

    /// The http client used for downloading binary artifacts.
    fileprivate let httpClient: HTTPClient

    fileprivate let authorizationProvider: AuthorizationProvider?

    /// The downloader used for unarchiving binary artifacts.
    fileprivate let archiver: Archiver

    /// The algorithm used for generating file checksums.
    fileprivate let checksumAlgorithm: HashAlgorithm

    /// Enable prefetching containers in resolver.
    fileprivate let resolverPrefetchingEnabled: Bool

    /// Update containers while fetching them.
    fileprivate let resolverUpdateEnabled: Bool

    /// Write dependency resolver trace to a file.
    fileprivate let resolverTracingEnabled: Bool

    fileprivate let additionalFileRules: [FileRuleDescription]

    // state

    /// The active package resolver. This is set during a dependency resolution operation.
    fileprivate var activeResolver: PubgrubDependencyResolver?

    fileprivate var resolvedFileWatcher: ResolvedFileWatcher?

    /// Create a new package workspace.
    ///
    /// This initializer is designed for use cases when the workspace needs to be highly customized such as testing.
    /// In other cases, use the other, more straight forward, initializers
    ///
    /// This will automatically load the persisted state for the package, if
    /// present. If the state isn't present then a default state will be
    /// constructed.
    ///
    /// - Parameters:
    ///   - fileSystem: The file system to use.
    ///   - location: Workspace location configuration.
    ///   - mirrors: Dependencies mirrors.
    ///   - authorizationProvider: Provider of authentication information.
    ///   - customToolsVersion: A custom tools version.
    ///   - customManifestLoader: A custom manifest loader.
    ///   - customRepositoryManager: A custom repository manager.
    ///   - customRepositoryProvider: A custom repository provider.
    ///   - customIdentityResolver: A custom identity resolver.
    ///   - customHTTPClient: A custom http client.
    ///   - customArchiver: A custom archiver.
    ///   - customChecksumAlgorithm: A custom checksum algorithm.
    ///   - additionalFileRules: File rules to determine resource handling behavior.
    ///   - resolverUpdateEnabled: Enables the dependencies resolver automatic version update check.  Enabled by default. When disabled the resolver relies only on the resolved version file
    ///   - resolverPrefetchingEnabled: Enables the dependencies resolver prefetching based on the resolved version file.  Enabled by default..
    ///   - resolverTracingEnabled: Enables the dependencies resolver tracing.  Disabled by default..
    ///   - sharedRepositoriesCacheEnabled: Enables the shared repository cache. Enabled by default..
    ///   - delegate: Delegate for workspace events
    public init(
        fileSystem: FileSystem,
        location: Location,
        mirrors: DependencyMirrors? = .none,
        authorizationProvider: AuthorizationProvider? = .none,
        customToolsVersion: ToolsVersion? = .none,
        customManifestLoader: ManifestLoaderProtocol? = .none,
        customRepositoryManager: RepositoryManager? = .none,
        customRepositoryProvider: RepositoryProvider? = .none,
        customIdentityResolver: IdentityResolver? = .none,
        customHTTPClient: HTTPClient? = .none,
        customArchiver: Archiver? = .none,
        customChecksumAlgorithm: HashAlgorithm? = .none,
        additionalFileRules: [FileRuleDescription]? = .none,
        resolverUpdateEnabled: Bool? = .none,
        resolverPrefetchingEnabled: Bool? = .none,
        resolverTracingEnabled: Bool? = .none,
        sharedRepositoriesCacheEnabled: Bool? = .none,
        delegate: WorkspaceDelegate? = .none
    ) throws {
        // defaults
        let currentToolsVersion = customToolsVersion ?? ToolsVersion.currentToolsVersion
        let toolsVersionLoader = ToolsVersionLoader()
        let manifestLoader = try customManifestLoader ?? ManifestLoader(
            toolchain: UserToolchain(destination: .hostDestination()).configuration,
            cacheDir: location.sharedManifestsCacheDirectory
        )
        let repositoryProvider = customRepositoryProvider ?? GitRepositoryProvider()
        let sharedRepositoriesCacheEnabled = sharedRepositoriesCacheEnabled ?? true
        let repositoryManager = customRepositoryManager ?? RepositoryManager(
            fileSystem: fileSystem,
            path: location.repositoriesDirectory,
            provider: repositoryProvider,
            delegate: delegate.map(WorkspaceRepositoryManagerDelegate.init(workspaceDelegate:)),
            cachePath: sharedRepositoriesCacheEnabled ? location.sharedRepositoriesCacheDirectory : .none
        )
        // FIXME: use workspace scope when migrating workspace to new observability API
        let httpClient = customHTTPClient ?? HTTPClient(observabilityScope: ObservabilitySystem.topScope)
        let archiver = customArchiver ?? ZipArchiver()
        let mirrors = mirrors ?? DependencyMirrors()
        let identityResolver = customIdentityResolver ?? DefaultIdentityResolver(locationMapper: mirrors.effectiveURL(for:))
        var checksumAlgorithm = customChecksumAlgorithm ?? SHA256()
        #if canImport(CryptoKit)
        if checksumAlgorithm is SHA256, #available(macOS 10.15, *) {
            checksumAlgorithm = CryptoKitSHA256()
        }
        #endif

        let additionalFileRules = additionalFileRules ?? []
        let resolverUpdateEnabled = resolverUpdateEnabled ?? true
        let resolverPrefetchingEnabled = resolverPrefetchingEnabled ?? false
        let resolverTracingEnabled = resolverTracingEnabled ?? false

        // initialize
        self.fileSystem = fileSystem
        self.location = location
        self.delegate = delegate
        self.mirrors = mirrors
        self.authorizationProvider = authorizationProvider
        self.manifestLoader = manifestLoader
        self.currentToolsVersion = currentToolsVersion
        self.toolsVersionLoader = toolsVersionLoader
        self.httpClient = httpClient
        self.archiver = archiver
        self.repositoryManager = repositoryManager
        self.identityResolver = identityResolver
        self.checksumAlgorithm = checksumAlgorithm

        self.pinsStore = LoadableResult {
            try PinsStore(
                pinsFile: location.resolvedVersionsFile,
                workingDirectory: location.workingDirectory,
                fileSystem: fileSystem,
                mirrors: mirrors
            )
        }

        self.additionalFileRules = additionalFileRules
        self.resolverUpdateEnabled = resolverUpdateEnabled
        self.resolverPrefetchingEnabled = resolverPrefetchingEnabled
        self.resolverTracingEnabled = resolverTracingEnabled

        self.state = WorkspaceState(dataPath: self.location.workingDirectory, fileSystem: fileSystem)
    }

    // deprecated 8/2021
    @available(*, deprecated, message: "use non-deprecated initializer instead")
    public convenience init(
        dataPath: AbsolutePath,
        editablesPath: AbsolutePath,
        pinsFile: AbsolutePath,
        manifestLoader: ManifestLoaderProtocol,
        repositoryManager: RepositoryManager? = nil,
        currentToolsVersion: ToolsVersion? = nil,
        toolsVersionLoader: ToolsVersionLoaderProtocol? = nil,
        delegate: WorkspaceDelegate? = nil,
        config: Workspace.Configuration? = nil,
        fileSystem: FileSystem? = nil,
        repositoryProvider: RepositoryProvider? = nil,
        identityResolver: IdentityResolver? = nil,
        httpClient: HTTPClient? = nil,
        netrcFilePath: AbsolutePath? = nil,
        archiver: Archiver? = nil,
        checksumAlgorithm: HashAlgorithm? = nil,
        additionalFileRules: [FileRuleDescription]? = nil,
        isResolverPrefetchingEnabled: Bool? = nil,
        enablePubgrubResolver: Bool? = nil,
        skipUpdate: Bool? = nil,
        enableResolverTrace: Bool? = nil,
        cachePath: AbsolutePath? = nil
    ) {
        // try! safe in this case since the new initializer will only throw when creating a manifest loader
        // which is passed explicitly in this case. this initializer will go away soon in any case.
        let fileSystem = fileSystem ?? localFileSystem
        try! self.init(
            fileSystem: fileSystem,
            location: .init(
                workingDirectory: dataPath,
                editsDirectory: editablesPath,
                resolvedVersionsFile: pinsFile,
                sharedCacheDirectory: cachePath,
                sharedConfigurationDirectory: nil // legacy
            ),
            mirrors: config?.mirrors,
            authorizationProvider: netrcFilePath.map {
                try Configuration.Netrc(path: $0, fileSystem: fileSystem).get()
            },
            customToolsVersion: currentToolsVersion,
            customManifestLoader: manifestLoader,
            customRepositoryManager: repositoryManager,
            customRepositoryProvider: repositoryProvider,
            customIdentityResolver: identityResolver,
            customHTTPClient: httpClient,
            customArchiver: archiver,
            customChecksumAlgorithm: checksumAlgorithm,
            additionalFileRules: additionalFileRules,
            resolverUpdateEnabled: skipUpdate.map{ !$0 },
            resolverPrefetchingEnabled: isResolverPrefetchingEnabled,
            resolverTracingEnabled: enableResolverTrace
        )
        if let toolsVersionLoader = toolsVersionLoader {
            self.toolsVersionLoader = toolsVersionLoader
        }
    }

    /// A convenience method for creating a workspace for the given root
    /// package path.
    ///
    /// The root package path is used to compute the build directory and other
    /// default paths.
    ///
    /// - Parameters:
    ///   - fileSystem: The file system to use, defaults to local file system.
    ///   - forRootPackage: The path for the root package.
    ///   - customToolchain: A custom toolchain.
    ///   - delegate: Delegate for workspace events
    public convenience init(
        fileSystem: FileSystem? = .none,
        forRootPackage packagePath: AbsolutePath,
        customToolchain: UserToolchain,
        delegate: WorkspaceDelegate? = .none
    ) throws {
        let fileSystem = fileSystem ?? localFileSystem
        let location = Location(forRootPackage: packagePath, fileSystem: fileSystem)
        let manifestLoader = ManifestLoader(
            toolchain: customToolchain.configuration,
            cacheDir: location.sharedManifestsCacheDirectory
        )
        try self.init(
            fileSystem: fileSystem,
            forRootPackage: packagePath,
            customManifestLoader: manifestLoader,
            delegate: delegate
        )
    }

    /// A convenience method for creating a workspace for the given root
    /// package path.
    ///
    /// The root package path is used to compute the build directory and other
    /// default paths.
    ///
    /// - Parameters:
    ///   - fileSystem: The file system to use, defaults to local file system.
    ///   - forRootPackage: The path for the root package.
    ///   - customManifestLoader: A custom manifest loader.
    ///   - delegate: Delegate for workspace events
    public convenience init(
        fileSystem: FileSystem? = .none,
        forRootPackage packagePath: AbsolutePath,
        customManifestLoader: ManifestLoaderProtocol? =  .none,
        delegate: WorkspaceDelegate? =  .none
    ) throws {
        let fileSystem = fileSystem ?? localFileSystem
        let location = Location(forRootPackage: packagePath, fileSystem: fileSystem)
        try self .init(
            fileSystem: fileSystem,
            location: location,
            mirrors: try Configuration.Mirrors(
                forRootPackage: packagePath,
                sharedMirrorFile: location.sharedMirrorsConfigurationFile,
                fileSystem: fileSystem
            ).mirrors,
            customManifestLoader: customManifestLoader,
            delegate: delegate
        )
    }

    /// A convenience method for creating a workspace for the given root
    /// package path.
    ///
    /// The root package path is used to compute the build directory and other
    /// default paths.
    // deprecated 8/2021
    @available(*, deprecated, message: "use initializer instead")
    public static func create(
        forRootPackage packagePath: AbsolutePath,
        manifestLoader: ManifestLoaderProtocol,
        repositoryManager: RepositoryManager? = nil,
        delegate: WorkspaceDelegate? = nil,
        identityResolver: IdentityResolver? = nil
    ) -> Workspace {
        let workspace = try! Workspace(forRootPackage: packagePath,
                                       customManifestLoader: manifestLoader,
                                       delegate: delegate
        )
        if let repositoryManager = repositoryManager {
            workspace.repositoryManager = repositoryManager
        }
        if let identityResolver = identityResolver {
            workspace.identityResolver = identityResolver
        }
        return workspace
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
        guard let dependency = self.state.dependencies[.plain(packageName)] else {
            diagnostics.emit(.dependencyNotFound(packageName: packageName))
            return
        }

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
    ) throws {
        // Look up the dependency and check if we can pin it.
        guard let dependency = self.state.dependencies[.plain(packageName)] else {
            diagnostics.emit(.dependencyNotFound(packageName: packageName))
            return
        }
        guard let currentState = checkoutState(for: dependency, diagnostics: diagnostics) else {
            return
        }

        // Compute the custom or extra constraint we need to impose.
        let requirement: PackageRequirement
        if let version = version {
            requirement = .versionSet(.exact(version))
        } else if let branch = branch {
            requirement = .revision(branch)
        } else if let revision = revision {
            requirement = .revision(revision)
        } else {
            requirement = currentState.requirement
        }

        // If any products are required, the rest of the package graph will supply those constraints.
        let constraint = PackageContainerConstraint(package: dependency.packageRef, requirement: requirement, products: .nothing)

        // Run the resolution.
        try self.resolve(
            root: root,
            forceResolution: false,
            constraints: [constraint],
            diagnostics: diagnostics
        )
    }

    /// Cleans the build artifacts from workspace data.
    ///
    /// - Parameters:
    ///     - diagnostics: The diagnostics engine that reports errors, warnings
    ///       and notes.
    public func clean(with diagnostics: DiagnosticsEngine) {

        // These are the things we don't want to remove while cleaning.
        let protectedAssets = [
            self.repositoryManager.path,
            self.location.repositoriesCheckoutsDirectory,
            self.location.artifactsDirectory,
            self.state.storagePath,
        ].map({ path -> String in
            // Assert that these are present inside data directory.
            assert(path.parentDirectory == self.location.workingDirectory)
            return path.basename
        })

        // If we have no data yet, we're done.
        guard fileSystem.exists(self.location.workingDirectory) else {
            return
        }

        guard let contents = diagnostics.wrap({ try fileSystem.getDirectoryContents(self.location.workingDirectory) }) else {
            return
        }

        // Remove all but protected paths.
        let contentsToRemove = Set(contents).subtracting(protectedAssets)
        for name in contentsToRemove {
            try? fileSystem.removeFileTree(self.location.workingDirectory.appending(RelativePath(name)))
        }
    }

    /// Cleans the build artifacts from workspace data.
    ///
    /// - Parameters:
    ///     - diagnostics: The diagnostics engine that reports errors, warnings
    ///       and notes.
    public func purgeCache(with diagnostics: DiagnosticsEngine) {
        diagnostics.wrap {
            try repositoryManager.purgeCache()
            try manifestLoader.purgeCache()
        }
    }

    /// Resets the entire workspace by removing the data directory.
    ///
    /// - Parameters:
    ///     - diagnostics: The diagnostics engine that reports errors, warnings
    ///       and notes.
    public func reset(with diagnostics: DiagnosticsEngine) {
        let removed = diagnostics.wrap {
            try fileSystem.chmod(.userWritable, path: self.location.repositoriesCheckoutsDirectory, options: [.recursive, .onlyFiles])
            // Reset state.
            try self.resetState()
        }

        guard removed else { return }
        try? repositoryManager.reset()
        try? manifestLoader.resetCache()
        try? fileSystem.removeFileTree(self.location.workingDirectory)
    }

    // FIXME: @testable internal
    public func resetState() throws {
        try self.state.reset()
    }

    /// Cancel the active dependency resolution operation.
    public func cancelActiveResolverOperation() {
        // FIXME: Need to add cancel support.
    }

    /// Updates the current dependencies.
    ///
    /// - Parameters:
    ///     - diagnostics: The diagnostics engine that reports errors, warnings
    ///       and notes.
    @discardableResult
    public func updateDependencies(
        root: PackageGraphRootInput,
        packages: [String] = [],
        diagnostics: DiagnosticsEngine,
        dryRun: Bool = false
    ) throws -> [(PackageReference, Workspace.PackageStateChange)]? {
        // Create cache directories.
        createCacheDirectories(with: diagnostics)

        // FIXME: this should not block
        // Load the root manifests and currently checked out manifests.
        let rootManifests = try temp_await { self.loadRootManifests(packages: root.packages, diagnostics: diagnostics, completion: $0) }

        // Load the current manifests.
        let graphRoot = PackageGraphRoot(input: root, manifests: rootManifests)
        let currentManifests = try self.loadDependencyManifests(root: graphRoot, diagnostics: diagnostics)

        // Abort if we're unable to load the pinsStore or have any diagnostics.
        guard let pinsStore = diagnostics.wrap({ try self.pinsStore.load() }) else { return nil }

        // Ensure we don't have any error at this point.
        guard !diagnostics.hasErrors else { return nil }

        // Add unversioned constraints for edited packages.
        var updateConstraints = currentManifests.editedPackagesConstraints()

        // Create constraints based on root manifest and pins for the update resolution.
        updateConstraints += try graphRoot.constraints()

        let pinsMap: PinsStore.PinsMap
        if packages.isEmpty {
            // No input packages so we have to do a full update. Set pins map to empty.
            pinsMap = [:]
        } else {
            // We have input packages so we have to partially update the package graph. Remove
            // the pins for the input packages so only those packages are updated.
            pinsMap = pinsStore.pinsMap.filter{ !packages.contains($0.value.packageRef.name) }
        }

        // Resolve the dependencies.
        let resolver = try self.createResolver(pinsMap: pinsMap)
        self.activeResolver = resolver

        let updateResults = resolveDependencies(
            resolver: resolver,
            constraints: updateConstraints,
            diagnostics: diagnostics
        )

        // Reset the active resolver.
        self.activeResolver = nil

        guard !diagnostics.hasErrors else { return nil }

        if dryRun {
            return diagnostics.wrap { return try computePackageStateChanges(root: graphRoot, resolvedDependencies: updateResults, updateBranches: true) }
        }

        // Update the checkouts based on new dependency resolution.
        let packageStateChanges = self.updateDependenciesCheckouts(root: graphRoot, updateResults: updateResults, updateBranches: true, diagnostics: diagnostics)

        // Load the updated manifests.
        let updatedDependencyManifests = try self.loadDependencyManifests(root: graphRoot, diagnostics: diagnostics)

        // Update the pins store.
        pinAll(
            dependencyManifests: updatedDependencyManifests,
            pinsStore: pinsStore,
            diagnostics: diagnostics)

        // Update the binary target artifacts.
        let addedOrUpdatedPackages = packageStateChanges.compactMap({ $0.1.isAddedOrUpdated ? $0.0 : nil })
        try self.updateBinaryArtifacts(
            manifests: updatedDependencyManifests,
            addedOrUpdatedPackages: addedOrUpdatedPackages,
            diagnostics: diagnostics)

        return nil
    }

    /// Loads a package graph from a root package using the resources associated with a particular `swiftc` executable.
    ///
    /// - Parameters:
    ///   - at: The absolute path of the root package.
    ///   - swiftCompiler: The absolute path of a `swiftc` executable. Its associated resources will be used by the loader.
    ///   - identityResolver: A helper to resolve identities based on configuration
    ///   - diagnostics: Optional.  The diagnostics engine.
    ///   - on: The dispatch queue to perform asynchronous operations on.
    ///   - completion: The completion handler .
    // deprecated 8/2021
    @available(*, deprecated, message: "use workspace instance API instead")
    public static func loadRootGraph(
        at packagePath: AbsolutePath,
        swiftCompiler: AbsolutePath,
        swiftCompilerFlags: [String],
        identityResolver: IdentityResolver? = nil,
        diagnostics: DiagnosticsEngine
    ) throws -> PackageGraph {
        let toolchain = ToolchainConfiguration(swiftCompiler: swiftCompiler, swiftCompilerFlags: swiftCompilerFlags)
        let loader = ManifestLoader(toolchain: toolchain)
        let workspace = Workspace.create(forRootPackage: packagePath, manifestLoader: loader, identityResolver: identityResolver)
        return try workspace.loadPackageGraph(rootPath: packagePath, diagnostics: diagnostics)
    }

    @discardableResult
    public func loadPackageGraph(
        rootInput root: PackageGraphRootInput,
        explicitProduct: String? = nil,
        createMultipleTestProducts: Bool = false,
        createREPLProduct: Bool = false,
        forceResolvedVersions: Bool = false,
        diagnostics: DiagnosticsEngine,
        xcTestMinimumDeploymentTargets: [PackageModel.Platform:PlatformVersion]? = nil
    ) throws -> PackageGraph {

        // Perform dependency resolution, if required.
        let manifests: DependencyManifests
        if forceResolvedVersions {
            manifests = try self.resolveBasedOnResolvedVersionsFile(
                root: root,
                explicitProduct: explicitProduct,
                diagnostics: diagnostics
            )
        } else {
            manifests = try self.resolve(
                root: root,
                explicitProduct: explicitProduct,
                forceResolution: false,
                constraints: [],
                diagnostics: diagnostics
            )
        }

        let binaryArtifacts = try self.state.artifacts.map{ artifact -> BinaryArtifact in
            return try BinaryArtifact(kind: artifact.kind(), originURL: artifact.originURL, path: artifact.path)
        }

        // Load the graph.
        return try PackageGraph.load(
            root: manifests.root,
            identityResolver: self.identityResolver,
            additionalFileRules: additionalFileRules,
            externalManifests: manifests.allDependencyManifests(),
            requiredDependencies: manifests.computePackageURLs().required,
            unsafeAllowedPackages: manifests.unsafeAllowedPackages(),
            binaryArtifacts: binaryArtifacts,
            xcTestMinimumDeploymentTargets: xcTestMinimumDeploymentTargets ?? MinimumDeploymentTarget.default.xcTestMinimumDeploymentTargets,
            shouldCreateMultipleTestProducts: createMultipleTestProducts,
            createREPLProduct: createREPLProduct,
            fileSystem: fileSystem
        )
    }

    @discardableResult
    public func loadPackageGraph(
        rootPath: AbsolutePath,
        explicitProduct: String? = nil,
        diagnostics: DiagnosticsEngine
    ) throws -> PackageGraph {
        try self.loadPackageGraph(
            rootInput: PackageGraphRootInput(packages: [rootPath]),
            explicitProduct: explicitProduct,
            diagnostics: diagnostics
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
        forceResolution: Bool = false,
        diagnostics: DiagnosticsEngine
    ) throws {
        try self.resolve(
            root: root,
            forceResolution: forceResolution,
            constraints: [],
            diagnostics: diagnostics
        )
    }

    /// Loads and returns manifests at the given paths.
    public func loadRootManifests(
        packages: [AbsolutePath],
        diagnostics: DiagnosticsEngine,
        completion: @escaping(Result<[AbsolutePath: Manifest], Error>) -> Void
    ) {
        let lock = Lock()
        let sync = DispatchGroup()
        var rootManifests = [AbsolutePath: Manifest]()
        Set(packages).forEach { package in
            sync.enter()
            // TODO: this does not use the identity resolver which is probably fine since its the root packages
            self.loadManifest(packageIdentity: PackageIdentity(path: package), packageKind: .root(package), packagePath: package, packageLocation: package.pathString, diagnostics: diagnostics) { result in
                defer { sync.leave() }
                if case .success(let manifest) = result {
                    lock.withLock {
                        rootManifests[package] = manifest
                    }
                }
            }
        }

        sync.notify(queue: .sharedConcurrent) {
            // Check for duplicate root packages.
            let duplicateRoots = rootManifests.values.spm_findDuplicateElements(by: \.name)
            if !duplicateRoots.isEmpty {
                let name = duplicateRoots[0][0].name
                diagnostics.emit(error: "found multiple top-level packages named '\(name)'")
                return completion(.success([:]))
            }

            completion(.success(rootManifests))
        }
    }

    /// Loads and returns manifest at the given path.
    public func loadRootManifest(
        at path: AbsolutePath,
        diagnostics: DiagnosticsEngine,
        completion: @escaping(Result<Manifest, Error>) -> Void
    ) {
        self.loadRootManifests(packages: [path], diagnostics: diagnostics) { result in
            completion(result.tryMap{
                // normally, we call loadRootManifests which attempts to load any manifest it can and report errors via diagnostics
                // in this case, we want to load a specific manifest, so if the diagnostics contains an error we want to throw
                guard !diagnostics.hasErrors else {
                    throw Diagnostics.fatalError
                }
                guard let manifest = $0[path] else {
                    throw InternalError("Unknown manifest for '\(path)'")
                }
                return manifest
            })
        }
    }

    public func loadRootPackage(
        at path: AbsolutePath,
        diagnostics: DiagnosticsEngine,
        completion: @escaping(Result<Package, Error>) -> Void
    ) {
        self.loadRootManifest(at: path, diagnostics: diagnostics) { result in
            let result = result.tryMap { manifest -> Package in
                let identity = try self.identityResolver.resolveIdentity(for: manifest.packageKind)
                let builder = PackageBuilder(
                    identity: identity,
                    manifest: manifest,
                    productFilter: .everything,
                    path: path,
                    xcTestMinimumDeploymentTargets: MinimumDeploymentTarget.default.xcTestMinimumDeploymentTargets,
                    fileSystem: self.fileSystem
                )
                return try builder.construct()
            }
            completion(result)
        }
    }

    /// Generates the checksum
    public func checksum(
        forBinaryArtifactAt path: AbsolutePath,
        diagnostics: DiagnosticsEngine
    ) -> String {
        // Validate the path has a supported extension.
        guard let pathExtension = path.extension, archiver.supportedExtensions.contains(pathExtension) else {
            let supportedExtensionList = archiver.supportedExtensions.joined(separator: ", ")
            diagnostics.emit(error: "unexpected file type; supported extensions are: \(supportedExtensionList)")
            return ""
        }

        // Ensure that the path with the accepted extension is a file.
        guard fileSystem.isFile(path) else {
            diagnostics.emit(error: "file not found at path: \(path.pathString)")
            return ""
        }

        return diagnostics.wrap {
            let contents = try fileSystem.readFileContents(path)
            return self.checksumAlgorithm.hash(contents).hexadecimalRepresentation
        } ?? ""
    }
}

// MARK: - Editing Functions

extension Workspace {

    func checkoutState(
        for dependency: ManagedDependency,
        diagnostics: DiagnosticsEngine
    ) -> CheckoutState? {
        switch dependency.state {
        case .checkout(let checkoutState):
            return checkoutState
        case .edited:
            diagnostics.emit(error: "dependency '\(dependency.packageRef.name)' already in edit mode")
        case .local:
            diagnostics.emit(error: "local dependency '\(dependency.packageRef.name)' can't be edited")
        }
        return nil
    }

    /// Edit implementation.
    fileprivate func _edit(
        packageName: String,
        path: AbsolutePath? = nil,
        revision: Revision? = nil,
        checkoutBranch: String? = nil,
        diagnostics: DiagnosticsEngine
    ) throws {
        // Look up the dependency and check if we can edit it.
        guard let dependency = self.state.dependencies[.plain(packageName)] else {
            diagnostics.emit(.dependencyNotFound(packageName: packageName))
            return
        }

        guard let checkoutState = checkoutState(for: dependency, diagnostics: diagnostics) else {
            return
        }

        // If a path is provided then we use it as destination. If not, we
        // use the folder with packageName inside editablesPath.
        let destination = path ?? self.location.editsDirectory.appending(component: packageName)

        // If there is something present at the destination, we confirm it has
        // a valid manifest with name same as the package we are trying to edit.
        if fileSystem.exists(destination) {
            // FIXME: this should not block
            let manifest = try temp_await {
                self.loadManifest(packageIdentity: dependency.packageRef.identity,
                                  packageKind: .fileSystem(destination),
                                  packagePath: destination,
                                  packageLocation: dependency.packageRef.location,
                                  diagnostics: diagnostics,
                                  completion: $0)
            }

            guard manifest.name == packageName else {
                return diagnostics.emit(error: "package at '\(destination)' is \(manifest.name) but was expecting \(packageName)")
            }

            // Emit warnings for branch and revision, if they're present.
            if let checkoutBranch = checkoutBranch {
                diagnostics.emit(.editBranchNotCheckedOut(
                    packageName: packageName,
                    branchName: checkoutBranch))
            }
            if let revision = revision {
                diagnostics.emit(.editRevisionNotUsed(
                    packageName: packageName,
                    revisionIdentifier: revision.identifier))
            }
        } else {
            // Otherwise, create a checkout at the destination from our repository store.
            //
            // Get handle to the repository.
            // TODO: replace with async/await when available
            let repository = try dependency.packageRef.makeRepositorySpecifier()
            let handle = try temp_await {
                repositoryManager.lookup(repository: repository, skipUpdate: true, on: .sharedConcurrent, completion: $0)
            }
            let repo = try handle.open()

            // Do preliminary checks on branch and revision, if provided.
            if let branch = checkoutBranch, repo.exists(revision: Revision(identifier: branch)) {
                throw WorkspaceDiagnostics.BranchAlreadyExists(branch: branch)
            }
            if let revision = revision, !repo.exists(revision: revision) {
                throw WorkspaceDiagnostics.RevisionDoesNotExist(revision: revision.identifier)
            }

            let workingCopy = try handle.createWorkingCopy(at: destination, editable: true)
            try workingCopy.checkout(revision: revision ?? checkoutState.revision)

            // Checkout to the new branch if provided.
            if let branch = checkoutBranch {
                try workingCopy.checkout(newBranch: branch)
            }
        }

        // For unmanaged dependencies, create the symlink under editables dir.
        if let path = path {
            try fileSystem.createDirectory(self.location.editsDirectory)
            // FIXME: We need this to work with InMem file system too.
            if !(fileSystem is InMemoryFileSystem) {
                let symLinkPath = self.location.editsDirectory.appending(component: packageName)

                // Cleanup any existing symlink.
                if fileSystem.isSymlink(symLinkPath) {
                    try fileSystem.removeFileTree(symLinkPath)
                }

                // FIXME: We should probably just warn in case we fail to create
                // this symlink, which could happen if there is some non-symlink
                // entry at this location.
                try fileSystem.createSymbolicLink(symLinkPath, pointingAt: path, relative: false)
            }
        }

        // Remove the existing checkout.
        do {
            let oldCheckoutPath = self.location.repositoriesCheckoutsDirectory.appending(dependency.subpath)
            try fileSystem.chmod(.userWritable, path: oldCheckoutPath, options: [.recursive, .onlyFiles])
            try fileSystem.removeFileTree(oldCheckoutPath)
        }

        // Save the new state.
        self.state.dependencies.add(
            dependency.edited(subpath: RelativePath(packageName), unmanagedPath: path)
        )
        try self.state.save()
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
        case .checkout, .local:
            throw WorkspaceDiagnostics.DependencyNotInEditMode(dependencyName: dependency.packageRef.name)

        case .edited(_, let path):
            if path != nil {
                // Set force remove to true for unmanaged dependencies.  Note that
                // this only removes the symlink under the editable directory and
                // not the actual unmanaged package.
                forceRemove = true
            }
        }

        // Form the edit working repo path.
        let path = self.location.editsDirectory.appending(dependency.subpath)
        // Check for uncommited and unpushed changes if force removal is off.
        if !forceRemove {
            let workingCopy = try repositoryManager.openWorkingCopy(at: path)
            guard !workingCopy.hasUncommittedChanges() else {
                throw WorkspaceDiagnostics.UncommitedChanges(repositoryPath: path)
            }
            guard try !workingCopy.hasUnpushedCommits() else {
                throw WorkspaceDiagnostics.UnpushedChanges(repositoryPath: path)
            }
        }
        // Remove the editable checkout from disk.
        if fileSystem.exists(path) {
            try fileSystem.removeFileTree(path)
        }
        // If this was the last editable dependency, remove the editables directory too.
        if fileSystem.exists(self.location.editsDirectory), try fileSystem.getDirectoryContents(self.location.editsDirectory).isEmpty {
            try fileSystem.removeFileTree(self.location.editsDirectory)
        }

        if case .edited(let basedOn, _) = dependency.state, case .checkout(let checkoutState) = basedOn?.state {
            // Restore the original checkout.
            //
            // The retrieve method will automatically update the managed dependency state.
            _ = try self.retrieve(package: dependency.packageRef, at: checkoutState)
        } else {
            // The original dependency was removed, update the managed dependency state.
            self.state.dependencies.remove(dependency.packageRef.identity)
            try self.state.save()
        }

        // Resolve the dependencies if workspace root is provided. We do this to
        // ensure the unedited version of this dependency is resolved properly.
        if let root = root {
            try self.resolve(root: root, diagnostics: diagnostics)
        }
    }

}

// MARK: - Pinning Functions

extension Workspace {

    /// Pins all of the current managed dependencies at their checkout state.
    fileprivate func pinAll(
        dependencyManifests: DependencyManifests,
        pinsStore: PinsStore,
        diagnostics: DiagnosticsEngine
    ) {
        // Reset the pinsStore and start pinning the required dependencies.
        pinsStore.unpinAll()

        let requiredURLs = dependencyManifests.computePackageURLs().required

        for dependency in self.state.dependencies  {
            if requiredURLs.contains(where: { $0.location == dependency.packageRef.location }) {
                pinsStore.pin(dependency)
            }
        }
        diagnostics.wrap{
            try pinsStore.saveState()
        }

        // Ask resolved file watcher to update its value so we don't fire
        // an extra event if the file was modified by us.
        self.resolvedFileWatcher?.updateValue()
    }
}

fileprivate extension PinsStore {
    /// Pin a managed dependency at its checkout state.
    ///
    /// This method does nothing if the dependency is in edited state.
    func pin(_ dependency: Workspace.ManagedDependency) {

        // Get the checkout state.
        let checkoutState: CheckoutState
        switch dependency.state {
        case .checkout(let state):
            checkoutState = state
        case .edited, .local:
            return
        }

        self.pin(
            packageRef: dependency.packageRef,
            state: checkoutState
        )
    }
}

// MARK: - Manifest Loading and caching

extension Workspace {
    /// A struct representing all the current manifests (root + external) in a package graph.
    public struct DependencyManifests {
        /// The package graph root.
        let root: PackageGraphRoot

        /// The dependency manifests in the transitive closure of root manifest.
        let dependencies: [(manifest: Manifest, dependency: ManagedDependency, productFilter: ProductFilter)]

        let workspace: Workspace

        fileprivate init(
            root: PackageGraphRoot,
            dependencies: [(manifest: Manifest, dependency: ManagedDependency, productFilter: ProductFilter)],
            workspace: Workspace
        ) {
            self.root = root
            self.dependencies = dependencies
            self.workspace = workspace
        }

        /// Returns all manifests contained in DependencyManifests.
        public func allDependencyManifests() -> OrderedDictionary<PackageIdentity, Manifest> {
            return self.dependencies.reduce(into: OrderedDictionary<PackageIdentity, Manifest>()) { partial, item in
                partial[item.dependency.packageIdentity] = item.manifest
            }
        }

        /// Computes the identities which are declared in the manifests but aren't present in dependencies.
        public func missingPackageURLs() -> Set<PackageReference> {
            return self.computePackageURLs().missing
        }

        /// Returns the list of packages which are allowed to vend products with unsafe flags.
        func unsafeAllowedPackages() -> Set<PackageReference> {
            var result = Set<PackageReference>()

            for dependency in self.dependencies {
                let dependency = dependency.dependency
                switch dependency.state {
                case .checkout(let checkout):
                    if checkout.isBranchOrRevisionBased {
                        result.insert(dependency.packageRef)
                    }
                case .edited:
                    continue
                case .local:
                    result.insert(dependency.packageRef)
                }
            }

            // Root packages are always allowed to use unsafe flags.
            result.formUnion(root.packageReferences)

            return result
        }

        func computePackageURLs() -> (required: Set<PackageReference>, missing: Set<PackageReference>) {
            let manifestsMap: [PackageIdentity: Manifest] = Dictionary(uniqueKeysWithValues:
                self.root.packages.map { ($0.key, $0.value.manifest) } +
                self.dependencies.map { ($0.dependency.packageIdentity, $0.manifest) }
            )

            var inputIdentities: Set<PackageReference> = []
            let inputNodes: [GraphLoadingNode] = self.root.packages.map{ identity, package in
                inputIdentities.insert(package.reference)
                let node = GraphLoadingNode(identity: identity, manifest: package.manifest, productFilter: .everything)
                return node
            } + self.root.dependencies.compactMap{ dependency in
                let package = dependency.createPackageRef()
                inputIdentities.insert(package)
                return manifestsMap[dependency.identity].map { manifest in
                    GraphLoadingNode(identity: dependency.identity, manifest: manifest, productFilter: dependency.productFilter)
                }
            }

            // FIXME: this is dropping legitimate packages with equal identities and should be revised as part of the identity work
            var requiredIdentities: Set<PackageReference> = []
            _ = transitiveClosure(inputNodes) { node in
                return node.manifest.dependenciesRequired(for: node.productFilter).compactMap{ dependency in
                    let package = dependency.createPackageRef()
                    requiredIdentities.insert(package)
                    return manifestsMap[dependency.identity].map { manifest in
                        GraphLoadingNode(identity: dependency.identity, manifest: manifest, productFilter: dependency.productFilter)
                    }
                }
            }
            // FIXME: This should be an ordered set.
            requiredIdentities = inputIdentities.union(requiredIdentities)

            let availableIdentities: Set<PackageReference> = Set(manifestsMap.map {
                // FIXME: adding this guard to ensure refactoring is correct 9/21
                // we only care about remoteSourceControl for this validation. it would otherwise trigger for
                // a dependency is put into edit mode, which we want to deprecate anyways
                if case .remoteSourceControl = $0.1.packageKind {
                    let effectiveURL = workspace.mirrors.effectiveURL(for: $0.1.packageLocation)
                    guard effectiveURL == $0.1.packageKind.locationString else {
                        preconditionFailure("effective url for \($0.1.packageLocation) is \(effectiveURL), different from expected \($0.1.packageKind.locationString)")
                    }
                }
                return PackageReference(identity: $0.key, kind: $0.1.packageKind)
            })
            // We should never have loaded a manifest we don't need.
            assert(availableIdentities.isSubset(of: requiredIdentities), "\(availableIdentities) | \(requiredIdentities)")
            // These are the missing package identities.
            let missingIdentities = requiredIdentities.subtracting(availableIdentities)

            return (requiredIdentities, missingIdentities)
        }

        /// Returns constraints of the dependencies, including edited package constraints.
        func dependencyConstraints() throws -> [PackageContainerConstraint] {
            var allConstraints = [PackageContainerConstraint]()

            for (externalManifest, managedDependency, productFilter) in dependencies {
                // For edited packages, add a constraint with unversioned requirement so the
                // resolver doesn't try to resolve it.
                switch managedDependency.state {
                case .edited:
                    // FIXME: We shouldn't need to construct a new package reference object here.
                    // We should get the correct one from managed dependency object.
                    let ref = PackageReference.fileSystem(
                        identity: managedDependency.packageRef.identity,
                        path: workspace.path(to: managedDependency)
                    )
                    let constraint = PackageContainerConstraint(
                        package: ref,
                        requirement: .unversioned,
                        products: productFilter)
                    allConstraints.append(constraint)
                case .checkout, .local:
                    break
                }
                allConstraints += try externalManifest.dependencyConstraints(productFilter: productFilter)
            }
            return allConstraints
        }

        // FIXME: @testable(internal)
        /// Returns a list of constraints for all 'edited' package.
        public func editedPackagesConstraints() -> [PackageContainerConstraint] {
            var constraints = [PackageContainerConstraint]()

            for (_, managedDependency, productFilter) in dependencies {
                switch managedDependency.state {
                case .checkout, .local: continue
                case .edited: break
                }
                // FIXME: We shouldn't need to construct a new package reference object here.
                // We should get the correct one from managed dependency object.
                let ref = PackageReference.fileSystem(
                    identity: managedDependency.packageRef.identity,
                    path: workspace.path(to: managedDependency)
                )
                let constraint = PackageContainerConstraint(
                    package: ref,
                    requirement: .unversioned,
                    products: productFilter)
                constraints.append(constraint)
            }
            return constraints
        }
    }

    /// Watch the Package.resolved for changes.
    ///
    /// This is useful if clients want to be notified when the Package.resolved
    /// file is changed *outside* of libSwiftPM operations. For example, as part
    /// of a git operation.
    public func watchResolvedFile() throws {
        // Return if we're already watching it.
        guard self.resolvedFileWatcher == nil else { return }
        self.resolvedFileWatcher = try ResolvedFileWatcher(resolvedFile: self.location.resolvedVersionsFile) { [weak self] in
            self?.delegate?.resolvedFileChanged()
        }
    }

    /// Create the cache directories.
    fileprivate func createCacheDirectories(with diagnostics: DiagnosticsEngine) {
        do {
            try fileSystem.createDirectory(self.repositoryManager.path, recursive: true)
            try fileSystem.createDirectory(self.location.repositoriesCheckoutsDirectory, recursive: true)
            try fileSystem.createDirectory(self.location.artifactsDirectory, recursive: true)
        } catch {
            diagnostics.emit(error)
        }
    }

    /// Returns the location of the dependency.
    ///
    /// Checkout dependencies will return the subpath inside `checkoutsPath` and
    /// edited dependencies will either return a subpath inside `editablesPath` or
    /// a custom path.
    public func path(to dependency: Workspace.ManagedDependency) -> AbsolutePath {
        switch dependency.state {
        case .checkout:
            return self.location.repositoriesCheckoutsDirectory.appending(dependency.subpath)
        case .edited(_, let path):
            return path ?? self.location.editsDirectory.appending(dependency.subpath)
        case .local:
            return AbsolutePath(dependency.packageRef.location)
        }
    }

    /// Returns manifest interpreter flags for a package.
    public func interpreterFlags(for packagePath: AbsolutePath) -> [String] {
        // We ignore all failures here and return empty array.
        guard let manifestLoader = self.manifestLoader as? ManifestLoader,
              let toolsVersion = try? toolsVersionLoader.load(at: packagePath, fileSystem: fileSystem),
              currentToolsVersion >= toolsVersion,
              toolsVersion >= ToolsVersion.minimumRequired else {
            return []
        }
        return manifestLoader.interpreterFlags(for: toolsVersion)
    }

    /// Load the manifests for the current dependency tree.
    ///
    /// This will load the manifests for the root package as well as all the
    /// current dependencies from the working checkouts.l
    public func loadDependencyManifests(
        root: PackageGraphRoot,
        diagnostics: DiagnosticsEngine,
        automaticallyAddManagedDependencies: Bool = false
    ) throws -> DependencyManifests {
        // Utility Just because a raw tuple cannot be hashable.
        struct Key: Hashable {
            let identity: PackageIdentity
            let productFilter: ProductFilter
        }

        // Make a copy of dependencies as we might mutate them in the for loop.
        let dependenciesToCheck = Array(self.state.dependencies)
        // Remove any managed dependency which has become a root.
        for dependency in dependenciesToCheck {
            if root.packages.keys.contains(dependency.packageRef.identity) {
                diagnostics.wrap {
                    try self.remove(package: dependency.packageRef)
                }
            }
        }

        // Validates that all the managed dependencies are still present in the file system.
        self.fixManagedDependencies(with: diagnostics)
        guard !diagnostics.hasErrors else {
            return DependencyManifests(root: root, dependencies: [], workspace: self)
        }

        // Load root dependencies manifests (in parallel)
        let rootDependencies = root.dependencies.map{ $0.createPackageRef() }
        let rootDependenciesManifests = try temp_await { self.loadManagedManifests(for: rootDependencies, diagnostics: diagnostics, completion: $0) }

        let topLevelManifests = root.manifests.merging(rootDependenciesManifests, uniquingKeysWith: { lhs, rhs in
            return lhs // prefer roots!
        })

        // optimization: preload first level dependencies manifest (in parallel)
        let firstLevelDependencies = topLevelManifests.values.map { $0.dependencies.map{ $0.createPackageRef() } }.flatMap { $0 }
        let firstLevelManifests = try temp_await { self.loadManagedManifests(for: firstLevelDependencies, diagnostics: diagnostics, completion: $0) } // FIXME: this should not block

        // Continue to load the rest of the manifest for this graph
        // Creates a map of loaded manifests. We do this to avoid reloading the shared nodes.
        var loadedManifests = firstLevelManifests
        // Compute the transitive closure of available dependencies.
        let input = topLevelManifests.map { identity, manifest in KeyedPair(manifest, key: Key(identity: identity, productFilter: .everything)) }
        let allManifestsWithPossibleDuplicates = try topologicalSort(input) { pair in
            // optimization: preload manifest we know about in parallel
            let dependenciesRequired = pair.item.dependenciesRequired(for: pair.key.productFilter)
            // prepopulate managed dependencies if we are asked to do so
            // FIXME: this seems like hack, needs further investigation why this is needed
            if automaticallyAddManagedDependencies {
                dependenciesRequired.filter { $0.isLocal }.forEach { dependency in
                    self.state.dependencies.add(.local(packageRef: dependency.createPackageRef()))
                }
                diagnostics.wrap { try self.state.save() }
            }
            let dependenciesToLoad = dependenciesRequired.map{ $0.createPackageRef() }.filter { !loadedManifests.keys.contains($0.identity) }
            let dependenciesManifests = try temp_await { self.loadManagedManifests(for: dependenciesToLoad, diagnostics: diagnostics, completion: $0) }
            dependenciesManifests.forEach { loadedManifests[$0.key] = $0.value }
            return pair.item.dependenciesRequired(for: pair.key.productFilter).compactMap{ dependency in
                loadedManifests[dependency.identity].flatMap {
                    // we also compare the location as this function may attempt to load
                    // dependencies that have the same identity but from a different location
                    // which is an error case we diagnose an report about in the GraphLoading part which
                    // is prepared to handle the case where not all manifest are available
                    $0.packageLocation == dependency.location ?
                    KeyedPair($0, key: Key(identity: dependency.identity, productFilter: dependency.productFilter)) : nil
                }
            }
        }

        // merge the productFilter of the same package (by identity)
        var deduplication = [PackageIdentity: Int]()
        var allManifests = [(identity: PackageIdentity, manifest: Manifest, productFilter: ProductFilter)]()
        for pair in allManifestsWithPossibleDuplicates {
            if let index = deduplication[pair.key.identity]  {
                let productFilter = allManifests[index].productFilter.merge(pair.key.productFilter)
                allManifests[index] = (pair.key.identity, pair.item, productFilter)
            } else {
                deduplication[pair.key.identity] = allManifests.count
                allManifests.append((pair.key.identity, pair.item, pair.key.productFilter))
            }
        }

        let dependencyManifests = allManifests.filter{ !root.manifests.values.contains($0.manifest) }

        // TODO: this check should go away when introducing explicit overrides
        // check for overrides attempts with same name but different path
        let rootManifestsByName = Array(root.manifests.values).spm_createDictionary{ ($0.name, $0) }
        dependencyManifests.forEach { identity, manifest, _ in
            if let override = rootManifestsByName[manifest.name], override.packageLocation != manifest.packageLocation  {
                diagnostics.emit(error: "unable to override package '\(manifest.name)' because its identity '\(PackageIdentity(urlString: manifest.packageLocation))' doesn't match override's identity (directory name) '\(PackageIdentity(urlString: override.packageLocation))'")
            }
        }

        let dependencies = try dependencyManifests.map{ identity, manifest, productFilter -> (Manifest, ManagedDependency, ProductFilter) in
            guard let dependency = self.state.dependencies[identity] else {
                throw InternalError("dependency not found for \(identity) at \(manifest.packageLocation)")
            }
            return (manifest, dependency, productFilter)
        }

        return DependencyManifests(root: root, dependencies: dependencies, workspace: self)
    }

    /// Loads the given manifests, if it is present in the managed dependencies.
    private func loadManagedManifests(for packages: [PackageReference], diagnostics: DiagnosticsEngine, completion: @escaping (Result<[PackageIdentity: Manifest], Error>) -> Void) {
        let sync = DispatchGroup()
        let manifests = ThreadSafeKeyValueStore<PackageIdentity, Manifest>()
        Set(packages).forEach { package in
            sync.enter()
            self.loadManagedManifest(for: package, diagnostics: diagnostics) { manifest in
                defer { sync.leave() }
                if let manifest = manifest {
                    manifests[package.identity] = manifest
                }
            }
        }

        sync.notify(queue: .sharedConcurrent) {
            completion(.success(manifests.get()))
        }
    }

    /// Loads the given manifest, if it is present in the managed dependencies.
    fileprivate func loadManagedManifest(for package: PackageReference, diagnostics: DiagnosticsEngine, completion: @escaping (Manifest?) -> Void) {
        // Check if this dependency is available.
        // we also compare the location as this function may attempt to load
        // dependencies that have the same identity but from a different location
        // which is an error case we diagnose an report about in the GraphLoading part which
        // is prepared to handle the case where not all manifest are available
        guard let managedDependency = self.state.dependencies[comparingLocation: package] else {
            return completion(.none)
        }

        // Get the path of the package.
        let packagePath = path(to: managedDependency)

        // The kind and version, if known.
        let packageKind: PackageReference.Kind
        let version: Version?
        switch managedDependency.state {
        case .checkout(let checkoutState):
            packageKind = managedDependency.packageRef.kind
            switch checkoutState {
            case .version(let checkoutVersion, _):
                version = checkoutVersion
            default:
                version = .none
            }
        case .edited, .local:
            packageKind = .fileSystem(packagePath)
            version = .none
        }


        // Load and return the manifest.
        self.loadManifest(packageIdentity: managedDependency.packageRef.identity,
                          packageKind: packageKind,
                          packagePath: packagePath,
                          packageLocation: managedDependency.packageRef.location,
                          version: version,
                          diagnostics: diagnostics) { result in
            // error is added to diagnostics in the function above
            completion(try? result.get())
        }
    }

    /// Load the manifest at a given path.
    ///
    /// This is just a helper wrapper to the manifest loader.
    fileprivate func loadManifest(
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packagePath: AbsolutePath,
        packageLocation: String,
        version: Version? = nil,
        diagnostics: DiagnosticsEngine,
        completion: @escaping (Result<Manifest, Error>) -> Void
    ) {
        // Load the manifest, bracketed by the calls to the delegate callbacks.
        delegate?.willLoadManifest(packagePath: packagePath, url: packageLocation, version: version, packageKind: packageKind)
        diagnostics.with(location: PackageLocation.Local(packagePath: packagePath)) { diagnostics in
            do {
                // Load the tools version for the package.
                let toolsVersion = try toolsVersionLoader.load(at: packagePath, fileSystem: fileSystem)

                // Validate the tools version.
                try toolsVersion.validateToolsVersion(currentToolsVersion, packageIdentity: packageIdentity)

                // Load the manifest.
                // The delegate callback is only passed any diagnostics emitted during the parsing of the manifest, but they are also forwarded up to the caller.
                let manifestLoadingDiagnostics = DiagnosticsEngine(handlers: [{ diagnostics.emit($0) }], defaultLocation: diagnostics.defaultLocation)
                manifestLoader.load(at: packagePath,
                                    packageIdentity: packageIdentity,
                                    packageKind: packageKind,
                                    packageLocation: packageLocation,
                                    version: version,
                                    revision: nil,
                                    toolsVersion: toolsVersion,
                                    identityResolver: self.identityResolver,
                                    fileSystem: localFileSystem,
                                    diagnostics: manifestLoadingDiagnostics,
                                    on: .sharedConcurrent) { result in

                    switch result {
                    // Diagnostics.fatalError indicates that a more specific diagnostic has already been added.
                    case .failure(Diagnostics.fatalError):
                        break
                    case .failure(let error):
                        diagnostics.emit(error)
                    case .success(let manifest):
                        self.delegate?.didLoadManifest(packagePath: packagePath, url: packageLocation, version: version, packageKind: packageKind, manifest: manifest, diagnostics: manifestLoadingDiagnostics.diagnostics)
                    }
                    completion(result)
                }
            } catch {
                diagnostics.emit(error)
                completion(.failure(error))
            }
        }
    }

    /// Validates that all the edited dependencies are still present in the file system.
    /// If some checkout dependency is removed form the file system, clone it again.
    /// If some edited dependency is removed from the file system, mark it as unedited and
    /// fallback on the original checkout.
    fileprivate func fixManagedDependencies(with diagnostics: DiagnosticsEngine) {

        // Reset managed dependencies if the state file was removed during the lifetime of the Workspace object.
        if !self.state.dependencies.isEmpty && !self.state.stateFileExists() {
            try? self.state.reset()
        }

        // Make a copy of dependencies as we might mutate them in the for loop.
        let allDependencies = Array(self.state.dependencies)
        for dependency in allDependencies {
            diagnostics.wrap {

                // If the dependency is present, we're done.
                let dependencyPath = self.path(to: dependency)
                guard !fileSystem.isDirectory(dependencyPath) else { return }

                switch dependency.state {
                case .checkout(let checkoutState):
                    // If some checkout dependency has been removed, retrieve it again.
                    _ = try self.retrieve(package: dependency.packageRef, at: checkoutState)
                    diagnostics.emit(.checkedOutDependencyMissing(packageName: dependency.packageRef.name))

                case .edited:
                    // If some edited dependency has been removed, mark it as unedited.
                    //
                    // Note: We don't resolve the dependencies when unediting
                    // here because we expect this method to be called as part
                    // of some other resolve operation (i.e. resolve, update, etc).
                    try unedit(dependency: dependency, forceRemove: true, diagnostics: diagnostics)

                    diagnostics.emit(.editedDependencyMissing(packageName: dependency.packageRef.name))

                case .local:
                    self.state.dependencies.remove(dependency.packageRef.identity)
                    try self.state.save()
                }
            }
        }
    }
}

// MARK: - Binary artifacts

extension Workspace {
    fileprivate func updateBinaryArtifacts(
        manifests: DependencyManifests,
        addedOrUpdatedPackages: [PackageReference],
        diagnostics: DiagnosticsEngine
    ) throws {
        let manifestArtifacts = try self.parseArtifacts(from: manifests)

        var artifactsToRemove: [ManagedArtifact] = []
        var artifactsToAdd: [ManagedArtifact] = []
        var artifactsToDownload: [RemoteArtifact] = []

        for artifact in state.artifacts {
            if !manifestArtifacts.local.contains(where: { $0.packageRef == artifact.packageRef && $0.targetName == artifact.targetName }) &&
                !manifestArtifacts.remote.contains(where: { $0.packageRef == artifact.packageRef && $0.targetName == artifact.targetName }) {
                artifactsToRemove.append(artifact)
            }
        }

        for artifact in manifestArtifacts.local {
            let existingArtifact = self.state.artifacts[
                packageIdentity: artifact.packageRef.identity,
                targetName: artifact.targetName
            ]

            if let existingArtifact = existingArtifact, case .remote = existingArtifact.source {
                // If we go from a remote to a local artifact, we can remove the old remote artifact.
                artifactsToRemove.append(existingArtifact)
            }

            artifactsToAdd.append(artifact)
        }

        for artifact in manifestArtifacts.remote {
            let existingArtifact = self.state.artifacts[
                packageIdentity: artifact.packageRef.identity,
                targetName: artifact.targetName
            ]

            if let existingArtifact = existingArtifact, case .remote(_, let existingChecksum) = existingArtifact.source {
                // If we already have an artifact with the same checksum, we don't need to download it again.
                if artifact.checksum == existingChecksum {
                    continue
                }

                // If the checksum is different but the package wasn't updated, this is a security risk.
                if !addedOrUpdatedPackages.contains(artifact.packageRef) {
                    diagnostics.emit(.artifactChecksumChanged(targetName: artifact.targetName))
                    continue
                }

                artifactsToRemove.append(existingArtifact)
            }

            artifactsToDownload.append(artifact)
        }

        // Remove the artifacts and directories which are not needed anymore.
        diagnostics.wrap {
            for artifact in artifactsToRemove {
                state.artifacts.remove(packageIdentity: artifact.packageRef.identity, targetName: artifact.targetName)

                if case .remote = artifact.source {
                    try fileSystem.removeFileTree(artifact.path)
                }
            }

            for directory in try fileSystem.getDirectoryContents(self.location.artifactsDirectory) {
                let directoryPath = self.location.artifactsDirectory.appending(component: directory)
                if try fileSystem.isDirectory(directoryPath) && fileSystem.getDirectoryContents(directoryPath).isEmpty {
                    try fileSystem.removeFileTree(directoryPath)
                }
            }
        }

        guard !diagnostics.hasErrors else {
            throw Diagnostics.fatalError
        }

        // Download the artifacts
        let downloadedArtifacts = try self.download(artifactsToDownload, diagnostics: diagnostics)
        artifactsToAdd.append(contentsOf: downloadedArtifacts)

        // Add the new artifacts
        for artifact in artifactsToAdd {
            self.state.artifacts.add(artifact)
        }

        guard !diagnostics.hasErrors else {
            throw Diagnostics.fatalError
        }

        diagnostics.wrap {
            try self.state.save()
        }
    }

    private func parseArtifacts(from manifests: DependencyManifests) throws -> (local: [ManagedArtifact], remote: [RemoteArtifact]) {
        let packageAndManifests: [(reference: PackageReference, manifest: Manifest)] =
            manifests.root.packages.values + // Root package and manifests.
            manifests.dependencies.map({ manifest, managed, _ in (managed.packageRef, manifest) }) // Dependency package and manifests.

        var localArtifacts: [ManagedArtifact] = []
        var remoteArtifacts: [RemoteArtifact] = []

        for (packageReference, manifest) in packageAndManifests {
            for target in manifest.targets where target.type == .binary {
                if let path = target.path {
                    // TODO: find a better way to get the base path (not via the manifest)
                    let absolutePath = try manifest.path.parentDirectory.appending(RelativePath(validating: path))
                    localArtifacts.append(
                        .local(
                            packageRef: packageReference,
                            targetName: target.name,
                            path: absolutePath)
                    )
                } else if let url = target.url.flatMap(URL.init(string:)), let checksum = target.checksum {
                    remoteArtifacts.append(
                        .init(
                            packageRef: packageReference,
                            targetName: target.name,
                            url: url,
                            checksum: checksum)
                    )
                } else {
                    throw InternalError("a binary target should have either a path or a URL and a checksum")
                }
            }
        }

        return (local: localArtifacts, remote: remoteArtifacts)
    }

    private func download(_ artifacts: [RemoteArtifact], diagnostics: DiagnosticsEngine) throws -> [ManagedArtifact] {
        let group = DispatchGroup()
        let tempDiagnostics = DiagnosticsEngine() // FIXME: transition to DiagnosticsEmmiter
        let result = ThreadSafeArrayStore<ManagedArtifact>()

        // zip files to download
        // stored in a thread-safe way as we may fetch more from "artifactbundleindex" files
        let zipArtifacts = ThreadSafeArrayStore<RemoteArtifact>(artifacts.filter { $0.url.pathExtension.lowercased() == "zip" })

        // fetch and parse "artifactbundleindex" files, if any
        let indexFiles = artifacts.filter { $0.url.pathExtension.lowercased() == "artifactbundleindex" }
        if !indexFiles.isEmpty {
            let hostToolchain = try UserToolchain(destination: .hostDestination())
            let jsonDecoder = JSONDecoder.makeWithDefaults()
            for indexFile in indexFiles {
                group.enter()
                var request = HTTPClient.Request(method: .get, url: indexFile.url)
                request.options.validResponseCodes = [200]
                request.options.authorizationProvider = self.authorizationProvider?.httpAuthorizationHeader(for:)
                self.httpClient.execute(request) { result in
                    defer { group.leave() }

                    do {
                        switch result {
                        case .failure(let error):
                            throw error
                        case .success(let response):
                            guard let body = response.body else {
                                throw StringError("Body is empty")
                            }
                            // FIXME: would be nice if checksumAlgorithm.hash took Data directly
                            let bodyChecksum = self.checksumAlgorithm.hash(ByteString(body)).hexadecimalRepresentation
                            guard bodyChecksum == indexFile.checksum else {
                                throw StringError("checksum of downloaded artifact of binary target '\(indexFile.targetName)' (\(bodyChecksum)) does not match checksum specified by the manifest (\(indexFile.checksum ))")
                            }
                            let metadata = try jsonDecoder.decode(ArchiveIndexFile.self, from: body)
                            // FIXME: this filter needs to become more sophisticated
                            guard let supportedArchive = metadata.archives.first(where: { $0.fileName.lowercased().hasSuffix(".zip") && $0.supportedTriples.contains(hostToolchain.triple) }) else {
                                throw StringError("No supported archive was found for '\(hostToolchain.triple.tripleString)'")
                            }
                            // add relevant archive
                            zipArtifacts.append(
                                RemoteArtifact(
                                    packageRef: indexFile.packageRef,
                                    targetName: indexFile.targetName,
                                    url: indexFile.url.deletingLastPathComponent().appendingPathComponent(supportedArchive.fileName),
                                    checksum: supportedArchive.checksum)
                            )
                        }
                    } catch {
                        tempDiagnostics.emit(error: "failed retrieving '\(indexFile.url)': \(error)")
                    }
                }
            }

            // wait for all "artifactbundleindex" files to be processed
            group.wait()

            // no reason to continue if we already ran into issues
            if tempDiagnostics.hasErrors {
                // collect all diagnostics
                diagnostics.append(contentsOf: tempDiagnostics)
                throw Diagnostics.fatalError
            }
        }

        // finally download zip files, if any
        for artifact in (zipArtifacts.map{ $0 }) {
            group.enter()
            defer { group.leave() }

            let parentDirectory =  self.location.artifactsDirectory.appending(component: artifact.packageRef.name)
            let tempExtractionDirectory = self.location.artifactsDirectory.appending(components: "extract", artifact.targetName)

            do {
                try fileSystem.createDirectory(parentDirectory, recursive: true)
                if fileSystem.exists(tempExtractionDirectory) {
                    try fileSystem.removeFileTree(tempExtractionDirectory)
                }
                try fileSystem.createDirectory(tempExtractionDirectory, recursive: true)
            } catch {
                tempDiagnostics.emit(error)
                continue
            }

            let archivePath = parentDirectory.appending(component: artifact.url.lastPathComponent)

            group.enter()
            var request = HTTPClient.Request.download(url: artifact.url, fileSystem: self.fileSystem, destination: archivePath)
            request.options.authorizationProvider = self.authorizationProvider?.httpAuthorizationHeader(for:)
            request.options.validResponseCodes = [200]
            self.httpClient.execute(
                request,
                progress: { bytesDownloaded, totalBytesToDownload in
                    self.delegate?.downloadingBinaryArtifact(
                        from: artifact.url.absoluteString,
                        bytesDownloaded: bytesDownloaded,
                        totalBytesToDownload: totalBytesToDownload)
                },
                completion: { downloadResult in
                    defer { group.leave() }

                    switch downloadResult {
                    case .success:
                        let archiveChecksum = self.checksum(forBinaryArtifactAt: archivePath, diagnostics: tempDiagnostics )
                        guard archiveChecksum == artifact.checksum else {
                            tempDiagnostics.emit(
                                .artifactInvalidChecksum(targetName: artifact.targetName, expectedChecksum: artifact.checksum, actualChecksum: archiveChecksum))
                            tempDiagnostics.wrap { try self.fileSystem.removeFileTree(archivePath) }
                            return
                        }

                        group.enter()
                        self.archiver.extract(from: archivePath, to: tempExtractionDirectory, completion: { extractResult in
                            defer { group.leave() }

                            switch extractResult {
                            case .success:
                                var artifactPath: AbsolutePath? = nil
                                tempDiagnostics.wrap {
                                    // copy from temp location to actual location
                                    let content = try self.fileSystem.getDirectoryContents(tempExtractionDirectory)
                                    for file in content {
                                        let source = tempExtractionDirectory.appending(component: file)
                                        let destination = parentDirectory.appending(component: file)
                                        if self.fileSystem.exists(destination) {
                                            try self.fileSystem.removeFileTree(destination)
                                        }
                                        try self.fileSystem.copy(from: source, to: destination)
                                        if destination.basenameWithoutExt == artifact.targetName {
                                            artifactPath = destination
                                        }
                                    }
                                    // remove temp location
                                    try self.fileSystem.removeFileTree(tempExtractionDirectory)
                                }

                                guard let mainArtifactPath = artifactPath else {
                                    return tempDiagnostics.emit(.artifactNotFound(targetName: artifact.targetName, artifactName: artifact.targetName))
                                }

                                result.append(
                                    .remote(
                                        packageRef: artifact.packageRef,
                                        targetName: artifact.targetName,
                                        url: artifact.url.absoluteString,
                                        checksum: artifact.checksum,
                                        path: mainArtifactPath
                                    )
                                )
                            case .failure(let error):
                                let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                                tempDiagnostics.emit(.artifactFailedExtraction(artifactURL: artifact.url, targetName: artifact.targetName, reason: reason))
                            }

                            tempDiagnostics.wrap { try self.fileSystem.removeFileTree(archivePath) }
                        })
                    case .failure(let error):
                        tempDiagnostics.emit(.artifactFailedDownload(artifactURL: artifact.url, targetName: artifact.targetName, reason: "\(error)"))
                    }
                })
        }

        group.wait()

        if zipArtifacts.count > 0 {
            delegate?.didDownloadBinaryArtifacts()
        }

        // collect all diagnostics
        diagnostics.append(contentsOf: tempDiagnostics)

        return result.map{ $0 }
    }
}

// MARK: - Dependency Management

extension Workspace {

    @available(*, deprecated, message: "renamed to resolveBasedOnResolvedVersionsFile")
    public func resolveToResolvedVersion(root: PackageGraphRootInput,diagnostics: DiagnosticsEngine) throws {
        try self.resolveBasedOnResolvedVersionsFile(root: root, diagnostics: diagnostics)
    }

    /// Resolves the dependencies according to the entries present in the Package.resolved file.
    ///
    /// This method bypasses the dependency resolution and resolves dependencies
    /// according to the information in the resolved file.
    public func resolveBasedOnResolvedVersionsFile(root: PackageGraphRootInput, diagnostics: DiagnosticsEngine) throws {
        try self.resolveBasedOnResolvedVersionsFile(root: root, explicitProduct: .none, diagnostics: diagnostics)
    }

    /// Resolves the dependencies according to the entries present in the Package.resolved file.
    ///
    /// This method bypasses the dependency resolution and resolves dependencies
    /// according to the information in the resolved file.
    @discardableResult
    fileprivate func resolveBasedOnResolvedVersionsFile(
        root: PackageGraphRootInput,
        explicitProduct: String?,
        diagnostics: DiagnosticsEngine
    ) throws -> DependencyManifests {
        // Ensure the cache path exists.
        self.createCacheDirectories(with: diagnostics)

        // FIXME: this should not block
        let rootManifests = try temp_await { self.loadRootManifests(packages: root.packages, diagnostics: diagnostics, completion: $0) }
        let graphRoot = PackageGraphRoot(input: root, manifests: rootManifests, explicitProduct: explicitProduct)

        // Load the pins store or abort now.
        guard let pinsStore = diagnostics.wrap({ try self.pinsStore.load() }), !diagnostics.hasErrors else {
            return try self.loadDependencyManifests(root: graphRoot, diagnostics: diagnostics)
        }

        // Request all the containers to fetch them in parallel.
        //
        // We just request the packages here, repository manager will
        // automatically manage the parallelism.
        for pin in pinsStore.pins {
            self.getContainer(for: pin.packageRef, skipUpdate: true, on: .sharedConcurrent, completion: { _ in })
        }

        // Compute the pins that we need to actually clone.
        //
        // We require cloning if there is no checkout or if the checkout doesn't
        // match with the pin.
        let requiredPins = pinsStore.pins.filter{ pin in
            // also compare the location in case it has changed
            guard let dependency = state.dependencies[comparingLocation: pin.packageRef] else {
                return true
            }
            switch dependency.state {
            case .checkout(let checkoutState):
                return pin.state != checkoutState
            case .edited, .local:
                return true
            }
        }

        // Retrieve the required pins.
        for pin in requiredPins {
            diagnostics.wrap {
                _ = try self.retrieve(package: pin.packageRef, at: pin.state)
            }
        }

        let currentManifests = try self.loadDependencyManifests(root: graphRoot, diagnostics: diagnostics, automaticallyAddManagedDependencies: true)

        let precomputationResult = try self.precomputeResolution(
            root: graphRoot,
            dependencyManifests: currentManifests,
            pinsStore: pinsStore,
            constraints: []
        )

        if case let .required(reason) = precomputationResult {
            let reasonString = Self.format(workspaceResolveReason: reason)

            if !fileSystem.exists(self.location.resolvedVersionsFile) {
                diagnostics.emit(error: "a resolved file is required when automatic dependency resolution is disabled and should be placed at \(self.location.resolvedVersionsFile.pathString). \(reasonString)")
            } else {
                diagnostics.emit(error: "an out-of-date resolved file was detected at \(self.location.resolvedVersionsFile.pathString), which is not allowed when automatic dependency resolution is disabled; please make sure to update the file to reflect the changes in dependencies. \(reasonString)")
            }
        }

        try self.updateBinaryArtifacts(manifests: currentManifests, addedOrUpdatedPackages: [], diagnostics: diagnostics)

        return currentManifests
    }

    /// Implementation of resolve(root:diagnostics:).
    ///
    /// The extra constraints will be added to the main requirements.
    /// It is useful in situations where a requirement is being
    /// imposed outside of manifest and pins file. E.g., when using a command
    /// like `$ swift package resolve foo --version 1.0.0`.
    @discardableResult
    fileprivate func resolve(
        root: PackageGraphRootInput,
        explicitProduct: String? = nil,
        forceResolution: Bool,
        constraints: [PackageContainerConstraint],
        diagnostics: DiagnosticsEngine,
        retryOnPackagePathMismatch: Bool = true,
        resetPinsStoreOnFailure: Bool = true
    ) throws -> DependencyManifests {

        // Ensure the cache path exists and validate that edited dependencies.
        self.createCacheDirectories(with: diagnostics)

        // FIXME: this should not block
        // Load the root manifests and currently checked out manifests.
        let rootManifests = try temp_await { self.loadRootManifests(packages: root.packages, diagnostics: diagnostics, completion: $0) }

        // Load the current manifests.
        let graphRoot = PackageGraphRoot(input: root, manifests: rootManifests, explicitProduct: explicitProduct)
        let currentManifests = try self.loadDependencyManifests(root: graphRoot, diagnostics: diagnostics)
        guard !diagnostics.hasErrors else {
            return currentManifests
        }

        validatePinsStore(dependencyManifests: currentManifests, diagnostics: diagnostics)

        // Abort if pinsStore is unloadable or if diagnostics has errors.
        guard !diagnostics.hasErrors, let pinsStore = diagnostics.wrap({ try pinsStore.load() }) else {
            return currentManifests
        }

        // Compute the missing package identities.
        let missingPackageURLs = currentManifests.missingPackageURLs()

        // Compute if we need to run the resolver. We always run the resolver if
        // there are extra constraints.
        if !missingPackageURLs.isEmpty {
            delegate?.willResolveDependencies(reason: .newPackages(packages: Array(missingPackageURLs)))
        } else if !constraints.isEmpty || forceResolution {
            delegate?.willResolveDependencies(reason: .forced)
        } else {
            let result = try self.precomputeResolution(
                root: graphRoot,
                dependencyManifests: currentManifests,
                pinsStore: pinsStore,
                constraints: constraints
            )

            switch result {
            case .notRequired:
                try self.updateBinaryArtifacts(
                    manifests: currentManifests,
                    addedOrUpdatedPackages: [],
                    diagnostics: diagnostics)

                return currentManifests
            case .required(let reason):
                delegate?.willResolveDependencies(reason: reason)
            }
        }

        // Create the constraints.
        var computedConstraints = [PackageContainerConstraint]()
        computedConstraints += currentManifests.editedPackagesConstraints()
        computedConstraints += try graphRoot.constraints() + constraints

        // Perform dependency resolution.
        let resolver = try createResolver(pinsMap: pinsStore.pinsMap)
        self.activeResolver = resolver

        let result = self.resolveDependencies(
            resolver: resolver,
            constraints: computedConstraints,
            diagnostics: diagnostics)

        // Reset the active resolver.
        self.activeResolver = nil

        guard !diagnostics.hasErrors else {
            return currentManifests
        }

        // Update the checkouts with dependency resolution result.
        let packageStateChanges = self.updateDependenciesCheckouts(root: graphRoot, updateResults: result, diagnostics: diagnostics)
        guard !diagnostics.hasErrors else {
            return currentManifests
        }

        // Update the pinsStore.
        let updatedDependencyManifests = try self.loadDependencyManifests(root: graphRoot, diagnostics: diagnostics)

        // If we still have required URLs, we probably cloned a wrong URL for
        // some package dependency.
        //
        // This would usually happen when we're resolving from scratch and the
        // resolved file has an outdated entry for a transitive dependency whose
        // URL was changed. For e.g., the resolved file could refer to a dependency
        // through a ssh url but its new reference is now changed to http.
        let missing = updatedDependencyManifests.computePackageURLs().missing
        if !missing.isEmpty {
            if retryOnPackagePathMismatch {
                // Retry resolution which will most likely resolve correctly now since
                // we have the manifest files of all the dependencies.
                return try self.resolve(
                    root: root,
                    explicitProduct: explicitProduct,
                    forceResolution: forceResolution,
                    constraints: constraints,
                    diagnostics: diagnostics,
                    retryOnPackagePathMismatch: false,
                    resetPinsStoreOnFailure: resetPinsStoreOnFailure
                )
            } else if resetPinsStoreOnFailure, !pinsStore.pinsMap.isEmpty {
                // If we weren't able to resolve properly even after a retry, it
                // could mean that the dependency at fault has a different
                // version of the manifest file which contains dependencies that
                // have also changed their package references.
                pinsStore.unpinAll()
                try pinsStore.saveState()
                // try again with pins reset
                return try self.resolve(
                    root: root,
                    explicitProduct: explicitProduct,
                    forceResolution: forceResolution,
                    constraints: constraints,
                    diagnostics: diagnostics,
                    retryOnPackagePathMismatch: false,
                    resetPinsStoreOnFailure: false
                )
            } else {
                // give up
                let missing = missing.map{ $0.description }
                diagnostics.emit(error: "exhausted attempts to resolve the dependencies graph, with '\(missing.joined(separator: "', '"))' unresolved.")
                return updatedDependencyManifests
            }
        }

        self.pinAll(dependencyManifests: updatedDependencyManifests, pinsStore: pinsStore, diagnostics: diagnostics)

        let addedOrUpdatedPackages = packageStateChanges.compactMap({ $0.1.isAddedOrUpdated ? $0.0 : nil })
        try self.updateBinaryArtifacts(
            manifests: updatedDependencyManifests,
            addedOrUpdatedPackages: addedOrUpdatedPackages,
            diagnostics: diagnostics)

        return updatedDependencyManifests
    }


    /// Updates the current working checkouts i.e. clone or remove based on the
    /// provided dependency resolution result.
    ///
    /// - Parameters:
    ///   - updateResults: The updated results from dependency resolution.
    ///   - diagnostics: The diagnostics engine that reports errors, warnings
    ///     and notes.
    ///   - updateBranches: If the branches should be updated in case they're pinned.
    @discardableResult
    fileprivate func updateDependenciesCheckouts(
        root: PackageGraphRoot,
        updateResults: [(PackageReference, BoundVersion, ProductFilter)],
        updateBranches: Bool = false,
        diagnostics: DiagnosticsEngine
    ) -> [(PackageReference, PackageStateChange)] {
        // Get the update package states from resolved results.
        guard let packageStateChanges = diagnostics.wrap({
            try computePackageStateChanges(root: root, resolvedDependencies: updateResults, updateBranches: updateBranches)
        }) else {
            return []
        }

        // First remove the checkouts that are no longer required.
        for (packageRef, state) in packageStateChanges {
            diagnostics.wrap {
                switch state {
                case .added, .updated, .unchanged: break
                case .removed:
                    try remove(package: packageRef)
                }
            }
        }

        // Update or clone new packages.
        for (packageRef, state) in packageStateChanges {
            diagnostics.wrap {
                switch state {
                case .added(let state):
                    _ = try self.updateDependency(package: packageRef, requirement: state.requirement, productFilter: state.products)
                case .updated(let state):
                    _ = try self.updateDependency(package: packageRef, requirement: state.requirement, productFilter: state.products)
                case .removed, .unchanged: break
                }
            }
        }

        // Inform the delegate if nothing was updated.
        if packageStateChanges.filter({ $0.1 == .unchanged }).count == packageStateChanges.count {
            delegate?.dependenciesUpToDate()
        }

        return packageStateChanges
    }

    private func updateDependency(
        package: PackageReference,
        requirement: PackageStateChange.Requirement,
        productFilter: ProductFilter
    ) throws -> AbsolutePath {
        let checkoutState: CheckoutState

        switch requirement {
        case .version(let version):
            // FIXME: We need to get the revision here, and we don't have a
            // way to get it back out of the resolver which is very
            // annoying. Maybe we should make an SPI on the provider for
            // this?
            // FIXME: this should not block
            // FIXME: this should be updated to support registry
            guard let container = (try temp_await {
                self.getContainer(for: package, skipUpdate: true, on: .sharedConcurrent, completion: $0)
            }) as? SourceControlPackageContainer else {
                throw InternalError("invalid container for \(package) expected a RepositoryPackageContainer")
            }
            guard let tag = container.getTag(for: version) else {
                throw InternalError("unable to get tag for \(package) \(version); available versions \(try container.versionsDescending())")
            }
            let revision = try container.getRevision(forTag: tag)
            checkoutState = .version(version, revision: revision)

        case .revision(let revision, .none):
            checkoutState = .revision(revision)

        case .revision(let revision, .some(let branch)):
            checkoutState = .branch(name: branch, revision: revision)

        case .unversioned:
            self.state.dependencies.add(ManagedDependency.local(packageRef: package))
            try self.state.save()
            return AbsolutePath(package.location)
        }

        return try self.retrieve(package: package, at: checkoutState)
    }

    public enum ResolutionPrecomputationResult: Equatable {
        case required(reason: WorkspaceResolveReason)
        case notRequired

        public var isRequired: Bool {
            switch self {
            case .required: return true
            case .notRequired: return false
            }
        }
    }

    /// Computes if dependency resolution is required based on input constraints and pins.
    ///
    /// - Returns: Returns a result defining whether dependency resolution is required and the reason for it.
    // @testable internal
    public func precomputeResolution(
        root: PackageGraphRoot,
        dependencyManifests: DependencyManifests,
        pinsStore: PinsStore,
        constraints: [PackageContainerConstraint]
    ) throws -> ResolutionPrecomputationResult {
        let computedConstraints =
            try root.constraints() +
            // Include constraints from the manifests in the graph root.
            root.manifests.values.flatMap{ try $0.dependencyConstraints(productFilter: .everything) } +
            dependencyManifests.dependencyConstraints() +
            constraints

        let precomputationProvider = ResolverPrecomputationProvider(root: root, dependencyManifests: dependencyManifests)
        let resolver = PubgrubDependencyResolver(provider: precomputationProvider, pinsMap: pinsStore.pinsMap)
        let result = resolver.solve(constraints: computedConstraints)

        switch result {
        case .success:
            return .notRequired
        case .failure(ResolverPrecomputationError.missingPackage(let package)):
            return .required(reason: .newPackages(packages: [package]))
        case .failure(ResolverPrecomputationError.differentRequirement(let package, let state, let requirement)):
            return .required(reason: .packageRequirementChange(
                package: package,
                state: state,
                requirement: requirement
            ))
        default:
            return .required(reason: .other)
        }
    }

    /// Validates that each checked out managed dependency has an entry in pinsStore.
    private func validatePinsStore(dependencyManifests: DependencyManifests, diagnostics: DiagnosticsEngine) {
        guard let pinsStore = diagnostics.wrap({ try pinsStore.load() }) else {
            return
        }

        let pins = pinsStore.pinsMap.keys
        let requiredURLs = dependencyManifests.computePackageURLs().required

        for dependency in self.state.dependencies {
            switch dependency.state {
            case .checkout: break
            case .edited, .local: continue
            }

            let identity = dependency.packageRef.identity

            if requiredURLs.contains(where: { $0.location == dependency.packageRef.location }) {
                // If required identity contains this dependency, it should be in the pins store.
                if let pin = pinsStore.pinsMap[identity], pin.packageRef.location == dependency.packageRef.location {
                    continue
                }
            } else if !pins.contains(identity) {
                // Otherwise, it should *not* be in the pins store.
                continue
            }

            return self.pinAll(dependencyManifests: dependencyManifests, pinsStore: pinsStore, diagnostics: diagnostics)
        }
    }

    /// This enum represents state of an external package.
    public enum PackageStateChange: Equatable, CustomStringConvertible {

        /// The requirement imposed by the the state.
        public enum Requirement: Equatable, CustomStringConvertible {
            /// A version requirement.
            case version(Version)

            /// A revision requirement.
            case revision(Revision, branch: String?)

            case unversioned

            public var description: String {
                switch self {
                case .version(let version):
                    return "requirement(\(version))"
                case .revision(let revision, let branch):
                    return "requirement(\(revision) \(branch ?? ""))"
                case .unversioned:
                    return "requirement(unversioned)"
                }
            }

            public var prettyPrinted: String {
                switch self {
                case .version(let version):
                    return "\(version)"
                case .revision(let revision, let branch):
                    return "\(revision) \(branch ?? "")"
                case .unversioned:
                    return "unversioned"
                }
            }
        }
        public struct State: Equatable {
            public let requirement: Requirement
            public let products: ProductFilter
            public init(requirement: Requirement, products: ProductFilter) {
                self.requirement = requirement
                self.products = products
            }
        }

        /// The package is added.
        case added(State)

        /// The package is removed.
        case removed

        /// The package is unchanged.
        case unchanged

        /// The package is updated.
        case updated(State)

        public var description: String {
            switch self {
            case .added(let requirement):
                return "added(\(requirement))"
            case .removed:
                return "removed"
            case .unchanged:
                return "unchanged"
            case .updated(let requirement):
                return "updated(\(requirement))"
            }
        }

        public var isAddedOrUpdated: Bool {
            switch self {
            case .added, .updated:
                return true
            case .unchanged, .removed:
                return false
            }
        }
    }

    /// Computes states of the packages based on last stored state.
    fileprivate func computePackageStateChanges(
        root: PackageGraphRoot,
        resolvedDependencies: [(PackageReference, BoundVersion, ProductFilter)],
        updateBranches: Bool
    ) throws -> [(PackageReference, PackageStateChange)] {
        // Load pins store and managed dependencies.
        let pinsStore = try self.pinsStore.load()
        var packageStateChanges: [PackageIdentity: (PackageReference, PackageStateChange)] = [:]

        // Set the states from resolved dependencies results.
        for (packageRef, binding, products) in resolvedDependencies {
            // Get the existing managed dependency for this package ref, if any.

            // first find by identity only since edit location may be different by design
            var currentDependency = self.state.dependencies[packageRef.identity]
            // Check if this is an edited dependency.
            if case .edited(let basedOn, _) = currentDependency?.state, let originalReference = basedOn?.packageRef {
                packageStateChanges[originalReference.identity] = (originalReference, .unchanged)
            } else {
                // if not edited, also compare by location since it may have changed
                currentDependency = self.state.dependencies[comparingLocation: packageRef]
            }

            switch binding {
            case .excluded:
                throw InternalError("Unexpected excluded binding")

            case .unversioned:
                // Ignore the root packages.
                if root.packages.keys.contains(packageRef.identity) {
                    continue
                }

                if let currentDependency = currentDependency {
                    switch currentDependency.state {
                    case .local, .edited:
                        packageStateChanges[packageRef.identity] = (packageRef, .unchanged)
                    case .checkout:
                        let newState = PackageStateChange.State(requirement: .unversioned, products: products)
                        packageStateChanges[packageRef.identity] = (packageRef, .updated(newState))
                    }
                } else {
                    let newState = PackageStateChange.State(requirement: .unversioned, products: products)
                    packageStateChanges[packageRef.identity] = (packageRef, .added(newState))
                }

            case .revision(let identifier, let branch):
                // Get the latest revision from the container.
                // TODO: replace with async/await when available
                guard let container = (try temp_await {
                    self.getContainer(for: packageRef, skipUpdate: true, on: .sharedConcurrent, completion: $0)
                }) as? SourceControlPackageContainer else {
                    throw InternalError("invalid container for \(packageRef) expected a RepositoryPackageContainer")
                }
                var revision = try container.getRevision(forIdentifier: identifier)
                let branch = branch ?? (identifier == revision.identifier ? nil : identifier)

                // If we have a branch and we shouldn't be updating the
                // branches, use the revision from pin instead (if present).
                if branch != nil, !updateBranches {
                    if case .branch(branch, let pinRevision) = pinsStore.pins.first(where: { $0.packageRef == packageRef })?.state {
                        revision = pinRevision
                    }
                }

                // First check if we have this dependency.
                if let currentDependency = currentDependency {
                    // If current state and new state are equal, we don't need
                    // to do anything.
                    let newState: CheckoutState
                    if let branch = branch {
                        newState = .branch(name: branch, revision: revision)
                    } else {
                        newState = .revision(revision)
                    }
                    if case .checkout(let checkoutState) = currentDependency.state, checkoutState == newState {
                        packageStateChanges[packageRef.identity] = (packageRef, .unchanged)
                    } else {
                        // Otherwise, we need to update this dependency to this revision.
                        let newState = PackageStateChange.State(requirement: .revision(revision, branch: branch), products: products)
                        packageStateChanges[packageRef.identity] = (packageRef, .updated(newState))
                    }
                } else {
                    let newState = PackageStateChange.State(requirement: .revision(revision, branch: branch), products: products)
                    packageStateChanges[packageRef.identity] = (packageRef, .added(newState))
                }

            case .version(let version):
                if let currentDependency = currentDependency {
                    if case .checkout(let checkoutState) = currentDependency.state, case .version(version, _) = checkoutState {
                        packageStateChanges[packageRef.identity] = (packageRef, .unchanged)
                    } else {
                        let newState = PackageStateChange.State(requirement: .version(version), products: products)
                        packageStateChanges[packageRef.identity] = (packageRef, .updated(newState))
                    }
                } else {
                    let newState = PackageStateChange.State(requirement: .version(version), products: products)
                    packageStateChanges[packageRef.identity] = (packageRef, .added(newState))
                }
            }
        }
        // Set the state of any old package that might have been removed.
        for packageRef in self.state.dependencies.lazy.map({ $0.packageRef }) where packageStateChanges[packageRef.identity] == nil {
            packageStateChanges[packageRef.identity] = (packageRef, .removed)
        }

        return Array(packageStateChanges.values)
    }

    /// Creates resolver for the workspace.
    fileprivate func createResolver(pinsMap: PinsStore.PinsMap) throws -> PubgrubDependencyResolver {
        var delegates = [DependencyResolverDelegate]()
        if let workspaceDelegate = self.delegate {
            delegates.append(WorkspaceDependencyResolverDelegate(workspaceDelegate))
        }
        if self.resolverTracingEnabled {
            delegates.append(try TracingDependencyResolverDelegate(path: self.location.workingDirectory.appending(components: "resolver.trace")))
        }
        let delegate = !delegates.isEmpty ? MultiplexResolverDelegate(delegates) : nil

        return PubgrubDependencyResolver(
            provider: self,
            pinsMap: pinsMap,
            updateEnabled: self.resolverUpdateEnabled,
            prefetchingEnabled: self.resolverPrefetchingEnabled,
            delegate: delegate
        )
    }

    /// Runs the dependency resolver based on constraints provided and returns the results.
    fileprivate func resolveDependencies(
        resolver: PubgrubDependencyResolver,
        constraints: [PackageContainerConstraint],
        diagnostics: DiagnosticsEngine
    ) -> [(package: PackageReference, binding: BoundVersion, products: ProductFilter)] {

        os_signpost(.begin, log: .swiftpm, name: SignpostName.resolution)
        let result = resolver.solve(constraints: constraints)
        os_signpost(.end, log: .swiftpm, name: SignpostName.resolution)

        // Take an action based on the result.
        switch result {
        case .success(let bindings):
            return bindings
        case .failure(let error):
            diagnostics.emit(error)
            return []
        }
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
    public func loadResult() -> Result<Value, Error> {
        return Result(catching: {
            try self.construct()
        })
    }

    /// Load and return the value.
    public func load() throws -> Value {
        return try loadResult().get()
    }
}

private struct RemoteArtifact {
    let packageRef: PackageReference
    let targetName: String
    let url: Foundation.URL
    let checksum: String
}

private struct ArchiveIndexFile: Decodable {
    let schemaVersion: String
    let archives: [Archive]

    struct Archive: Decodable {
        let fileName: String
        let checksum: String
        let supportedTriples: [Triple]

        enum CodingKeys: String, CodingKey {
            case fileName
            case checksum
            case supportedTriples
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.fileName = try container.decode(String.self, forKey: .fileName)
            self.checksum = try container.decode(String.self, forKey: .checksum)
            self.supportedTriples = try container.decode([String].self, forKey: .supportedTriples).map(Triple.init)
        }
    }
}

// MARK: - Package container provider

extension Workspace: PackageContainerProvider {
    public func getContainer(
        for package: PackageReference,
        skipUpdate: Bool,
        on queue: DispatchQueue,
        completion: @escaping (Result<PackageContainer, Swift.Error>) -> Void
    ) {
        switch package.kind {
        case .root, .fileSystem:
            queue.async {
                // If the container is local, just create and return a local package container.
                do {
                    let container = try FileSystemPackageContainer(
                        package: package,
                        identityResolver: self.identityResolver,
                        manifestLoader: self.manifestLoader,
                        toolsVersionLoader: self.toolsVersionLoader,
                        currentToolsVersion: self.currentToolsVersion,
                        fileSystem: self.fileSystem)
                    completion(.success(container))
                } catch {
                    completion(.failure(error))
                }
            }
        case .localSourceControl, .remoteSourceControl:
            // Resolve the container using the repository manager.
            do {
                let repositorySpecifier = try package.makeRepositorySpecifier()
                repositoryManager.lookup(repository: repositorySpecifier, skipUpdate: skipUpdate, on: queue) { result in
                    queue.async {
                        // Create the container wrapper.
                        let result = result.tryMap { handle -> PackageContainer in
                            // Open the repository.
                            //
                            // FIXME: Do we care about holding this open for the lifetime of the container.
                            let repository = try handle.open()
                            return try SourceControlPackageContainer(
                                package: package,
                                identityResolver: self.identityResolver,
                                repositorySpecifier: repositorySpecifier,
                                repository: repository,
                                manifestLoader: self.manifestLoader,
                                toolsVersionLoader: self.toolsVersionLoader,
                                currentToolsVersion: self.currentToolsVersion
                            )
                        }
                        completion(result)
                    }
                }
            } catch {
                queue.async {
                    completion(.failure(error))
                }
            }
        case .registry:
            fatalError("registry dependencies are supported at this point")
        }
    }

    /// Retrieves the given `package` at a given `checkoutState`.
    ///
    /// - Parameters:
    ///   - package: The package to retrieve.
    ///   - checkoutState: The state to retrieve at.
    /// - Returns: The path of the local copy of the package.
    func retrieve(package: PackageReference, at checkoutState: CheckoutState) throws -> AbsolutePath {
        switch package.kind {
        case .root, .fileSystem:
            fatalError("local dependencies are supported")
        case .localSourceControl, .remoteSourceControl:
            return try self.checkoutRepository(package: package, at: checkoutState)
        case .registry:
            fatalError("registry dependencies are supported at this point")
        }
    }

    /// Removes the clone and checkout of the provided specifier.
    ///
    /// - Parameters:
    ///   - package: The package to remove
    func remove(package: PackageReference) throws {
        guard let dependency = self.state.dependencies[package.identity] else {
            throw InternalError("trying to remove \(package.identity) which isn't in workspace")
        }

        // We only need to update the managed dependency structure to "remove"
        // a local package.
        //
        // Note that we don't actually remove a local package from disk.
        switch dependency.state {
        case .local:
            self.state.dependencies.remove(package.identity)
            try self.state.save()
            return
        case .checkout, .edited:
            break
        }

        // Inform the delegate.
        delegate?.removing(repository: dependency.packageRef.location)

        // Compute the dependency which we need to remove.
        let dependencyToRemove: ManagedDependency

        if case .edited(let _basedOn, let unmanagedPath) = dependency.state, let basedOn = _basedOn {
            // Remove the underlying dependency for edited packages.
            dependencyToRemove = basedOn
            let updatedDependency = Workspace.ManagedDependency.edited(
                packageRef: dependency.packageRef,
                subpath: dependency.subpath,
                basedOn: .none,
                unmanagedPath: unmanagedPath
            )
            self.state.dependencies.add(updatedDependency)
        } else {
            dependencyToRemove = dependency
            self.state.dependencies.remove(dependencyToRemove.packageRef.identity)
        }

        switch package.kind {
        case .root, .fileSystem:
            fatalError("local dependencies are supported")
        case .localSourceControl, .remoteSourceControl:
            try self.removeRepository(dependency: dependencyToRemove)
        case .registry:
            fatalError("registry dependencies are supported at this point")
        }

        // Save the state.
        try self.state.save()
    }
}

// MARK: - Repository management

// FIXME: this mixes quite a bit of workspace logic with repository specific one
// need to better separate the concerns
extension Workspace {
    /// Create a local clone of the given `repository` checked out to `checkoutState`.
    ///
    /// If an existing clone is present, the repository will be reset to the
    /// requested revision, if necessary.
    ///
    /// - Parameters:
    ///   - package: The package to clone.
    ///   - checkoutState: The state to check out.
    /// - Returns: The path of the local repository.
    /// - Throws: If the operation could not be satisfied.
    func checkoutRepository(package: PackageReference, at checkoutState: CheckoutState) throws -> AbsolutePath {
        // first fetch the repository.
        let path = try self.fetchRepository(package: package)

        // Check out the given revision.
        let workingCopy = try self.repositoryManager.openWorkingCopy(at: path)

        // Inform the delegate.
        delegate?.willCheckOut(repository: package.location, revision: checkoutState.description, at: path)

        // Do mutable-immutable dance because checkout operation modifies the disk state.
        try fileSystem.chmod(.userWritable, path: path, options: [.recursive, .onlyFiles])
        try workingCopy.checkout(revision: checkoutState.revision)
        try? fileSystem.chmod(.userUnWritable, path: path, options: [.recursive, .onlyFiles])

        // Write the state record.
        self.state.dependencies.add(.remote(
            packageRef: package,
            state: checkoutState,
            subpath: path.relative(to: self.location.repositoriesCheckoutsDirectory)
        ))
        try self.state.save()

        delegate?.didCheckOut(repository: package.location, revision: checkoutState.description, at: path, error: nil)

        return path
    }

    /// Fetch a given `package` and create a local checkout for it.
    ///
    /// This will first clone the repository into the canonical repositories
    /// location, if necessary, and then check it out from there.
    ///
    /// - Returns: The path of the local repository.
    /// - Throws: If the operation could not be satisfied.
    private func fetchRepository(package: PackageReference) throws -> AbsolutePath {
        // If we already have it, fetch to update the repo from its remote.
        // also compare the location as it may have changed
        if let dependency = self.state.dependencies[comparingLocation: package] {
            let path = self.location.repositoriesCheckoutsDirectory.appending(dependency.subpath)

            // Make sure the directory is not missing (we will have to clone again
            // if not).
            fetch: if self.fileSystem.isDirectory(path) {
                // Fetch the checkout in case there are updates available.
                let workingCopy = try self.repositoryManager.openWorkingCopy(at: path)

                // Ensure that the alternative object store is still valid.
                //
                // This can become invalid if the build directory is moved.
                guard workingCopy.isAlternateObjectStoreValid() else {
                    break fetch
                }

                // The fetch operation may update contents of the checkout, so
                // we need do mutable-immutable dance.
                try self.fileSystem.chmod(.userWritable, path: path, options: [.recursive, .onlyFiles])
                try workingCopy.fetch()
                try? self.fileSystem.chmod(.userUnWritable, path: path, options: [.recursive, .onlyFiles])

                return path
            }
        }

        // If not, we need to get the repository from the checkouts.
        let repository = try package.makeRepositorySpecifier()
        // FIXME: this should not block
        let handle = try temp_await {
            self.repositoryManager.lookup(repository: repository, skipUpdate: true, on: .sharedConcurrent, completion: $0)
        }

        // Clone the repository into the checkouts.
        let path = self.location.repositoriesCheckoutsDirectory.appending(component: repository.basename)

        try self.fileSystem.chmod(.userWritable, path: path, options: [.recursive, .onlyFiles])
        try self.fileSystem.removeFileTree(path)

        // Inform the delegate that we're starting cloning.
        self.delegate?.willCreateWorkingCopy(repository: handle.repository.url, at: path)
        _ = try handle.createWorkingCopy(at: path, editable: false)
        self.delegate?.didCreateWorkingCopy(repository: handle.repository.url, at: path, error: nil)

        return path
    }

    /// Removes the clone and checkout of the provided specifier.
    fileprivate func removeRepository(dependency: ManagedDependency) throws {
        // Remove the checkout.
        let dependencyPath = self.location.repositoriesCheckoutsDirectory.appending(dependency.subpath)
        let workingCopy = try self.repositoryManager.openWorkingCopy(at: dependencyPath)
        guard !workingCopy.hasUncommittedChanges() else {
            throw WorkspaceDiagnostics.UncommitedChanges(repositoryPath: dependencyPath)
        }

        try self.fileSystem.chmod(.userWritable, path: dependencyPath, options: [.recursive, .onlyFiles])
        try self.fileSystem.removeFileTree(dependencyPath)

        // Remove the clone.
        try self.repositoryManager.remove(repository: dependency.packageRef.makeRepositorySpecifier())
    }
}


// MARK: - Utility extensions

fileprivate extension Workspace.ManagedArtifact {
    var originURL: String? {
        switch self.source {
        case .remote(let url, _):
            return url
        case .local:
            return nil
        }
    }

    func kind() throws -> BinaryTarget.Kind {
        return try BinaryTarget.Kind.forFileExtension(self.path.extension ?? "unknown")
    }
}

// FIXME: the manifest loading logic should be changed to use identity instead of location once identity is unique
// at that time we should remove this
//@available(*, deprecated)
fileprivate extension PackageDependency {
    var location: String {
        switch self {
        case .fileSystem(let settings):
            return settings.path.pathString
        case .sourceControl(let settings):
            switch settings.location {
            case .local(let path):
                return path.pathString
            case .remote(let url):
                return url.absoluteString
            }
        case .registry:
            // FIXME: placeholder
            return self.identity.description
        }
    }
}

fileprivate extension DiagnosticsEngine {
    func append(contentsOf other: DiagnosticsEngine) {
        for diagnostic in other.diagnostics {
            self.emit(diagnostic.message, location: diagnostic.location)
        }
    }
}

internal extension PackageReference {
    func makeRepositorySpecifier() throws -> RepositorySpecifier {
        switch self.kind {
        case .localSourceControl(let path):
            return .init(path: path)
        case .remoteSourceControl(let url):
            return .init(url: url)
        default:
            throw StringError("invalid dependency kind \(self.kind)")
        }
    }
}

// FIXME: remove this when remove the single call site that uses it
fileprivate extension PackageDependency {
    var isLocal: Bool {
        switch self {
        case .fileSystem:
            return true
        case .sourceControl:
            return false
        case .registry:
            return false
        }
    }
}

extension Workspace {
    public static func format(workspaceResolveReason reason: WorkspaceResolveReason) -> String {
        var result = "Running resolver because "

        switch reason {
        case .forced:
            result.append("it was forced")
        case .newPackages(let packages):
            let dependencies = packages.lazy.map({ "'\($0.location)'" }).joined(separator: ", ")
            result.append("the following dependencies were added: \(dependencies)")
        case .packageRequirementChange(let package, let state, let requirement):
            result.append("dependency '\(package.name)' was ")

            switch state {
            case .checkout(let checkoutState)?:
                switch checkoutState.requirement {
                case .versionSet(.exact(let version)):
                    result.append("resolved to '\(version)'")
                case .versionSet(_):
                    // Impossible
                    break
                case .revision(let revision):
                    result.append("resolved to '\(revision)'")
                case .unversioned:
                    result.append("unversioned")
                }
            case .edited?:
                result.append("edited")
            case .local?:
                result.append("versioned")
            case nil:
                result.append("root")
            }

            result.append(" but now has a ")

            switch requirement {
            case .versionSet:
                result.append("different version-based")
            case .revision:
                result.append("different revision-based")
            case .unversioned:
                result.append("unversioned")
            }

            result.append(" requirement.")
        default:
            result.append(" requirements have changed.")
        }

        return result
    }
}
