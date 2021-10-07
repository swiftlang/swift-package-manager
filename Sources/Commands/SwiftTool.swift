/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import ArgumentParser
import Basics
import Build
import Dispatch
import func Foundation.NSUserName
import class Foundation.ProcessInfo
import func Foundation.NSHomeDirectory
import PackageGraph
import PackageLoading
import PackageModel
import SourceControl
import SPMBuildCore
import TSCBasic
import TSCLibc
import TSCUtility
import Workspace
import XCBuildSupport

typealias Diagnostic = TSCBasic.Diagnostic

private class ToolWorkspaceDelegate: WorkspaceDelegate {
    /// The stream to use for reporting progress.
    private let outputStream: ThreadSafeOutputByteStream

    /// The progress animation for downloads.
    private let downloadAnimation: NinjaProgressAnimation

    /// The progress animation for repository fetches.
    private let fetchAnimation: NinjaProgressAnimation

    /// Wether the tool is in a verbose mode.
    private let isVerbose: Bool

    private struct DownloadProgress {
        let bytesDownloaded: Int64
        let totalBytesToDownload: Int64
    }

    private struct FetchProgress {
        let objectsFetched: Int
        let totalObjectsToFetch: Int
    }

    /// The progress of each individual downloads.
    private var downloadProgress: [String: DownloadProgress] = [:]

    /// The progress of each individual fetch operation
    private var fetchProgress: [String: FetchProgress] = [:]

    private let queue = DispatchQueue(label: "org.swift.swiftpm.commands.tool-workspace-delegate")
    private let diagnostics: DiagnosticsEngine

    init(_ outputStream: OutputByteStream, isVerbose: Bool, diagnostics: DiagnosticsEngine) {
        // FIXME: Implement a class convenience initializer that does this once they are supported
        // https://forums.swift.org/t/allow-self-x-in-class-convenience-initializers/15924
        self.outputStream = outputStream as? ThreadSafeOutputByteStream ?? ThreadSafeOutputByteStream(outputStream)
        self.downloadAnimation = NinjaProgressAnimation(stream: self.outputStream)
        self.fetchAnimation = NinjaProgressAnimation(stream: self.outputStream)
        self.isVerbose = isVerbose
        self.diagnostics = diagnostics
    }

    func fetchingWillBegin(repository: String, fetchDetails: RepositoryManager.FetchDetails?) {
        queue.async {
            self.outputStream <<< "Fetching \(repository)"
            if let fetchDetails = fetchDetails {
                if fetchDetails.fromCache {
                    self.outputStream <<< " from cache"
                }
            }
            self.outputStream <<< "\n"
            self.outputStream.flush()
        }
    }

    func fetchingDidFinish(repository: String, fetchDetails: RepositoryManager.FetchDetails?, diagnostic: Diagnostic?, duration: DispatchTimeInterval) {
        queue.async {
            if self.diagnostics.hasErrors {
                self.fetchAnimation.clear()
            }

            let step = self.fetchProgress.values.reduce(0) { $0 + $1.objectsFetched }
            let total = self.fetchProgress.values.reduce(0) { $0 + $1.totalObjectsToFetch }

            if step == total && !self.fetchProgress.isEmpty {
                self.fetchAnimation.complete(success: true)
                self.fetchProgress.removeAll()
            }

            self.outputStream <<< "Fetched \(repository) (\(duration.descriptionInSeconds))"
            self.outputStream <<< "\n"
            self.outputStream.flush()
        }
    }

    func repositoryWillUpdate(_ repository: String) {
        queue.async {
            self.outputStream <<< "Updating \(repository)"
            self.outputStream <<< "\n"
            self.outputStream.flush()
        }
    }

    func repositoryDidUpdate(_ repository: String, duration: DispatchTimeInterval) {
        queue.async {
            self.outputStream <<< "Updated \(repository) (\(duration.descriptionInSeconds))"
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

    func willCreateWorkingCopy(repository: String, at path: AbsolutePath) {
        queue.async {
            self.outputStream <<< "Creating working copy for \(repository)"
            self.outputStream <<< "\n"
            self.outputStream.flush()
        }
    }

    func willCheckOut(repository: String, revision: String, at path: AbsolutePath) {
        // noop
    }

    func didCheckOut(repository: String, revision: String, at path: AbsolutePath, error: Diagnostic?) {
        guard case .none = error else {
            return // error will be printed before hand
        }
        queue.async {
            self.outputStream <<< "Working copy of \(repository) resolved at \(revision)"
            self.outputStream <<< "\n"
            self.outputStream.flush()
        }
    }

    func removing(repository: String) {
        queue.async {
            self.outputStream <<< "Removing \(repository)"
            self.outputStream <<< "\n"
            self.outputStream.flush()
        }
    }

    func warning(message: String) {
        // FIXME: We should emit warnings through the diagnostic engine.
        queue.async {
            self.outputStream <<< "warning: " <<< message
            self.outputStream <<< "\n"
            self.outputStream.flush()
        }
    }

    func willResolveDependencies(reason: WorkspaceResolveReason) {
        guard isVerbose else { return }

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

    func downloadingBinaryArtifact(from url: String, bytesDownloaded: Int64, totalBytesToDownload: Int64?) {
        queue.async {
            if let totalBytesToDownload = totalBytesToDownload {
                self.downloadProgress[url] = DownloadProgress(
                    bytesDownloaded: bytesDownloaded,
                    totalBytesToDownload: totalBytesToDownload)
            }

            let step = self.downloadProgress.values.reduce(0, { $0 + $1.bytesDownloaded }) / 1024
            let total = self.downloadProgress.values.reduce(0, { $0 + $1.totalBytesToDownload }) / 1024
            self.downloadAnimation.update(step: Int(step), total: Int(total), text: "Downloading binary artifacts")
        }
    }

    func didDownloadBinaryArtifacts() {
        queue.async {
            if self.diagnostics.hasErrors {
                self.downloadAnimation.clear()
            }

            self.downloadAnimation.complete(success: true)
            self.downloadProgress.removeAll()
        }
    }

    func fetchingRepository(from repository: String, objectsFetched: Int, totalObjectsToFetch: Int) {
        queue.async {
            self.fetchProgress[repository] = FetchProgress(
                objectsFetched: objectsFetched,
                totalObjectsToFetch: totalObjectsToFetch)

            let step = self.fetchProgress.values.reduce(0) { $0 + $1.objectsFetched }
            let total = self.fetchProgress.values.reduce(0) { $0 + $1.totalObjectsToFetch }
            self.fetchAnimation.update(step: step, total: total, text: "Fetching objects")
        }
    }

    // noop

    func willLoadManifest(packagePath: AbsolutePath, url: String, version: Version?, packageKind: PackageReference.Kind) {}
    func didLoadManifest(packagePath: AbsolutePath, url: String, version: Version?, packageKind: PackageReference.Kind, manifest: Manifest?, diagnostics: [Diagnostic]) {}
    func didCreateWorkingCopy(repository url: String, at path: AbsolutePath, error: Diagnostic?) {}
    func resolvedFileChanged() {}
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
    /// The original working directory.
    let originalWorkingDirectory: AbsolutePath

    /// The options of this tool.
    var options: SwiftToolOptions

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
            packages = try XcodeWorkspaceLoader(diagnostics: self.observabilityScope.makeDiagnosticsEngine()).load(workspace: workspace)
        } else {
            packages = [try getPackageRoot()]
        }

        return PackageGraphRootInput(packages: packages)
    }

    /// Path to the build directory.
    let buildPath: AbsolutePath

    /// The process set to hold the launched processes. These will be terminated on any signal
    /// received by the swift tools.
    let processSet: ProcessSet

    /// The current build system reference. The actual reference is present only during an active build.
    let buildSystemRef: BuildSystemRef

    /// The interrupt handler.
    let interruptHandler: InterruptHandler

    /// The execution status of the tool.
    var executionStatus: ExecutionStatus = .success

    /// The stream to print standard output on.
    fileprivate(set) var outputStream: OutputByteStream = TSCBasic.stdoutStream

    /// Holds the currently active workspace.
    ///
    /// It is not initialized in init() because for some of the commands like package init , usage etc,
    /// workspace is not needed, infact it would be an error to ask for the workspace object
    /// for package init because the Manifest file should *not* present.
    private var _workspace: Workspace?
    private var _workspaceDelegate: ToolWorkspaceDelegate?

    let observabilityScope: ObservabilityScope

    /// Create an instance of this tool.
    ///
    /// - parameter args: The command line arguments to be passed to this tool.
    public init(options: SwiftToolOptions) throws {
        // first, bootstrap the observability system
        let observabilitySystem = ObservabilitySystem.init(SwiftToolObservability())
        self.observabilityScope = observabilitySystem.topScope

        // Capture the original working directory ASAP.
        guard let cwd = localFileSystem.currentWorkingDirectory else {
            self.observabilityScope.emit(error: "couldn't determine the current working directory")
            throw ExitCode.failure
        }
        originalWorkingDirectory = cwd

        do {
            try Self.postprocessArgParserResult(options: options, diagnostics: self.observabilityScope.makeDiagnosticsEngine())
            self.options = options

            // Honor package-path option is provided.
            if let packagePath = options.packagePath ?? options.chdir {
                try ProcessEnv.chdir(packagePath)
            }

            // Force building with the native build system on other platforms than macOS.
#if !os(macOS)
            self.options._buildSystem = .native
#endif

            let processSet = ProcessSet()
            let buildSystemRef = BuildSystemRef()
            interruptHandler = try InterruptHandler {
                // Terminate all processes on receiving an interrupt signal.
                processSet.terminate()
                buildSystemRef.buildSystem?.cancel()

#if os(Windows)
                // Exit as if by signal()
                TerminateProcess(GetCurrentProcess(), 3)
#elseif os(macOS) || os(OpenBSD)
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
            self.processSet = processSet
            self.buildSystemRef = buildSystemRef

        } catch {
            self.observabilityScope.emit(error)
            throw ExitCode.failure
        }

        // Create local variables to use while finding build path to avoid capture self before init error.
        let customBuildPath = options.buildPath
        let packageRoot = findPackageRoot()

        self.packageRoot = packageRoot
        self.buildPath = getEnvBuildPath(workingDir: cwd) ??
        customBuildPath ??
        (packageRoot ?? cwd).appending(component: ".build")

        // Setup the globals.
        verbosity = Verbosity(rawValue: options.verbosity)
        Process.verbose = verbosity != .concise
    }

    static func postprocessArgParserResult(options: SwiftToolOptions, diagnostics: DiagnosticsEngine) throws {
        if options.chdir != nil {
            diagnostics.emit(warning: "'--chdir/-C' option is deprecated; use '--package-path' instead")
        }

        if options.multirootPackageDataFile != nil {
            diagnostics.emit(.unsupportedFlag("--multiroot-data-file"))
        }

        if options.useExplicitModuleBuild && !options.useIntegratedSwiftDriver {
            diagnostics.emit(error: "'--experimental-explicit-module-build' option requires '--use-integrated-swift-driver'")
        }

        if !options.archs.isEmpty && options.customCompileTriple != nil {
            diagnostics.emit(.mutuallyExclusiveArgumentsError(arguments: ["--arch", "--triple"]))
        }

        // --enable-test-discovery should never be called on darwin based platforms
#if canImport(Darwin)
        if options.enableTestDiscovery {
            diagnostics.emit(warning: "'--enable-test-discovery' option is deprecated; tests are automatically discovered on all platforms")
        }
#endif

        if options.shouldDisableManifestCaching {
            diagnostics.emit(warning: "'--disable-package-manifest-caching' option is deprecated; use '--manifest-caching' instead")
        }

        if let _ = options.netrcFilePath, options.netrc == false {
            diagnostics.emit(.mutuallyExclusiveArgumentsError(arguments: ["--disable-netrc", "--netrc-file"]))
        }

        if options._deprecated_netrc {
            diagnostics.emit(warning: "'--netrc' option is deprecated; .netrc files are located by default")
        }

        if options._deprecated_netrcOptional {
            diagnostics.emit(warning: "'--netrc-optional' option is deprecated; .netrc files are located by default")
        }
    }

    private func editsDirectory() throws -> AbsolutePath {
        // TODO: replace multiroot-data-file with explicit overrides
        if let multiRootPackageDataFile = options.multirootPackageDataFile {
            return multiRootPackageDataFile.appending(component: "Packages")
        }
        return try Workspace.DefaultLocations.editsDirectory(forRootPackage: self.getPackageRoot())
    }

    private func resolvedVersionsFile() throws -> AbsolutePath {
        // TODO: replace multiroot-data-file with explicit overrides
        if let multiRootPackageDataFile = options.multirootPackageDataFile {
            return multiRootPackageDataFile.appending(components: "xcshareddata", "swiftpm", "Package.resolved")
        }
        return try Workspace.DefaultLocations.resolvedVersionsFile(forRootPackage: self.getPackageRoot())
    }

    func getMirrorsConfig(sharedConfigurationDirectory: AbsolutePath? = nil) throws -> Workspace.Configuration.Mirrors {
        let sharedConfigurationDirectory = try sharedConfigurationDirectory ?? self.getSharedConfigurationDirectory()
        let sharedMirrorFile = sharedConfigurationDirectory.map { Workspace.DefaultLocations.mirrorsConfigurationFile(at: $0) }
        return try .init(
            localMirrorFile: self.mirrorsConfigFile(),
            sharedMirrorFile: sharedMirrorFile,
            fileSystem: localFileSystem
        )
    }

    private func mirrorsConfigFile() throws -> AbsolutePath {
        // TODO: does this make sense now that we a global configuration as well? or should we at least rename it?
        // Look for the override in the environment.
        if let envPath = ProcessEnv.vars["SWIFTPM_MIRROR_CONFIG"] {
            return try AbsolutePath(validating: envPath)
        }

        // Otherwise, use the default path.
        // TODO: replace multiroot-data-file with explicit overrides
        if let multiRootPackageDataFile = options.multirootPackageDataFile {
            // migrate from legacy location
            let legacyPath = multiRootPackageDataFile.appending(components: "xcshareddata", "swiftpm", "config")
            let newPath = multiRootPackageDataFile.appending(components: "xcshareddata", "swiftpm", "configuration", "mirrors.json")
            if localFileSystem.exists(legacyPath) {
                try localFileSystem.createDirectory(newPath.parentDirectory, recursive: true)
                try localFileSystem.move(from: legacyPath, to: newPath)
            }
            return newPath
        }

        // migrate from legacy location
        let legacyPath = try self.getPackageRoot().appending(components: ".swiftpm", "config")
        let newPath = try Workspace.DefaultLocations.mirrorsConfigurationFile(forRootPackage: self.getPackageRoot())
        if localFileSystem.exists(legacyPath) {
            try localFileSystem.createDirectory(newPath.parentDirectory, recursive: true)
            try localFileSystem.move(from: legacyPath, to: newPath)
        }
        return newPath
    }

    func getRegistriesConfig(sharedConfigurationDirectory: AbsolutePath? = nil) throws -> Workspace.Configuration.Registries {
        let localRegistriesFile = try Workspace.DefaultLocations.registriesConfigurationFile(forRootPackage: self.getPackageRoot())

        let sharedConfigurationDirectory = try sharedConfigurationDirectory ?? self.getSharedConfigurationDirectory()
        let sharedRegistriesFile = sharedConfigurationDirectory.map {
            Workspace.DefaultLocations.registriesConfigurationFile(at: $0)
        }

        return try .init(
            localRegistriesFile: localRegistriesFile,
            sharedRegistriesFile: sharedRegistriesFile,
            fileSystem: localFileSystem
        )
    }

    func getAuthorizationProvider() throws -> AuthorizationProvider? {
        var providers = [AuthorizationProvider]()
        // netrc file has higher specificity than keychain so use it first
        if let netrcConfigFile = try self.getNetrcConfigFile() {
            providers.append(try NetrcAuthorizationProvider(path: netrcConfigFile, fileSystem: localFileSystem))
        }
        
        // TODO: add --no-keychain option to allow opt-out
//#if canImport(Security)
//        providers.append(KeychainAuthorizationProvider(observabilityScope: self.observabilityScope))
//#endif
        
        return providers.isEmpty ? .none : CompositeAuthorizationProvider(providers, observabilityScope: self.observabilityScope)
    }

    func getNetrcConfigFile() throws -> AbsolutePath? {
        guard options.netrc else {
            return .none
        }

        if let configuredPath = options.netrcFilePath {
            guard localFileSystem.exists(configuredPath) else {
                throw StringError("Did not find .netrc file at \(configuredPath).")
            }
            return configuredPath
        }

        // TODO: replace multiroot-data-file with explicit overrides
        let localPath = try (options.multirootPackageDataFile ?? self.getPackageRoot()).appending(component: ".netrc")
        if localFileSystem.exists(localPath) {
            return localPath
        }

        let userHomePath = localFileSystem.homeDirectory.appending(component: ".netrc")
        return localFileSystem.exists(userHomePath) ? userHomePath : .none
    }

    private func getSharedCacheDirectory() throws -> AbsolutePath? {
        if let explicitCachePath = options.cachePath {
            // Create the explicit cache path if necessary
            if !localFileSystem.exists(explicitCachePath) {
                try localFileSystem.createDirectory(explicitCachePath, recursive: true)
            }
            return explicitCachePath
        }

        do {
            return try localFileSystem.getOrCreateSwiftPMCacheDirectory()
        } catch {
            self.observabilityScope.emit(warning: "Failed creating default cache location, \(error)")
            return .none
        }
    }

    private func getSharedConfigurationDirectory() throws -> AbsolutePath? {
        if let explicitConfigPath = options.configPath {
            // Create the explicit config path if necessary
            if !localFileSystem.exists(explicitConfigPath) {
                try localFileSystem.createDirectory(explicitConfigPath, recursive: true)
            }
            return explicitConfigPath
        }

        do {
            return try localFileSystem.getOrCreateSwiftPMConfigDirectory()
        } catch {
            self.observabilityScope.emit(warning: "Failed creating default configuration location, \(error)")
            return .none
        }
    }

    /// Returns the currently active workspace.
    func getActiveWorkspace() throws -> Workspace {
        if let workspace = _workspace {
            return workspace
        }

        let isVerbose = options.verbosity != 0
        let delegate = ToolWorkspaceDelegate(self.outputStream, isVerbose: isVerbose, diagnostics: self.observabilityScope.makeDiagnosticsEngine())
        let provider = GitRepositoryProvider(processSet: processSet)
        let sharedCacheDirectory =  try self.getSharedCacheDirectory()
        let sharedConfigurationDirectory = try self.getSharedConfigurationDirectory()
        let isXcodeBuildSystemEnabled = self.options.buildSystem == .xcode
        let workspace = try Workspace(
            fileSystem: localFileSystem,
            location: .init(
                workingDirectory: buildPath,
                editsDirectory: self.editsDirectory(),
                resolvedVersionsFile: self.resolvedVersionsFile(),
                sharedCacheDirectory: sharedCacheDirectory,
                sharedConfigurationDirectory: sharedConfigurationDirectory
            ),
            mirrors: self.getMirrorsConfig(sharedConfigurationDirectory: sharedConfigurationDirectory).mirrors,
            registries: try self.getRegistriesConfig(sharedConfigurationDirectory: sharedConfigurationDirectory).configuration,
            authorizationProvider: self.getAuthorizationProvider(),
            customManifestLoader: self.getManifestLoader(), // FIXME: doe we really need to customize it?
            customRepositoryProvider: provider, // FIXME: doe we really need to customize it?
            additionalFileRules: isXcodeBuildSystemEnabled ? FileRuleDescription.xcbuildFileTypes : FileRuleDescription.swiftpmFileTypes,
            resolverUpdateEnabled: !options.skipDependencyUpdate,
            resolverPrefetchingEnabled: options.shouldEnableResolverPrefetching,
            resolverTracingEnabled: options.enableResolverTrace,
            sharedRepositoriesCacheEnabled: self.options.useRepositoriesCache,
            delegate: delegate
        )
        _workspace = workspace
        _workspaceDelegate = delegate
        return workspace
    }

    /// Start redirecting the standard output stream to the standard error stream.
    func redirectStdoutToStderr() {
        self.outputStream = TSCBasic.stderrStream
    }

    /// Resolve the dependencies.
    func resolve() throws {
        let workspace = try getActiveWorkspace()
        let root = try getWorkspaceRoot()

        if options.forceResolvedVersions {
            try workspace.resolveBasedOnResolvedVersionsFile(root: root, diagnostics: self.observabilityScope.makeDiagnosticsEngine())
        } else {
            try workspace.resolve(root: root, diagnostics: self.observabilityScope.makeDiagnosticsEngine())
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

    /// Invoke plugins for any reachable targets in the graph, and return a mapping from targets to corresponding evaluation results.
    func invokePlugins(graph: PackageGraph) throws -> [ResolvedTarget: [PluginInvocationResult]] {
        do {
            // Configure the plugin invocation inputs.

            // The `plugins` directory is inside the workspace's main data directory, and contains all temporary
            // files related to all plugins in the workspace.
            let buildEnvironment = try buildParameters().buildEnvironment
            let dataDir = try self.getActiveWorkspace().location.workingDirectory
            let pluginsDir = dataDir.appending(component: "plugins")

            // The `cache` directory is in the plugins directory and is where the plugin script runner caches
            // compiled plugin binaries and any other derived information.
            let cacheDir = pluginsDir.appending(component: "cache")
            let pluginScriptRunner = try DefaultPluginScriptRunner(cacheDir: cacheDir, toolchain: self._hostToolchain.get().configuration)

            // The `outputs` directory contains subdirectories for each combination of package, target, and plugin.
            // Each usage of a plugin has an output directory that is writable by the plugin, where it can write
            // additional files, and to which it can configure tools to write their outputs, etc.
            let outputDir = pluginsDir.appending(component: "outputs")

            // The `tools` directory contains any command line tools (executables) that are available for any commands
            // defined by the executable.
            // FIXME: At the moment we just pass the built products directory for the host. We will need to extend this
            // with a map of the names of tools available to each plugin. In particular this would not work with any
            // binary targets.
            let builtToolsDir = dataDir.appending(components: try self._hostToolchain.get().triple.tripleString, buildEnvironment.configuration.dirname)

            // Create the cache directory, if needed.
            try localFileSystem.createDirectory(cacheDir, recursive: true)

            // Ask the graph to invoke plugins, and return the result.
            let result = try graph.invokePlugins(
                outputDir: outputDir,
                builtToolsDir: builtToolsDir,
                pluginScriptRunner: pluginScriptRunner,
                diagnostics: self.observabilityScope.makeDiagnosticsEngine(),
                fileSystem: localFileSystem
            )
            return result
        }
        catch {
            throw error
        }
    }

    /// Returns the user toolchain to compile the actual product.
    func getToolchain() throws -> UserToolchain {
        return try _destinationToolchain.get()
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
        localFileSystem.exists(buildParameters.llbuildManifest) &&
        localFileSystem.exists(buildParameters.buildDescriptionPath)

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

    func createBuildOperation(explicitProduct: String? = nil, cacheBuildManifest: Bool = true) throws -> BuildOperation {
        // Load a custom package graph which has a special product for REPL.
        let graphLoader = { try self.loadPackageGraph(explicitProduct: explicitProduct) }

        // Construct the build operation.
        let buildOp = try BuildOperation(
            buildParameters: buildParameters(),
            cacheBuildManifest: cacheBuildManifest && self.canUseCachedBuildManifest(),
            packageGraphLoader: graphLoader,
            pluginInvoker: { _ in [:] },
            diagnostics: self.observabilityScope.makeDiagnosticsEngine(),
            outputStream: self.outputStream
        )

        // Save the instance so it can be cancelled from the int handler.
        buildSystemRef.buildSystem = buildOp
        return buildOp
    }

    func createBuildSystem(explicitProduct: String? = nil, buildParameters: BuildParameters? = nil) throws -> BuildSystem {
        let buildSystem: BuildSystem
        switch options.buildSystem {
        case .native:
            let graphLoader = { try self.loadPackageGraph(explicitProduct: explicitProduct) }
            let pluginInvoker = { try self.invokePlugins(graph: $0) }
            buildSystem = try BuildOperation(
                buildParameters: buildParameters ?? self.buildParameters(),
                cacheBuildManifest: self.canUseCachedBuildManifest(),
                packageGraphLoader: graphLoader,
                pluginInvoker: pluginInvoker,
                diagnostics: self.observabilityScope.makeDiagnosticsEngine(),
                outputStream: self.outputStream
            )
        case .xcode:
            let graphLoader = { try self.loadPackageGraph(explicitProduct: explicitProduct, createMultipleTestProducts: true) }
            // FIXME: Implement the custom build command provider also.
            buildSystem = try XcodeBuildSystem(
                buildParameters: buildParameters ?? self.buildParameters(),
                packageGraphLoader: graphLoader,
                isVerbose: verbosity != .concise,
                diagnostics: self.observabilityScope.makeDiagnosticsEngine(),
                outputStream: self.outputStream
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

            /// Checks if stdout stream is tty.
            let isTTY: Bool = {
                let stream: OutputByteStream
                if let threadSafeStream = self.outputStream as? ThreadSafeOutputByteStream {
                    stream = threadSafeStream.stream
                } else {
                    stream = self.outputStream
                }
                guard let fileStream = stream as? LocalFileOutputByteStream else {
                    return false
                }
                return TerminalController.isTTY(fileStream)
            }()

            // Use "apple" as the subdirectory because in theory Xcode build system
            // can be used to build for any Apple platform and it has it's own
            // conventions for build subpaths based on platforms.
            let dataPath = buildPath.appending(
                component: options.buildSystem == .xcode ? "apple" : triple.tripleString)
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
                sanitizers: options.enabledSanitizers,
                enableCodeCoverage: options.shouldEnableCodeCoverage,
                indexStoreMode: options.indexStoreMode.indexStoreMode,
                enableParseableModuleInterfaces: options.shouldEnableParseableModuleInterfaces,
                emitSwiftModuleSeparately: options.emitSwiftModuleSeparately,
                useIntegratedSwiftDriver: options.useIntegratedSwiftDriver,
                useExplicitModuleBuild: options.useExplicitModuleBuild,
                isXcodeBuildSystemEnabled: options.buildSystem == .xcode,
                printManifestGraphviz: options.printManifestGraphviz,
                forceTestDiscovery: options.enableTestDiscovery, // backwards compatibility, remove with --enable-test-discovery
                isTTY: isTTY
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
                destination = try Destination(fromFile: customDestination)
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
                cachePath = try self.getSharedCacheDirectory().map{ Workspace.DefaultLocations.manifestsDirectory(at: $0) }
            }

            var extraManifestFlags = self.options.manifestFlags
            // Disable the implicit concurrency import if the compiler in use supports it to avoid warnings if we are building against an older SDK that does not contain a Concurrency module.
            if SwiftTargetBuildDescription.checkSupportedFrontendFlags(flags: ["disable-implicit-concurrency-module-import"], fs: localFileSystem) {
                extraManifestFlags += ["-Xfrontend", "-disable-implicit-concurrency-module-import"]
            }

            return try ManifestLoader(
                // Always use the host toolchain's resources for parsing manifest.
                toolchain: self._hostToolchain.get().configuration,
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
private func findPackageRoot() -> AbsolutePath? {
    guard var root = localFileSystem.currentWorkingDirectory else {
        return nil
    }
    // FIXME: It would be nice to move this to a generalized method which takes path and predicate and
    // finds the lowest path for which the predicate is true.
    while !localFileSystem.isFile(root.appending(component: Manifest.filename)) {
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

/// A wrapper to hold the build system so we can use it inside
/// the int. handler without requiring to initialize it.
final class BuildSystemRef {
    var buildSystem: BuildSystem?
}

extension Diagnostic.Message {
    static func unsupportedFlag(_ flag: String) -> Diagnostic.Message {
        .warning("\(flag) is an *unsupported* option which can be removed at any time; do not rely on it")
    }
}

extension DispatchTimeInterval {
    var descriptionInSeconds: String {
        switch self {
        case .seconds(let value):
            return "\(value)s"
        case .milliseconds(let value):
            return String(format: "%.2f", Double(value)/Double(1000)) + "s"
        case .microseconds(let value):
            return String(format: "%.2f", Double(value)/Double(1_000_000)) + "s"
        case .nanoseconds(let value):
            return String(format: "%.2f", Double(value)/Double(1_000_000_000)) + "s"
        case .never:
            return "n/a"
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        @unknown default:
            return "n/a"
#endif
        }
    }
}


// MARK: - Diagnostics

private struct SwiftToolObservability: ObservabilityHandlerProvider, DiagnosticsHandler {
    var diagnosticsHandler: DiagnosticsHandler { self }

    func handleDiagnostic(scope: ObservabilityScope, diagnostic: Basics.Diagnostic) {
        // TODO: do something useful with scope
        diagnostic.print()
    }
}

extension Basics.Diagnostic {
    func print() {
        let writer = InteractiveWriter.stderr

        if let diagnosticPrefix = self.metadata?.diagnosticPrefix {
            writer.write(diagnosticPrefix)
            writer.write(": ")
        }

        switch self.severity {
        case .error:
            writer.write("error: ", inColor: .red, bold: true)
        case .warning:
            writer.write("warning: ", inColor: .yellow, bold: true)
        case .info:
            writer.write("info: ", inColor: .white, bold: true)
        case .debug:
            writer.write("info: ", inColor: .white, bold: true)
        }

        writer.write(self.message)
        writer.write("\n")
    }
}

/// This class is used to write on the underlying stream.
///
/// If underlying stream is a not tty, the string will be written in without any
/// formatting.
private final class InteractiveWriter {

    /// The standard error writer.
    static let stderr = InteractiveWriter(stream: stderrStream)

    /// The standard output writer.
    static let stdout = InteractiveWriter(stream: stdoutStream)

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
        if let term = term {
            term.write(string, inColor: color, bold: bold)
        } else {
            stream <<< string
            stream.flush()
        }
    }
}

// FIXME: this is for backwards compatibility with existing diagnostics printing format
// we should remove this as we make use of the new scope and metadata to provide better contextual information
extension ObservabilityMetadata {
    fileprivate var diagnosticPrefix: String? {
        if let legacyLocation = self.legacyLocation {
            return legacyLocation
        } else if let packageIdentity = self.packageIdentity, let packageLocation = self.packageLocation {
            return "'\(packageIdentity)' \(packageLocation)"
        } else {
            return .none
        }
    }
}
