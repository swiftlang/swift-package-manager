//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import Dispatch
@_implementationOnly import DriverSupport
import class Foundation.NSLock
import class Foundation.ProcessInfo
import PackageGraph
import PackageLoading
import PackageModel
import SPMBuildCore
import Workspace

#if canImport(WinSDK)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import struct TSCBasic.AbsolutePath
import func TSCBasic.exec
import protocol TSCBasic.FileSystem
import var TSCBasic.localFileSystem
import protocol TSCBasic.OutputByteStream
import class TSCBasic.Process
import enum TSCBasic.ProcessEnv
import var TSCBasic.stderrStream
import class TSCBasic.TerminalController
import class TSCBasic.ThreadSafeOutputByteStream

import class TSCUtility.MultiLineNinjaProgressAnimation
import class TSCUtility.NinjaProgressAnimation
import class TSCUtility.PercentProgressAnimation
import protocol TSCUtility.ProgressAnimationProtocol
import var TSCUtility.verbosity

typealias Diagnostic = Basics.Diagnostic

public struct ToolWorkspaceConfiguration {
    let wantsMultipleTestProducts: Bool
    let wantsREPLProduct: Bool

    public init(wantsMultipleTestProducts: Bool = false,
         wantsREPLProduct: Bool = false) {
        self.wantsMultipleTestProducts = wantsMultipleTestProducts
        self.wantsREPLProduct = wantsREPLProduct
    }
}

public typealias WorkspaceDelegateProvider = (_ observabilityScope: ObservabilityScope, _ outputHandler: @escaping (String, Bool) -> Void, _ progressHandler: @escaping (Int64, Int64, String?) -> Void) -> WorkspaceDelegate
public typealias WorkspaceLoaderProvider = (_ fileSystem: FileSystem, _ observabilityScope: ObservabilityScope) -> WorkspaceLoader

public protocol SwiftCommand: ParsableCommand {
    var globalOptions: GlobalOptions { get }
    var toolWorkspaceConfiguration: ToolWorkspaceConfiguration { get }
    var workspaceDelegateProvider: WorkspaceDelegateProvider { get }
    var workspaceLoaderProvider: WorkspaceLoaderProvider { get }

    func buildSystemProvider(_ swiftTool: SwiftTool) throws -> BuildSystemProvider
    func run(_ swiftTool: SwiftTool) throws
}

extension SwiftCommand {
    public func run() throws {
        let swiftTool = try SwiftTool(
            options: globalOptions,
            toolWorkspaceConfiguration: self.toolWorkspaceConfiguration,
            workspaceDelegateProvider: self.workspaceDelegateProvider,
            workspaceLoaderProvider: self.workspaceLoaderProvider
        )
        swiftTool.buildSystemProvider = try buildSystemProvider(swiftTool)
        var toolError: Error? = .none
        do {
            try self.run(swiftTool)
            if swiftTool.observabilityScope.errorsReported || swiftTool.executionStatus == .failure {
                throw ExitCode.failure
            }
        } catch {
            toolError = error
        }

        // wait for all observability items to process
        swiftTool.waitForObservabilityEvents(timeout: .now() + 5)

        if let error = toolError {
            throw error
        }
    }

    public static var _errorLabel: String { "error" }

    public var toolWorkspaceConfiguration: ToolWorkspaceConfiguration {
        return .init()
    }
}

public final class SwiftTool {
    #if os(Windows)
    // unfortunately this is needed for C callback handlers used by Windows shutdown handler
    static var cancellator: Cancellator?
    #endif

    /// The original working directory.
    public let originalWorkingDirectory: AbsolutePath

    /// The options of this tool.
    public let options: GlobalOptions

    /// Path to the root package directory, nil if manifest is not found.
    private let packageRoot: AbsolutePath?

    /// Helper function to get package root or throw error if it is not found.
    public func getPackageRoot() throws -> AbsolutePath {
        guard let packageRoot = packageRoot else {
            throw StringError("Could not find \(Manifest.filename) in this directory or any of its parent directories.")
        }
        return packageRoot
    }

    /// Get the current workspace root object.
    public func getWorkspaceRoot() throws -> PackageGraphRootInput {
        let packages: [AbsolutePath]

        if let workspace = options.locations.multirootPackageDataFile {
            packages = try self.workspaceLoaderProvider(self.fileSystem, self.observabilityScope).load(workspace: workspace)
        } else {
            packages = [try getPackageRoot()]
        }

        return PackageGraphRootInput(packages: packages)
    }

    /// Scratch space (.build) directory.
    public let scratchDirectory: AbsolutePath

    /// Path to the shared security directory
    public let sharedSecurityDirectory: AbsolutePath?

    /// Path to the shared cache directory
    public let sharedCacheDirectory: AbsolutePath?

    /// Path to the shared configuration directory
    public let sharedConfigurationDirectory: AbsolutePath?

    /// Path to the cross-compilation SDK directory.
    public let sharedCrossCompilationDestinationsDirectory: AbsolutePath?

    /// Cancellator to handle cancellation of outstanding work when handling SIGINT
    public let cancellator: Cancellator

    /// The execution status of the tool.
    public var executionStatus: ExecutionStatus = .success

    /// Holds the currently active workspace.
    ///
    /// It is not initialized in init() because for some of the commands like package init , usage etc,
    /// workspace is not needed, in-fact it would be an error to ask for the workspace object
    /// for package init because the Manifest file should *not* present.
    private var _workspace: Workspace?
    private var _workspaceDelegate: WorkspaceDelegate?

    private let observabilityHandler: SwiftToolObservabilityHandler

    /// The observability scope to emit diagnostics event on
    public let observabilityScope: ObservabilityScope

    /// The min severity at which to log diagnostics
    public let logLevel: Basics.Diagnostic.Severity

    /// The file system in use
    public let fileSystem: FileSystem

    /// Provider which can create a `WorkspaceDelegate` if needed.
    private let workspaceDelegateProvider: WorkspaceDelegateProvider

    /// Provider which can create a `WorkspaceLoader` if needed.
    private let workspaceLoaderProvider: WorkspaceLoaderProvider

    private let toolWorkspaceConfiguration: ToolWorkspaceConfiguration

    fileprivate var buildSystemProvider: BuildSystemProvider?

    /// Create an instance of this tool.
    ///
    /// - parameter options: The command line options to be passed to this tool.
    public convenience init(options: GlobalOptions, toolWorkspaceConfiguration: ToolWorkspaceConfiguration = .init(), workspaceDelegateProvider: @escaping WorkspaceDelegateProvider, workspaceLoaderProvider: @escaping WorkspaceLoaderProvider) throws {
        // output from background activities goes to stderr, this includes diagnostics and output from build operations,
        // package resolution that take place as part of another action
        // CLI commands that have user facing output, use stdout directly to emit the final result
        // this means that the build output from "swift build" goes to stdout
        // but the build output from "swift test" goes to stderr, while the tests output go to stdout
        try self.init(outputStream: TSCBasic.stderrStream, options: options, toolWorkspaceConfiguration: toolWorkspaceConfiguration, workspaceDelegateProvider: workspaceDelegateProvider, workspaceLoaderProvider: workspaceLoaderProvider)
    }

    // marked internal for testing
    internal init(outputStream: OutputByteStream, options: GlobalOptions, toolWorkspaceConfiguration: ToolWorkspaceConfiguration, workspaceDelegateProvider: @escaping WorkspaceDelegateProvider, workspaceLoaderProvider: @escaping WorkspaceLoaderProvider) throws {
        self.fileSystem = localFileSystem
        // first, bootstrap the observability system
        self.logLevel = options.logging.logLevel
        self.observabilityHandler = SwiftToolObservabilityHandler(outputStream: outputStream, logLevel: self.logLevel)
        let observabilitySystem = ObservabilitySystem(self.observabilityHandler)
        self.observabilityScope = observabilitySystem.topScope
        self.toolWorkspaceConfiguration = toolWorkspaceConfiguration
        self.workspaceDelegateProvider = workspaceDelegateProvider
        self.workspaceLoaderProvider = workspaceLoaderProvider

        let cancellator = Cancellator(observabilityScope: self.observabilityScope)

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
            if let packagePath = options.locations.packageDirectory {
                try ProcessEnv.chdir(packagePath)
            }

            #if os(Windows)
            // set shutdown handler to terminate sub-processes, etc
            SwiftTool.cancellator = cancellator
            _ = SetConsoleCtrlHandler({ _ in
                // Terminate all processes on receiving an interrupt signal.
                try? SwiftTool.cancellator?.cancel(deadline: .now() + .seconds(30))

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
                try? cancellator.cancel(deadline: .now() + .seconds(30))

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

            self.cancellator = cancellator
        } catch {
            self.observabilityScope.emit(error)
            throw ExitCode.failure
        }

        // Create local variables to use while finding build path to avoid capture self before init error.
        let packageRoot = findPackageRoot(fileSystem: fileSystem)

        self.packageRoot = packageRoot
        self.scratchDirectory =
            try getEnvBuildPath(workingDir: cwd) ??
            options.locations.scratchDirectory ??
            (packageRoot ?? cwd).appending(component: ".build")

        // make sure common directories are created
        self.sharedSecurityDirectory = try getSharedSecurityDirectory(options: self.options, fileSystem: fileSystem)
        self.sharedConfigurationDirectory = try getSharedConfigurationDirectory(options: self.options, fileSystem: fileSystem)
        self.sharedCacheDirectory = try getSharedCacheDirectory(options: self.options, fileSystem: fileSystem)
        self.sharedCrossCompilationDestinationsDirectory = try getSharedCrossCompilationDestinationsDirectory(options: self.options, fileSystem: fileSystem)

        // set global process logging handler
        Process.loggingHandler = { self.observabilityScope.emit(debug: $0) }
    }

    static func postprocessArgParserResult(options: GlobalOptions, observabilityScope: ObservabilityScope) throws {
        if options.locations.multirootPackageDataFile != nil {
            observabilityScope.emit(.unsupportedFlag("--multiroot-data-file"))
        }

        if options.build.useExplicitModuleBuild && !options.build.useIntegratedSwiftDriver {
            observabilityScope.emit(error: "'--experimental-explicit-module-build' option requires '--use-integrated-swift-driver'")
        }

        if !options.build.archs.isEmpty && options.build.customCompileTriple != nil {
            observabilityScope.emit(.mutuallyExclusiveArgumentsError(arguments: ["--arch", "--triple"]))
        }

        // --enable-test-discovery should never be called on darwin based platforms
        #if canImport(Darwin)
        if options.build.enableTestDiscovery {
            observabilityScope.emit(warning: "'--enable-test-discovery' option is deprecated; tests are automatically discovered on all platforms")
        }
        #endif

        if options.caching.shouldDisableManifestCaching {
            observabilityScope.emit(warning: "'--disable-package-manifest-caching' option is deprecated; use '--manifest-caching' instead")
        }

        if let _ = options.security.netrcFilePath, options.security.netrc == false {
            observabilityScope.emit(.mutuallyExclusiveArgumentsError(arguments: ["--disable-netrc", "--netrc-file"]))
        }
    }

    func waitForObservabilityEvents(timeout: DispatchTime) {
        self.observabilityHandler.wait(timeout: timeout)
    }

    /// Returns the currently active workspace.
    public func getActiveWorkspace(emitDeprecatedConfigurationWarning: Bool = false) throws -> Workspace {
        if let workspace = _workspace {
            return workspace
        }

        let delegate = self.workspaceDelegateProvider(self.observabilityScope, self.observabilityHandler.print, self.observabilityHandler.progress)
        let isXcodeBuildSystemEnabled = self.options.build.buildSystem == .xcode
        let workspace = try Workspace(
            fileSystem: self.fileSystem,
            location: .init(
                scratchDirectory: self.scratchDirectory,
                editsDirectory: self.getEditsDirectory(),
                resolvedVersionsFile: self.getResolvedVersionsFile(),
                localConfigurationDirectory: try self.getLocalConfigurationDirectory(),
                sharedConfigurationDirectory: self.sharedConfigurationDirectory,
                sharedSecurityDirectory: self.sharedSecurityDirectory,
                sharedCacheDirectory: self.sharedCacheDirectory,
                emitDeprecatedConfigurationWarning: emitDeprecatedConfigurationWarning
            ),
            authorizationProvider: self.getAuthorizationProvider(),
            configuration: .init(
                skipDependenciesUpdates: options.resolver.skipDependencyUpdate,
                prefetchBasedOnResolvedFile: options.resolver.shouldEnableResolverPrefetching,
                shouldCreateMultipleTestProducts: toolWorkspaceConfiguration.wantsMultipleTestProducts || options.build.buildSystem == .xcode,
                createREPLProduct: toolWorkspaceConfiguration.wantsREPLProduct,
                additionalFileRules: isXcodeBuildSystemEnabled ? FileRuleDescription.xcbuildFileTypes : FileRuleDescription.swiftpmFileTypes,
                sharedDependenciesCacheEnabled: self.options.caching.useDependenciesCache,
                fingerprintCheckingMode: self.options.security.fingerprintCheckingMode,
                sourceControlToRegistryDependencyTransformation: self.options.resolver.sourceControlToRegistryDependencyTransformation.workspaceConfiguration,
                restrictImports: .none
            ),
            cancellator: self.cancellator,
            initializationWarningHandler: { self.observabilityScope.emit(warning: $0) },
            customHostToolchain: self.getHostToolchain(),
            customManifestLoader: self.getManifestLoader(),
            delegate: delegate
        )
        _workspace = workspace
        _workspaceDelegate = delegate
        return workspace
    }

    private func getEditsDirectory() throws -> AbsolutePath {
        // TODO: replace multiroot-data-file with explicit overrides
        if let multiRootPackageDataFile = options.locations.multirootPackageDataFile {
            return multiRootPackageDataFile.appending(component: "Packages")
        }
        return try Workspace.DefaultLocations.editsDirectory(forRootPackage: self.getPackageRoot())
    }

    private func getResolvedVersionsFile() throws -> AbsolutePath {
        // TODO: replace multiroot-data-file with explicit overrides
        if let multiRootPackageDataFile = options.locations.multirootPackageDataFile {
            return multiRootPackageDataFile.appending(components: "xcshareddata", "swiftpm", "Package.resolved")
        }
        return try Workspace.DefaultLocations.resolvedVersionsFile(forRootPackage: self.getPackageRoot())
    }

    internal func getLocalConfigurationDirectory() throws -> AbsolutePath {
        // Otherwise, use the default path.
        // TODO: replace multiroot-data-file with explicit overrides
        if let multiRootPackageDataFile = options.locations.multirootPackageDataFile {
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

    public func getAuthorizationProvider() throws -> AuthorizationProvider? {
        var authorization = Workspace.Configuration.Authorization.default
        if !options.security.netrc {
            authorization.netrc = .disabled
        } else if let configuredPath = options.security.netrcFilePath {
            authorization.netrc = .custom(configuredPath)
        } else {
            let rootPath = try options.locations.multirootPackageDataFile ?? self.getPackageRoot()
            authorization.netrc = .workspaceAndUser(rootPath: rootPath)
        }

        #if canImport(Security)
        authorization.keychain = self.options.security.keychain ? .enabled : .disabled
        #endif

        return try authorization.makeAuthorizationProvider(fileSystem: self.fileSystem, observabilityScope: self.observabilityScope)
    }

    /// Resolve the dependencies.
    public func resolve() throws {
        let workspace = try getActiveWorkspace()
        let root = try getWorkspaceRoot()

        if options.resolver.forceResolvedVersions {
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
    public func loadPackageGraph(
        explicitProduct: String? = nil,
        testEntryPointPath: AbsolutePath? = nil
    ) throws -> PackageGraph {
        do {
            let workspace = try getActiveWorkspace()

            // Fetch and load the package graph.
            let graph = try workspace.loadPackageGraph(
                rootInput: getWorkspaceRoot(),
                explicitProduct: explicitProduct,
                forceResolvedVersions: options.resolver.forceResolvedVersions,
                testEntryPointPath: testEntryPointPath,
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

    public func getPluginScriptRunner(customPluginsDir: AbsolutePath? = .none) throws -> PluginScriptRunner {
        let pluginsDir = try customPluginsDir ?? self.getActiveWorkspace().location.pluginWorkingDirectory
        let cacheDir = pluginsDir.appending(component: "cache")
        let pluginScriptRunner = try DefaultPluginScriptRunner(
            fileSystem: self.fileSystem,
            cacheDir: cacheDir,
            toolchain: self.getHostToolchain(),
            enableSandbox: !self.options.security.shouldDisableSandbox,
            verboseOutput: self.logLevel <= .info
        )
        // register the plugin runner system with the cancellation handler
        self.cancellator.register(name: "plugin runner", handler: pluginScriptRunner)
        return pluginScriptRunner
    }

    /// Returns the user toolchain to compile the actual product.
    public func getDestinationToolchain() throws -> UserToolchain {
        return try _destinationToolchain.get()
    }

    public func getHostToolchain() throws -> UserToolchain {
        return try _hostToolchain.get()
    }

    func getManifestLoader() throws -> ManifestLoader {
        return try _manifestLoader.get()
    }

    public func canUseCachedBuildManifest() throws -> Bool {
        if !self.options.caching.cacheBuildManifest {
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
    public func createBuildSystem(
        explicitBuildSystem: BuildSystemProvider.Kind? = .none,
        explicitProduct: String? = .none,
        cacheBuildManifest: Bool = true,
        customBuildParameters: BuildParameters? = .none,
        customPackageGraphLoader: (() throws -> PackageGraph)? = .none,
        customOutputStream: OutputByteStream? = .none,
        customLogLevel: Basics.Diagnostic.Severity? = .none,
        customObservabilityScope: ObservabilityScope? = .none
    ) throws -> BuildSystem {
        guard let buildSystemProvider = buildSystemProvider else {
            fatalError("build system provider not initialized")
        }

        let buildSystem = try buildSystemProvider.createBuildSystem(
            kind: explicitBuildSystem ?? options.build.buildSystem,
            explicitProduct: explicitProduct,
            cacheBuildManifest: cacheBuildManifest,
            customBuildParameters: customBuildParameters,
            customPackageGraphLoader: customPackageGraphLoader,
            customOutputStream: customOutputStream,
            customLogLevel: customLogLevel,
            customObservabilityScope: customObservabilityScope
        )

        // register the build system with the cancellation handler
        self.cancellator.register(name: "build system", handler: buildSystem.cancel)
        return buildSystem
    }

    /// Return the build parameters.
    public func buildParameters() throws -> BuildParameters {
        return try _buildParameters.get()
    }

    private lazy var _buildParameters: Result<BuildParameters, Swift.Error> = {
        return Result(catching: {
            let toolchain = try self.getDestinationToolchain()
            let triple = toolchain.triple

            // Use "apple" as the subdirectory because in theory Xcode build system
            // can be used to build for any Apple platform and it has it's own
            // conventions for build subpaths based on platforms.
            let dataPath = self.scratchDirectory.appending(
                component: options.build.buildSystem == .xcode ? "apple" : triple.platformBuildPathComponent())
            return BuildParameters(
                dataPath: dataPath,
                configuration: options.build.configuration,
                toolchain: toolchain,
                destinationTriple: triple,
                archs: options.build.archs,
                flags: options.build.buildFlags,
                xcbuildFlags: options.build.xcbuildFlags,
                jobs: options.build.jobs ?? UInt32(ProcessInfo.processInfo.activeProcessorCount),
                shouldLinkStaticSwiftStdlib: options.linker.shouldLinkStaticSwiftStdlib,
                canRenameEntrypointFunctionName: DriverSupport.checkSupportedFrontendFlags(
                    flags: ["entry-point-function-name"], fileSystem: self.fileSystem
                ),
                sanitizers: options.build.enabledSanitizers,
                enableCodeCoverage: false, // set by test commands when appropriate
                indexStoreMode: options.build.indexStoreMode.buildParameter,
                enableParseableModuleInterfaces: options.build.shouldEnableParseableModuleInterfaces,
                emitSwiftModuleSeparately: options.build.emitSwiftModuleSeparately,
                useIntegratedSwiftDriver: options.build.useIntegratedSwiftDriver,
                useExplicitModuleBuild: options.build.useExplicitModuleBuild,
                isXcodeBuildSystemEnabled: options.build.buildSystem == .xcode,
                forceTestDiscovery: options.build.enableTestDiscovery, // backwards compatibility, remove with --enable-test-discovery
                testEntryPointPath: options.build.testEntryPointPath,
                explicitTargetDependencyImportCheckingMode: options.build.explicitTargetDependencyImportCheck.modeParameter,
                linkerDeadStrip: options.linker.linkerDeadStrip,
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
            if let customDestination = self.options.locations.customCompileDestination {
                destination = try Destination(fromFile: customDestination, fileSystem: self.fileSystem)
            } else if let target = self.options.build.customCompileTriple,
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
        if let triple = self.options.build.customCompileTriple {
            destination.targetTriple = triple
        }
        if let binDir = self.options.build.customCompileToolchain {
            destination.toolchainBinDir = binDir.appending(components: "usr", "bin")
        }
        if let sdk = self.options.build.customCompileSDK {
            destination.sdkRootDir = sdk
        }
        destination.archs = options.build.archs

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
            switch (self.options.caching.shouldDisableManifestCaching, self.options.caching.manifestCachingMode) {
            case (true, _):
                // backwards compatibility
                cachePath = .none
            case (false, .none):
                cachePath = .none
            case (false, .local):
                cachePath = self.scratchDirectory
            case (false, .shared):
                cachePath = self.sharedCacheDirectory.map{ Workspace.DefaultLocations.manifestsDirectory(at: $0) }
            }

            var extraManifestFlags = self.options.build.manifestFlags
            // Disable the implicit concurrency import if the compiler in use supports it to avoid warnings if we are building against an older SDK that does not contain a Concurrency module.
            if DriverSupport.checkSupportedFrontendFlags(flags: ["disable-implicit-concurrency-module-import"], fileSystem: self.fileSystem) {
                extraManifestFlags += ["-Xfrontend", "-disable-implicit-concurrency-module-import"]
            }
            // Disable the implicit string processing import if the compiler in use supports it to avoid warnings if we are building against an older SDK that does not contain a StringProcessing module.
            if DriverSupport.checkSupportedFrontendFlags(flags: ["disable-implicit-string-processing-module-import"], fileSystem: self.fileSystem) {
                extraManifestFlags += ["-Xfrontend", "-disable-implicit-string-processing-module-import"]
            }

            if self.logLevel <= .info {
                extraManifestFlags.append("-v")
            }

            return try ManifestLoader(
                // Always use the host toolchain's resources for parsing manifest.
                toolchain: self.getHostToolchain(),
                isManifestSandboxEnabled: !self.options.security.shouldDisableSandbox,
                cacheDir: cachePath,
                extraManifestFlags: extraManifestFlags,
                restrictImports: nil
            )
        })
    }()

    /// An enum indicating the execution status of run commands.
    public enum ExecutionStatus {
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
private func getEnvBuildPath(workingDir: AbsolutePath) throws -> AbsolutePath? {
    // Don't rely on build path from env for SwiftPM's own tests.
    guard ProcessEnv.vars["SWIFTPM_TESTS_MODULECACHE"] == nil else { return nil }
    guard let env = ProcessEnv.vars["SWIFTPM_BUILD_DIR"] else { return nil }
    return try AbsolutePath(validating: env, relativeTo: workingDir)
}


private func getSharedSecurityDirectory(options: GlobalOptions, fileSystem: FileSystem) throws -> AbsolutePath? {
    if let explicitSecurityDirectory = options.locations.securityDirectory {
        // Create the explicit security path if necessary
        if !fileSystem.exists(explicitSecurityDirectory) {
            try fileSystem.createDirectory(explicitSecurityDirectory, recursive: true)
        }
        return explicitSecurityDirectory
    } else {
        // further validation is done in workspace
        return try fileSystem.swiftPMSecurityDirectory
    }
}

private func getSharedConfigurationDirectory(options: GlobalOptions, fileSystem: FileSystem) throws -> AbsolutePath? {
    if let explicitConfigurationDirectory = options.locations.configurationDirectory {
        // Create the explicit config path if necessary
        if !fileSystem.exists(explicitConfigurationDirectory) {
            try fileSystem.createDirectory(explicitConfigurationDirectory, recursive: true)
        }
        return explicitConfigurationDirectory
    } else {
        // further validation is done in workspace
        return try fileSystem.swiftPMConfigurationDirectory
    }
}

private func getSharedCacheDirectory(options: GlobalOptions, fileSystem: FileSystem) throws -> AbsolutePath? {
    if let explicitCacheDirectory = options.locations.cacheDirectory {
        // Create the explicit cache path if necessary
        if !fileSystem.exists(explicitCacheDirectory) {
            try fileSystem.createDirectory(explicitCacheDirectory, recursive: true)
        }
        return explicitCacheDirectory
    } else {
        // further validation is done in workspace
        return try fileSystem.swiftPMCacheDirectory
    }
}

private func getSharedCrossCompilationDestinationsDirectory(
    options: GlobalOptions,
    fileSystem: FileSystem
) throws -> AbsolutePath? {
    if let explicitDestinationsDirectory = options.locations.crossCompilationDestinationsDirectory {
        // Create the explicit destinations path if necessary
        if !fileSystem.exists(explicitDestinationsDirectory) {
            try fileSystem.createDirectory(explicitDestinationsDirectory, recursive: true)
        }
        return explicitDestinationsDirectory
    } else {
        return try fileSystem.swiftPMCrossCompilationDestinationsDirectory
    }
}

extension Basics.Diagnostic {
    static func unsupportedFlag(_ flag: String) -> Self {
        .warning("\(flag) is an *unsupported* option which can be removed at any time; do not rely on it")
    }
}

// MARK: - Support for loading external workspaces

public protocol WorkspaceLoader {
    func load(workspace: AbsolutePath) throws -> [AbsolutePath]
}

// MARK: - Diagnostics

extension SwiftTool {
    // FIXME: deprecate these one we are further along refactoring the call sites that use it
    /// The stream to print standard output on.
    public var outputStream: OutputByteStream {
        self.observabilityHandler.outputStream
    }
}

extension Workspace.ManagedDependency {
    fileprivate var isEdited: Bool {
        if case .edited = self.state { return true }
        return false
    }
}

extension LoggingOptions {
    fileprivate var logLevel: Diagnostic.Severity {
        if self.verbose {
            return .info
        } else if self.veryVerbose {
            return .debug
        } else {
            return .warning
        }
    }
}

extension ResolverOptions.SourceControlToRegistryDependencyTransformation {
    fileprivate var workspaceConfiguration: WorkspaceConfiguration.SourceControlToRegistryDependencyTransformation {
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

extension BuildOptions.StoreMode {
    fileprivate var buildParameter: BuildParameters.IndexStoreMode {
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

extension BuildOptions.TargetDependencyImportCheckingMode {
    fileprivate var modeParameter: BuildParameters.TargetDependencyImportCheckingMode {
        switch self {
        case .none:
            return .none
        case .warn:
            return .warn
        case .error:
            return .error
        }
    }
}

public extension Basics.Diagnostic {
    static func mutuallyExclusiveArgumentsError(arguments: [String]) -> Self {
        .error(arguments.map{ "'\($0)'" }.spm_localizedJoin(type: .conjunction) + " are mutually exclusive")
    }
}
