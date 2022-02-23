/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import ArgumentParser
import Basics
import Build
import Dispatch
import class Foundation.ProcessInfo
import OrderedCollections
import PackageGraph
import PackageLoading
import PackageModel
import SourceControl
import SPMBuildCore
import TSCBasic
import Workspace
import XCBuildSupport

#if os(Windows)
import WinSDK
#elseif os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
import Darwin
#else
import Glibc
#endif

import protocol TSCUtility.ProgressAnimationProtocol
import class TSCUtility.NinjaProgressAnimation
import class TSCUtility.PercentProgressAnimation
import var TSCUtility.verbosity

typealias Diagnostic = Basics.Diagnostic

private class ToolWorkspaceDelegate: WorkspaceDelegate {
    /// The stream to use for reporting progress.
    private let outputStream: ThreadSafeOutputByteStream

    /// The progress animation for downloads.
    private let binaryDownloadAnimation: NinjaProgressAnimation

    /// The progress animation for repository fetches.
    private let fetchAnimation: NinjaProgressAnimation

    /// Logging level
    private let logLevel: Diagnostic.Severity

    private struct DownloadProgress {
        let bytesDownloaded: Int64
        let totalBytesToDownload: Int64
    }

    private struct FetchProgress {
        let progress: Int64
        let total: Int64
    }

    /// The progress of binary downloads.
    private var binaryDownloadProgress = OrderedCollections.OrderedDictionary<String, DownloadProgress>()

    /// The progress of package  fetch operations.
    private var fetchProgress = OrderedCollections.OrderedDictionary<PackageIdentity, FetchProgress>()

    private let queue = DispatchQueue(label: "org.swift.swiftpm.commands.tool-workspace-delegate")

    private let observabilityScope: ObservabilityScope

    init(_ outputStream: OutputByteStream, logLevel: Diagnostic.Severity, observabilityScope: ObservabilityScope) {
        // FIXME: Implement a class convenience initializer that does this once they are supported
        // https://forums.swift.org/t/allow-self-x-in-class-convenience-initializers/15924
        self.outputStream = outputStream as? ThreadSafeOutputByteStream ?? ThreadSafeOutputByteStream(outputStream)
        self.binaryDownloadAnimation = NinjaProgressAnimation(stream: self.outputStream)
        self.fetchAnimation = NinjaProgressAnimation(stream: self.outputStream)
        self.logLevel = logLevel
        self.observabilityScope = observabilityScope
    }

    func willFetchPackage(package: PackageIdentity, packageLocation: String?, fetchDetails: PackageFetchDetails) {
        queue.async {
            self.outputStream <<< "Fetching \(packageLocation ?? package.description)"
            if fetchDetails.fromCache {
                self.outputStream <<< " from cache"
            }
            self.outputStream <<< "\n"
            self.outputStream.flush()
        }
    }

    func didFetchPackage(package: PackageIdentity, packageLocation: String?, result: Result<PackageFetchDetails, Error>, duration: DispatchTimeInterval) {
        queue.async {
            guard case .success = result, !self.observabilityScope.errorsReported else {
                self.fetchAnimation.clear()
                return
            }

            let progress = self.fetchProgress.values.reduce(0) { $0 + $1.progress }
            let total = self.fetchProgress.values.reduce(0) { $0 + $1.total }

            if progress == total && !self.fetchProgress.isEmpty {
                self.fetchAnimation.clear()
                self.fetchProgress.removeAll()
            } else {
                self.fetchProgress[package] = nil
            }

            self.outputStream <<< "Fetched \(packageLocation ?? package.description) (\(duration.descriptionInSeconds))"
            self.outputStream <<< "\n"
            self.outputStream.flush()
        }
    }

    func fetchingPackage(package: PackageIdentity, packageLocation: String?, progress: Int64, total: Int64?) {
        queue.async {
            self.fetchProgress[package] = FetchProgress(
                progress: progress,
                total: total ?? progress
            )

            let progress = self.fetchProgress.values.reduce(0) { $0 + $1.progress }
            let total = self.fetchProgress.values.reduce(0) { $0 + $1.total }
            let packages = self.fetchProgress.keys.map { $0.description }.joined(separator: ", ")
            self.fetchAnimation.update(
                step: progress > Int.max ? Int.max : Int(progress),
                total: total > Int.max ? Int.max : Int(total),
                text: "Fetching \(packages)"
            )
        }
    }

    func willUpdateRepository(package: PackageIdentity, repository url: String) {
        queue.async {
            self.outputStream <<< "Updating \(url)"
            self.outputStream <<< "\n"
            self.outputStream.flush()
        }
    }

    func didUpdateRepository(package: PackageIdentity, repository url: String, duration: DispatchTimeInterval) {
        queue.async {
            self.outputStream <<< "Updated \(url) (\(duration.descriptionInSeconds))"
            self.outputStream <<< "\n"
            self.outputStream.flush()
        }
    }

    func dependenciesUpToDate() {
        queue.async {
            self.outputStream <<< "Everything is already up-to-date"
            self.outputStream <<< "\n"
            self.outputStream.flush()
        }
    }

    func willCreateWorkingCopy(package: PackageIdentity, repository url: String, at path: AbsolutePath) {
        queue.async {
            self.outputStream <<< "Creating working copy for \(url)"
            self.outputStream <<< "\n"
            self.outputStream.flush()
        }
    }

    func didCheckOut(package: PackageIdentity, repository url: String, revision: String, at path: AbsolutePath) {
        queue.async {
            self.outputStream <<< "Working copy of \(url) resolved at \(revision)"
            self.outputStream <<< "\n"
            self.outputStream.flush()
        }
    }

    func removing(package: PackageIdentity, packageLocation: String?) {
        queue.async {
            self.outputStream <<< "Removing \(packageLocation ?? package.description)"
            self.outputStream <<< "\n"
            self.outputStream.flush()
        }
    }

    func willResolveDependencies(reason: WorkspaceResolveReason) {
        guard self.logLevel <= .info else {
            return
        }

        queue.sync {
            self.outputStream <<< Workspace.format(workspaceResolveReason: reason)
            self.outputStream <<< "\n"
            self.outputStream.flush()
        }
    }

    func willComputeVersion(package: PackageIdentity, location: String) {
        queue.async {
            self.outputStream <<< "Computing version for \(location)"
            self.outputStream <<< "\n"
            self.outputStream.flush()
        }
    }

    func didComputeVersion(package: PackageIdentity, location: String, version: String, duration: DispatchTimeInterval) {
        queue.async {
            self.outputStream <<< "Computed \(location) at \(version) (\(duration.descriptionInSeconds))"
            self.outputStream <<< "\n"
            self.outputStream.flush()
        }
    }

    func willDownloadBinaryArtifact(from url: String) {
        queue.async {
            self.outputStream <<< "Downloading binary artifact \(url)"
            self.outputStream <<< "\n"
            self.outputStream.flush()
        }
    }

    func didDownloadBinaryArtifact(from url: String, result: Result<AbsolutePath, Error>, duration: DispatchTimeInterval) {
        queue.async {
            guard case .success = result, !self.observabilityScope.errorsReported else {
                self.binaryDownloadAnimation.clear()
                return
            }

            let progress = self.binaryDownloadProgress.values.reduce(0) { $0 + $1.bytesDownloaded }
            let total = self.binaryDownloadProgress.values.reduce(0) { $0 + $1.totalBytesToDownload }

            if progress == total && !self.binaryDownloadProgress.isEmpty {
                self.binaryDownloadAnimation.clear()
                self.binaryDownloadProgress.removeAll()
            } else {
                self.binaryDownloadProgress[url] = nil
            }

            self.outputStream <<< "Downloaded \(url) (\(duration.descriptionInSeconds))"
            self.outputStream <<< "\n"
            self.outputStream.flush()
        }
    }

    func downloadingBinaryArtifact(from url: String, bytesDownloaded: Int64, totalBytesToDownload: Int64?) {
        queue.async {
            self.binaryDownloadProgress[url] = DownloadProgress(
                bytesDownloaded: bytesDownloaded,
                totalBytesToDownload: totalBytesToDownload ?? bytesDownloaded
            )

            let step = self.binaryDownloadProgress.values.reduce(0, { $0 + $1.bytesDownloaded })
            let total = self.binaryDownloadProgress.values.reduce(0, { $0 + $1.totalBytesToDownload })
            let artifacts = self.binaryDownloadProgress.keys.joined(separator: ", ")
            self.binaryDownloadAnimation.update(
                step: step > Int.max ? Int.max : Int(step > 1024 ? step / 1024 : step),
                total: total > Int.max ? Int.max : Int(total > 1024 ? total / 1024 : total),
                text: "Downloading \(artifacts)"
            )
        }
    }

    // noop

    func willLoadManifest(packagePath: AbsolutePath, url: String, version: Version?, packageKind: PackageReference.Kind) {}
    func didLoadManifest(packagePath: AbsolutePath, url: String, version: Version?, packageKind: PackageReference.Kind, manifest: Manifest?, diagnostics: [Basics.Diagnostic]) {}
    func willCheckOut(package: PackageIdentity, repository url: String, revision: String, at path: AbsolutePath) {}
    func didCreateWorkingCopy(package: PackageIdentity, repository url: String, at path: AbsolutePath) {}
    func resolvedFileChanged() {}
    func didDownloadAllBinaryArtifacts() {}
}

protocol SwiftCommand: ParsableCommand {
    var swiftOptions: SwiftToolOptions { get }

    func run(_ swiftTool: SwiftTool) throws
}

extension SwiftCommand {
    public func run() throws {
        let swiftTool = try SwiftTool(options: swiftOptions)
        try self.run(swiftTool)
        if swiftTool.observabilityScope.errorsReported || swiftTool.executionStatus == .failure {
            throw ExitCode.failure
        }
    }

    public static var _errorLabel: String { "error" }
}

public class SwiftTool {
    #if os(Windows)
    // unfortunately this is needed for C callback handlers used by Windows shutdown handler
    static var shutdownRegistry: (processSet: ProcessSet, buildSystemRef: BuildSystemRef)?
    #endif

    /// The original working directory.
    let originalWorkingDirectory: AbsolutePath

    /// The options of this tool.
    let options: SwiftToolOptions

    /// Path to the root package directory, nil if manifest is not found.
    let packageRoot: AbsolutePath?

    /// Helper function to get package root or throw error if it is not found.
    func getPackageRoot() throws -> AbsolutePath {
        guard let packageRoot = packageRoot else {
            throw StringError("Could not find \(Manifest.filename) in this directory or any of its parent directories.")
        }
        return packageRoot
    }

    /// Get the current workspace root object.
    func getWorkspaceRoot() throws -> PackageGraphRootInput {
        let packages: [AbsolutePath]

        if let workspace = options.multirootPackageDataFile {
            packages = try XcodeWorkspaceLoader(fileSystem: self.fileSystem, observabilityScope: self.observabilityScope).load(workspace: workspace)
        } else {
            packages = [try getPackageRoot()]
        }

        return PackageGraphRootInput(packages: packages)
    }

    /// Path to the build directory.
    let buildPath: AbsolutePath

    /// Path to the shared security directory
    let sharedSecurityDirectory: AbsolutePath?

    /// Path to the shared cache directory
    let sharedCacheDirectory: AbsolutePath?

    /// Path to the shared configuration directory
    let sharedConfigurationDirectory: AbsolutePath?

    /// The process set to hold the launched processes. These will be terminated on any signal
    /// received by the swift tools.
    let processSet: ProcessSet

    /// The current build system reference. The actual reference is present only during an active build.
    let buildSystemRef: BuildSystemRef

    /// The execution status of the tool.
    var executionStatus: ExecutionStatus = .success

    /// Holds the currently active workspace.
    ///
    /// It is not initialized in init() because for some of the commands like package init , usage etc,
    /// workspace is not needed, in-fact it would be an error to ask for the workspace object
    /// for package init because the Manifest file should *not* present.
    private var _workspace: Workspace?
    private var _workspaceDelegate: ToolWorkspaceDelegate?

    private let observabilityHandler: SwiftToolObservabilityHandler

    /// The observability scope to emit diagnostics event on
    let observabilityScope: ObservabilityScope

    /// The min severity at which to log diagnostics
    let logLevel: Diagnostic.Severity

    /// The file system in use
    let fileSystem: FileSystem

    /// Create an instance of this tool.
    ///
    /// - parameter options: The command line options to be passed to this tool.
    public convenience init(options: SwiftToolOptions) throws {
        // output from background activities goes to stderr, this includes diagnostics and output from build operations,
        // package resolution that take place as part of another action
        // CLI commands that have user facing output, use stdout directly to emit the final result
        // this means that the build output from "swift build" goes to stdout
        // but the build output from "swift test" goes to stderr, while the tests output go to stdout
        try self.init(outputStream: TSCBasic.stderrStream, options: options)
    }

    // marked internal for testing
    internal init(outputStream: OutputByteStream, options: SwiftToolOptions) throws {
        self.fileSystem = localFileSystem
        // first, bootstrap the observability system
        self.logLevel = options.logLevel
        self.observabilityHandler = SwiftToolObservabilityHandler(outputStream: outputStream, logLevel: self.logLevel)
        let observabilitySystem = ObservabilitySystem(self.observabilityHandler)
        self.observabilityScope = observabilitySystem.topScope

        // Capture the original working directory ASAP.
        guard let cwd = self.fileSystem.currentWorkingDirectory else {
            self.observabilityScope.emit(error: "couldn't determine the current working directory")
            throw ExitCode.failure
        }
        self.originalWorkingDirectory = cwd

        do {
            try Self.postprocessArgParserResult(options: options, observabilityScope: self.observabilityScope)
            self.options = options

            // Honor package-path option is provided.
            if let packagePath = options.packagePath ?? options.chdir {
                try ProcessEnv.chdir(packagePath)
            }

            let processSet = ProcessSet()
            let buildSystemRef = BuildSystemRef()

            #if os(Windows)
            // set shutdown handler to terminate sub-processes, etc
            SwiftTool.shutdownRegistry = (processSet: processSet, buildSystemRef: buildSystemRef)
            _ = SetConsoleCtrlHandler({ _ in
                // Terminate all processes on receiving an interrupt signal.
                DefaultPluginScriptRunner.cancelAllRunningPlugins()
                SwiftTool.shutdownRegistry?.processSet.terminate()
                SwiftTool.shutdownRegistry?.buildSystemRef.buildSystem?.cancel()

                // Reset the handler.
                _ = SetConsoleCtrlHandler(nil, false)

                // Exit as if by signal()
                TerminateProcess(GetCurrentProcess(), 3)

                return true
            }, true)
            #else
            // trap SIGINT to terminate sub-processes, etc
            signal(SIGINT, SIG_IGN)
            let interruptSignalSource = DispatchSource.makeSignalSource(signal: SIGINT)
            interruptSignalSource.setEventHandler {
                // cancel the trap?
                interruptSignalSource.cancel()

                // Terminate all processes on receiving an interrupt signal.
                DefaultPluginScriptRunner.cancelAllRunningPlugins()
                processSet.terminate()
                buildSystemRef.buildSystem?.cancel()

                #if os(macOS) || os(OpenBSD)
                // Install the default signal handler.
                var action = sigaction()
                action.__sigaction_u.__sa_handler = SIG_DFL
                sigaction(SIGINT, &action, nil)
                kill(getpid(), SIGINT)
                #elseif os(Android)
                // Install the default signal handler.
                var action = sigaction()
                action.sa_handler = SIG_DFL
                sigaction(SIGINT, &action, nil)
                kill(getpid(), SIGINT)
                #else
                var action = sigaction()
                action.__sigaction_handler = unsafeBitCast(
                    SIG_DFL,
                    to: sigaction.__Unnamed_union___sigaction_handler.self)
                sigaction(SIGINT, &action, nil)
                kill(getpid(), SIGINT)
                #endif
            }
            interruptSignalSource.resume()
            #endif

            self.processSet = processSet
            self.buildSystemRef = buildSystemRef

        } catch {
            self.observabilityScope.emit(error)
            throw ExitCode.failure
        }

        // Create local variables to use while finding build path to avoid capture self before init error.
        let customBuildPath = options.buildPath
        let packageRoot = findPackageRoot(fileSystem: fileSystem)

        self.packageRoot = packageRoot
        self.buildPath = getEnvBuildPath(workingDir: cwd) ??
        customBuildPath ??
        (packageRoot ?? cwd).appending(component: ".build")

        // make sure common directories are created
        self.sharedSecurityDirectory = try getSharedSecurityDirectory(options: self.options, fileSystem: fileSystem, observabilityScope: self.observabilityScope)
        self.sharedConfigurationDirectory = try getSharedConfigurationDirectory(options: self.options, fileSystem: fileSystem, observabilityScope: self.observabilityScope)
        self.sharedCacheDirectory = try getSharedCacheDirectory(options: self.options, fileSystem: fileSystem, observabilityScope: self.observabilityScope)

        // set global process logging handler
        Process.loggingHandler = { self.observabilityScope.emit(debug: $0) }
    }

    static func postprocessArgParserResult(options: SwiftToolOptions, observabilityScope: ObservabilityScope) throws {
        if options.chdir != nil {
            observabilityScope.emit(warning: "'--chdir/-C' option is deprecated; use '--package-path' instead")
        }

        if options.multirootPackageDataFile != nil {
            observabilityScope.emit(.unsupportedFlag("--multiroot-data-file"))
        }

        if options.useExplicitModuleBuild && !options.useIntegratedSwiftDriver {
            observabilityScope.emit(error: "'--experimental-explicit-module-build' option requires '--use-integrated-swift-driver'")
        }

        if !options.archs.isEmpty && options.customCompileTriple != nil {
            observabilityScope.emit(.mutuallyExclusiveArgumentsError(arguments: ["--arch", "--triple"]))
        }

        // --enable-test-discovery should never be called on darwin based platforms
#if canImport(Darwin)
        if options.enableTestDiscovery {
            observabilityScope.emit(warning: "'--enable-test-discovery' option is deprecated; tests are automatically discovered on all platforms")
        }
#endif

        if options.shouldDisableManifestCaching {
            observabilityScope.emit(warning: "'--disable-package-manifest-caching' option is deprecated; use '--manifest-caching' instead")
        }

        if let _ = options.netrcFilePath, options.netrc == false {
            observabilityScope.emit(.mutuallyExclusiveArgumentsError(arguments: ["--disable-netrc", "--netrc-file"]))
        }

        if options._deprecated_netrc {
            observabilityScope.emit(warning: "'--netrc' option is deprecated; .netrc files are located by default")
        }

        if options._deprecated_netrcOptional {
            observabilityScope.emit(warning: "'--netrc-optional' option is deprecated; .netrc files are located by default")
        }

        if options._deprecated_enableResolverTrace {
            observabilityScope.emit(warning: "'--enableResolverTrace' flag is deprecated; use '--verbose' option to log resolver output")
        }

        if options._deprecated_useRepositoriesCache != nil {
            observabilityScope.emit(warning: "'--disable-repository-cache'/'--enable-repository-cache' flags are deprecated; use '--disable-dependency-cache'/'--enable-dependency-cache' instead")
        }

    }

    /// Returns the currently active workspace.
    func getActiveWorkspace() throws -> Workspace {
        if let workspace = _workspace {
            return workspace
        }

        let delegate = ToolWorkspaceDelegate(self.outputStream, logLevel: self.logLevel, observabilityScope: self.observabilityScope)
        let repositoryProvider = GitRepositoryProvider(processSet: self.processSet)
        let isXcodeBuildSystemEnabled = self.options.buildSystem == .xcode
        let workspace = try Workspace(
            fileSystem: self.fileSystem,
            location: .init(
                workingDirectory: self.buildPath,
                editsDirectory: self.getEditsDirectory(),
                resolvedVersionsFile: self.getResolvedVersionsFile(),
                localConfigurationDirectory: try self.getLocalConfigurationDirectory(),
                sharedConfigurationDirectory: self.sharedConfigurationDirectory,
                sharedSecurityDirectory: self.sharedSecurityDirectory,
                sharedCacheDirectory: self.sharedCacheDirectory
            ),
            authorizationProvider: self.getAuthorizationProvider(),
            configuration: .init(
                skipDependenciesUpdates: options.skipDependencyUpdate,
                prefetchBasedOnResolvedFile: options.shouldEnableResolverPrefetching,
                additionalFileRules: isXcodeBuildSystemEnabled ? FileRuleDescription.xcbuildFileTypes : FileRuleDescription.swiftpmFileTypes,
                sharedDependenciesCacheEnabled: self.options.useDependenciesCache,
                fingerprintCheckingMode: self.options.resolverFingerprintCheckingMode,
                sourceControlToRegistryDependencyTransformation: self.options.sourceControlToRegistryDependencyTransformation.workspaceConfiguration
            ),
            initializationWarningHandler: { self.observabilityScope.emit(warning: $0) },
            customHostToolchain: self.getHostToolchain(),
            customManifestLoader: self.getManifestLoader(),
            customRepositoryProvider: repositoryProvider, // FIXME: ideally we would not customize the repository provider. its currently done for shutdown handling which can be better abstracted
            delegate: delegate
        )
        _workspace = workspace
        _workspaceDelegate = delegate
        return workspace
    }

    private func getEditsDirectory() throws -> AbsolutePath {
        // TODO: replace multiroot-data-file with explicit overrides
        if let multiRootPackageDataFile = options.multirootPackageDataFile {
            return multiRootPackageDataFile.appending(component: "Packages")
        }
        return try Workspace.DefaultLocations.editsDirectory(forRootPackage: self.getPackageRoot())
    }

    private func getResolvedVersionsFile() throws -> AbsolutePath {
        // TODO: replace multiroot-data-file with explicit overrides
        if let multiRootPackageDataFile = options.multirootPackageDataFile {
            return multiRootPackageDataFile.appending(components: "xcshareddata", "swiftpm", "Package.resolved")
        }
        return try Workspace.DefaultLocations.resolvedVersionsFile(forRootPackage: self.getPackageRoot())
    }

    internal func getLocalConfigurationDirectory() throws -> AbsolutePath {
        // Otherwise, use the default path.
        // TODO: replace multiroot-data-file with explicit overrides
        if let multiRootPackageDataFile = options.multirootPackageDataFile {
            // migrate from legacy location
            let legacyPath = multiRootPackageDataFile.appending(components: "xcshareddata", "swiftpm", "config")
            let newPath = Workspace.DefaultLocations.mirrorsConfigurationFile(at: multiRootPackageDataFile.appending(components: "xcshareddata", "swiftpm", "configuration"))
            return try Workspace.migrateMirrorsConfiguration(from: legacyPath, to: newPath, observabilityScope: observabilityScope)
        } else {
            // migrate from legacy location
            let legacyPath = try self.getPackageRoot().appending(components: ".swiftpm", "config")
            let newPath = try Workspace.DefaultLocations.mirrorsConfigurationFile(forRootPackage: self.getPackageRoot())
            return try Workspace.migrateMirrorsConfiguration(from: legacyPath, to: newPath, observabilityScope: observabilityScope)
        }
    }

    func getAuthorizationProvider() throws -> AuthorizationProvider? {
        var authorization = Workspace.Configuration.Authorization.default
        if !options.netrc {
            authorization.netrc = .disabled
        } else if let configuredPath = options.netrcFilePath {
            authorization.netrc = .custom(configuredPath)
        } else {
            let rootPath = try options.multirootPackageDataFile ?? self.getPackageRoot()
            authorization.netrc = .workspaceAndUser(rootPath: rootPath)
        }

        #if canImport(Security)
        authorization.keychain = self.options.keychain ? .enabled : .disabled
        #endif

        return try authorization.makeAuthorizationProvider(fileSystem: self.fileSystem, observabilityScope: self.observabilityScope)
    }

    /// Resolve the dependencies.
    func resolve() throws {
        let workspace = try getActiveWorkspace()
        let root = try getWorkspaceRoot()

        if options.forceResolvedVersions {
            try workspace.resolveBasedOnResolvedVersionsFile(root: root, observabilityScope: self.observabilityScope)
        } else {
            try workspace.resolve(root: root, observabilityScope: self.observabilityScope)
        }

        // Throw if there were errors when loading the graph.
        // The actual errors will be printed before exiting.
        guard !self.observabilityScope.errorsReported else {
            throw ExitCode.failure
        }
    }

    /// Fetch and load the complete package graph.
    ///
    /// - Parameters:
    ///   - explicitProduct: The product specified on the command line to a “swift run” or “swift build” command. This allows executables from dependencies to be run directly without having to hook them up to any particular target.
    @discardableResult
    func loadPackageGraph(
        explicitProduct: String? = nil,
        createMultipleTestProducts: Bool = false,
        createREPLProduct: Bool = false
    ) throws -> PackageGraph {
        do {
            let workspace = try getActiveWorkspace()

            // Fetch and load the package graph.
            let graph = try workspace.loadPackageGraph(
                rootInput: getWorkspaceRoot(),
                explicitProduct: explicitProduct,
                createMultipleTestProducts: createMultipleTestProducts,
                createREPLProduct: createREPLProduct,
                forceResolvedVersions: options.forceResolvedVersions,
                observabilityScope: self.observabilityScope
            )

            // Throw if there were errors when loading the graph.
            // The actual errors will be printed before exiting.
            guard !self.observabilityScope.errorsReported else {
                throw ExitCode.failure
            }
            return graph
        } catch {
            throw error
        }
    }
    
    func getPluginScriptRunner() throws -> PluginScriptRunner {
        let pluginsDir = try self.getActiveWorkspace().location.pluginWorkingDirectory
        let cacheDir = pluginsDir.appending(component: "cache")
        let pluginScriptRunner = try DefaultPluginScriptRunner(
            fileSystem: self.fileSystem,
            cacheDir: cacheDir,
            toolchain: self.getHostToolchain().configuration,
            enableSandbox: !self.options.shouldDisableSandbox
        )
        return pluginScriptRunner
    }

    /// Returns the user toolchain to compile the actual product.
    func getToolchain() throws -> UserToolchain {
        return try _destinationToolchain.get()
    }

    func getHostToolchain() throws -> UserToolchain {
        return try _hostToolchain.get()
    }

    func getManifestLoader() throws -> ManifestLoader {
        return try _manifestLoader.get()
    }

    private func canUseCachedBuildManifest() throws -> Bool {
        if !self.options.cacheBuildManifest {
            return false
        }

        let buildParameters = try self.buildParameters()
        let haveBuildManifestAndDescription =
        self.fileSystem.exists(buildParameters.llbuildManifest) &&
        self.fileSystem.exists(buildParameters.buildDescriptionPath)

        if !haveBuildManifestAndDescription {
            return false
        }

        // Perform steps for build manifest caching if we can enabled it.
        //
        // FIXME: We don't add edited packages in the package structure command yet (SR-11254).
        let hasEditedPackages = try self.getActiveWorkspace().state.dependencies.contains(where: { $0.isEdited })
        if hasEditedPackages {
            return false
        }

        return true
    }

    // note: do not customize the OutputStream unless absolutely necessary
    // "customOutputStream" is designed to support build output redirection
    // but it is only expected to be used when invoking builds from "swift build" command.
    // in all other cases, the build output should go to the default which is stderr
    func createBuildOperation(
        explicitProduct: String? = .none,
        cacheBuildManifest: Bool = true,
        customBuildParameters: BuildParameters? = .none,
        customPackageGraphLoader: (() throws -> PackageGraph)? = .none,
        customOutputStream: OutputByteStream? = .none,
        customObservabilityScope: ObservabilityScope? = .none
    ) throws -> BuildOperation {
        let graphLoader = { try self.loadPackageGraph(explicitProduct: explicitProduct) }

        // Construct the build operation.
        // FIXME: We need to implement the build tool invocation closure here so that build tool plugins work with dumping the symbol graph (the only case that currently goes through this path, as far as I can tell). rdar://86112934
        let buildOp = try BuildOperation(
            buildParameters: customBuildParameters ?? self.buildParameters(),
            cacheBuildManifest: cacheBuildManifest && self.canUseCachedBuildManifest(),
            packageGraphLoader: customPackageGraphLoader ?? graphLoader,
            pluginScriptRunner: self.getPluginScriptRunner(),
            pluginWorkDirectory: try self.getActiveWorkspace().location.pluginWorkingDirectory,
            outputStream: customOutputStream ?? self.outputStream,
            logLevel: self.logLevel,
            fileSystem: self.fileSystem,
            observabilityScope: customObservabilityScope ?? self.observabilityScope
        )

        // Save the instance so it can be cancelled from the int handler.
        buildSystemRef.buildSystem = buildOp
        return buildOp
    }

    // note: do not customize the OutputStream unless absolutely necessary
    // "customOutputStream" is designed to support build output redirection
    // but it is only expected to be used when invoking builds from "swift build" command.
    // in all other cases, the build output should go to the default which is stderr
    func createBuildSystem(
        explicitProduct: String? = .none,
        customBuildParameters: BuildParameters? = .none,
        customPackageGraphLoader: (() throws -> PackageGraph)? = .none,
        customOutputStream: OutputByteStream? = .none,
        customObservabilityScope: ObservabilityScope? = .none
    ) throws -> BuildSystem {
        let buildSystem: BuildSystem
        switch options.buildSystem {
        case .native:
            let graphLoader = { try self.loadPackageGraph(explicitProduct: explicitProduct) }

            buildSystem = try BuildOperation(
                buildParameters: customBuildParameters ?? self.buildParameters(),
                cacheBuildManifest: self.canUseCachedBuildManifest(),
                packageGraphLoader: customPackageGraphLoader ?? graphLoader,
                pluginScriptRunner: self.getPluginScriptRunner(),
                pluginWorkDirectory: try self.getActiveWorkspace().location.pluginWorkingDirectory,
                disableSandboxForPluginCommands: self.options.shouldDisableSandbox,
                outputStream: customOutputStream ?? self.outputStream,
                logLevel: self.logLevel,
                fileSystem: self.fileSystem,
                observabilityScope: customObservabilityScope ?? self.observabilityScope
            )
        case .xcode:
            let graphLoader = { try self.loadPackageGraph(explicitProduct: explicitProduct, createMultipleTestProducts: true) }
            // FIXME: Implement the custom build command provider also.
            buildSystem = try XcodeBuildSystem(
                buildParameters: customBuildParameters ?? self.buildParameters(),
                packageGraphLoader: customPackageGraphLoader ??  graphLoader,
                outputStream: customOutputStream ?? self.outputStream,
                logLevel: self.logLevel,
                fileSystem: self.fileSystem,
                observabilityScope: customObservabilityScope ?? self.observabilityScope
            )
        }

        // Save the instance so it can be cancelled from the int handler.
        buildSystemRef.buildSystem = buildSystem
        return buildSystem
    }

    /// Return the build parameters.
    func buildParameters() throws -> BuildParameters {
        return try _buildParameters.get()
    }

    private lazy var _buildParameters: Result<BuildParameters, Swift.Error> = {
        return Result(catching: {
            let toolchain = try self.getToolchain()
            let triple = toolchain.triple

            // Use "apple" as the subdirectory because in theory Xcode build system
            // can be used to build for any Apple platform and it has it's own
            // conventions for build subpaths based on platforms.
            let dataPath = buildPath.appending(
                component: options.buildSystem == .xcode ? "apple" : triple.platformBuildPathComponent())
            return BuildParameters(
                dataPath: dataPath,
                configuration: options.configuration,
                toolchain: toolchain,
                destinationTriple: triple,
                archs: options.archs,
                flags: options.buildFlags,
                xcbuildFlags: options.xcbuildFlags,
                jobs: options.jobs ?? UInt32(ProcessInfo.processInfo.activeProcessorCount),
                shouldLinkStaticSwiftStdlib: options.shouldLinkStaticSwiftStdlib,
                canRenameEntrypointFunctionName: SwiftTargetBuildDescription.checkSupportedFrontendFlags(
                    flags: ["entry-point-function-name"], fileSystem: self.fileSystem
                ),
                sanitizers: options.enabledSanitizers,
                enableCodeCoverage: options.shouldEnableCodeCoverage,
                indexStoreMode: options.indexStoreMode.buildParameter,
                enableParseableModuleInterfaces: options.shouldEnableParseableModuleInterfaces,
                emitSwiftModuleSeparately: options.emitSwiftModuleSeparately,
                useIntegratedSwiftDriver: options.useIntegratedSwiftDriver,
                useExplicitModuleBuild: options.useExplicitModuleBuild,
                isXcodeBuildSystemEnabled: options.buildSystem == .xcode,
                printManifestGraphviz: options.printManifestGraphviz,
                forceTestDiscovery: options.enableTestDiscovery, // backwards compatibility, remove with --enable-test-discovery
                linkerDeadStrip: options.linkerDeadStrip,
                verboseOutput: self.logLevel <= .info
            )
        })
    }()

    /// Lazily compute the destination toolchain.
    private lazy var _destinationToolchain: Result<UserToolchain, Swift.Error> = {
        var destination: Destination
        let hostDestination: Destination
        do {
            hostDestination = try self._hostToolchain.get().destination
            // Create custom toolchain if present.
            if let customDestination = self.options.customCompileDestination {
                destination = try Destination(fromFile: customDestination, fileSystem: self.fileSystem)
            } else if let target = self.options.customCompileTriple,
                      let targetDestination = Destination.defaultDestination(for: target, host: hostDestination) {
                destination = targetDestination
            } else {
                // Otherwise use the host toolchain.
                destination = hostDestination
            }
        } catch {
            return .failure(error)
        }
        // Apply any manual overrides.
        if let triple = self.options.customCompileTriple {
            destination.target = triple
        }
        if let binDir = self.options.customCompileToolchain {
            destination.binDir = binDir.appending(components: "usr", "bin")
        }
        if let sdk = self.options.customCompileSDK {
            destination.sdk = sdk
        }
        destination.archs = options.archs

        // Check if we ended up with the host toolchain.
        if hostDestination == destination {
            return self._hostToolchain
        }

        return Result(catching: { try UserToolchain(destination: destination) })
    }()

    /// Lazily compute the host toolchain used to compile the package description.
    private lazy var _hostToolchain: Result<UserToolchain, Swift.Error> = {
        return Result(catching: {
            try UserToolchain(destination: Destination.hostDestination(
                originalWorkingDirectory: self.originalWorkingDirectory))
        })
    }()

    private lazy var _manifestLoader: Result<ManifestLoader, Swift.Error> = {
        return Result(catching: {
            let cachePath: AbsolutePath?
            switch (self.options.shouldDisableManifestCaching, self.options.manifestCachingMode) {
            case (true, _):
                // backwards compatibility
                cachePath = .none
            case (false, .none):
                cachePath = .none
            case (false, .local):
                cachePath = self.buildPath
            case (false, .shared):
                cachePath = self.sharedCacheDirectory.map{ Workspace.DefaultLocations.manifestsDirectory(at: $0) }
            }

            var extraManifestFlags = self.options.manifestFlags
            // Disable the implicit concurrency import if the compiler in use supports it to avoid warnings if we are building against an older SDK that does not contain a Concurrency module.
            if SwiftTargetBuildDescription.checkSupportedFrontendFlags(flags: ["disable-implicit-concurrency-module-import"], fileSystem: self.fileSystem) {
                extraManifestFlags += ["-Xfrontend", "-disable-implicit-concurrency-module-import"]
            }

            if self.logLevel <= .info {
                extraManifestFlags.append("-v")
            }

            return try ManifestLoader(
                // Always use the host toolchain's resources for parsing manifest.
                toolchain: self.getHostToolchain().configuration,
                isManifestSandboxEnabled: !self.options.shouldDisableSandbox,
                cacheDir: cachePath,
                extraManifestFlags: extraManifestFlags
            )
        })
    }()

    /// An enum indicating the execution status of run commands.
    enum ExecutionStatus {
        case success
        case failure
        }
}

/// Returns path of the nearest directory containing the manifest file w.r.t
/// current working directory.
private func findPackageRoot(fileSystem: FileSystem) -> AbsolutePath? {
    guard var root = fileSystem.currentWorkingDirectory else {
        return nil
    }
    // FIXME: It would be nice to move this to a generalized method which takes path and predicate and
    // finds the lowest path for which the predicate is true.
    while !fileSystem.isFile(root.appending(component: Manifest.filename)) {
        root = root.parentDirectory
        guard !root.isRoot else {
            return nil
        }
    }
    return root
}

/// Returns the build path from the environment, if present.
private func getEnvBuildPath(workingDir: AbsolutePath) -> AbsolutePath? {
    // Don't rely on build path from env for SwiftPM's own tests.
    guard ProcessEnv.vars["SWIFTPM_TESTS_MODULECACHE"] == nil else { return nil }
    guard let env = ProcessEnv.vars["SWIFTPM_BUILD_DIR"] else { return nil }
    return AbsolutePath(env, relativeTo: workingDir)
}


private func getSharedSecurityDirectory(options: SwiftToolOptions, fileSystem: FileSystem, observabilityScope: ObservabilityScope) throws -> AbsolutePath? {
    if let explicitSecurityPath = options.securityPath {
        // Create the explicit security path if necessary
        if !fileSystem.exists(explicitSecurityPath) {
            try fileSystem.createDirectory(explicitSecurityPath, recursive: true)
        }
        return explicitSecurityPath
    } else {
        // further validation is done in workspace
        return fileSystem.swiftPMSecurityDirectory
    }
}

private func getSharedConfigurationDirectory(options: SwiftToolOptions, fileSystem: FileSystem, observabilityScope: ObservabilityScope) throws -> AbsolutePath? {
    if let explicitConfigPath = options.configPath {
        // Create the explicit config path if necessary
        if !fileSystem.exists(explicitConfigPath) {
            try fileSystem.createDirectory(explicitConfigPath, recursive: true)
        }
        return explicitConfigPath
    } else {
        // further validation is done in workspace
        return fileSystem.swiftPMConfigurationDirectory
    }
}

private func getSharedCacheDirectory(options: SwiftToolOptions, fileSystem: FileSystem, observabilityScope: ObservabilityScope) throws -> AbsolutePath? {
    if let explicitCachePath = options.cachePath {
        // Create the explicit cache path if necessary
        if !fileSystem.exists(explicitCachePath) {
            try fileSystem.createDirectory(explicitCachePath, recursive: true)
        }
        return explicitCachePath
    } else {
        // further validation is done in workspace
        return fileSystem.swiftPMCacheDirectory
    }
}

/// A wrapper to hold the build system so we can use it inside
/// the int. handler without requiring to initialize it.
final class BuildSystemRef {
    var buildSystem: BuildSystem?
}

extension Basics.Diagnostic {
    static func unsupportedFlag(_ flag: String) -> Self {
        .warning("\(flag) is an *unsupported* option which can be removed at any time; do not rely on it")
    }
}

// MARK: - Diagnostics

private struct SwiftToolObservabilityHandler: ObservabilityHandlerProvider {
    private let outputHandler: OutputHandler

    var diagnosticsHandler: DiagnosticsHandler {
        self.outputHandler
    }

    init(outputStream: OutputByteStream, logLevel: Diagnostic.Severity) {
        let threadSafeOutputByteStream = outputStream as? ThreadSafeOutputByteStream ?? ThreadSafeOutputByteStream(outputStream)
        self.outputHandler = OutputHandler(logLevel: logLevel, outputStream: threadSafeOutputByteStream)
    }

    // FIXME: deprecate this one we are further along refactoring the call sites that use it
    var outputStream: OutputByteStream {
        self.outputHandler.outputStream
    }

    struct OutputHandler: DiagnosticsHandler {
        let logLevel: Diagnostic.Severity
        let outputStream: ThreadSafeOutputByteStream
        let writer: InteractiveWriter

        init(logLevel: Diagnostic.Severity, outputStream: ThreadSafeOutputByteStream) {
            self.logLevel = logLevel
            self.outputStream = outputStream
            self.writer = InteractiveWriter(stream: outputStream)
        }

        func handleDiagnostic(scope: ObservabilityScope, diagnostic: Basics.Diagnostic) {
            // TODO: do something useful with scope
            if diagnostic.severity >= self.logLevel {
                diagnostic.print(with: self.writer)
            }
        }
    }
}

extension SwiftTool {
    // FIXME: deprecate these one we are further along refactoring the call sites that use it
    /// The stream to print standard output on.
    var outputStream: OutputByteStream {
        self.observabilityHandler.outputStream
    }
}

extension Basics.Diagnostic {
    fileprivate func print(with writer: InteractiveWriter) {
        var message: String
        switch self.severity {
        case .error:
            message = writer.format("error: ", inColor: .red, bold: true)
        case .warning:
            message = writer.format("warning: ", inColor: .yellow, bold: true)
        case .info:
            message = writer.format("info: ", inColor: .white, bold: true)
        case .debug:
            message = writer.format("debug: ", inColor: .white, bold: true)
        }

        if let diagnosticPrefix = self.metadata?.diagnosticPrefix {
            message += diagnosticPrefix
            message += ": "
        }

        message += self.message
        if !self.message.hasPrefix("\n") {
            message += "\n"
        }

        writer.write(message)
    }
}

/// This class is used to write on the underlying stream.
///
/// If underlying stream is a not tty, the string will be written in without any
/// formatting.
private struct InteractiveWriter {
    /// The terminal controller, if present.
    let term: TerminalController?

    /// The output byte stream reference.
    let stream: OutputByteStream

    /// Create an instance with the given stream.
    init(stream: OutputByteStream) {
        self.term = TerminalController(stream: stream)
        self.stream = stream
    }

    /// Write the string to the contained terminal or stream.
    func write(_ string: String, inColor color: TerminalController.Color = .noColor, bold: Bool = false) {
        if let term = self.term {
            term.write(string, inColor: color, bold: bold)
        } else {
            stream <<< string
            stream.flush()
        }
    }

    func format(_ string: String, inColor color: TerminalController.Color = .noColor, bold: Bool = false) -> String {
        if let term = self.term {
            return term.wrap(string, inColor: color, bold: bold)
        } else {
            return string
        }
    }
}

// FIXME: this is for backwards compatibility with existing diagnostics printing format
// we should remove this as we make use of the new scope and metadata to provide better contextual information
extension ObservabilityMetadata {
    fileprivate var diagnosticPrefix: String? {
        if let packageIdentity = self.packageIdentity {
            return "'\(packageIdentity)'"
        } else {
            return .none
        }
    }
}

extension Workspace.ManagedDependency {
    fileprivate var isEdited: Bool {
        if case .edited = self.state { return true }
        return false
    }
}

extension SwiftToolOptions {
    var logLevel: Diagnostic.Severity {
        if self.verbose {
            return .info
        } else if self.veryVerbose {
            return .debug
        } else {
            return .warning
        }
    }
}

extension SwiftToolOptions.SourceControlToRegistryDependencyTransformation {
    var workspaceConfiguration: WorkspaceConfiguration.SourceControlToRegistryDependencyTransformation {
        switch self {
        case .disabled:
            return .disabled
        case .identity:
            return .identity
        case .swizzle:
            return .swizzle
        }
    }
}

extension SwiftToolOptions.StoreMode {
    var buildParameter: BuildParameters.IndexStoreMode {
        switch self {
        case .autoIndexStore:
            return .auto
        case .enableIndexStore:
            return .on
        case .disableIndexStore:
            return .off
        }
    }
}
