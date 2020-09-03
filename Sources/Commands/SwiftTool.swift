/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import func Foundation.NSUserName
import class Foundation.ProcessInfo
import Dispatch

import ArgumentParser
import TSCLibc
import TSCBasic
import TSCUtility

import PackageModel
import PackageGraph
import SourceControl
import SPMBuildCore
import Build
import XCBuildSupport
import Workspace

typealias Diagnostic = TSCBasic.Diagnostic

private class ToolWorkspaceDelegate: WorkspaceDelegate {

    /// The stream to use for reporting progress.
    private let stdoutStream: ThreadSafeOutputByteStream

    /// The progress animation for downloads.
    private let downloadAnimation: NinjaProgressAnimation

    /// Wether the tool is in a verbose mode.
    private let isVerbose: Bool

    private struct DownloadProgress {
        let bytesDownloaded: Int64
        let totalBytesToDownload: Int64
    }

    /// The progress of each individual downloads.
    private var downloadProgress: [String: DownloadProgress] = [:]

    private let queue = DispatchQueue(label: "org.swift.swiftpm.commands.tool-workspace-delegate")
    private let diagnostics: DiagnosticsEngine

    init(_ stdoutStream: OutputByteStream, isVerbose: Bool, diagnostics: DiagnosticsEngine) {
        // FIXME: Implement a class convenience initializer that does this once they are supported
        // https://forums.swift.org/t/allow-self-x-in-class-convenience-initializers/15924
        self.stdoutStream = stdoutStream as? ThreadSafeOutputByteStream ?? ThreadSafeOutputByteStream(stdoutStream)
        self.downloadAnimation = NinjaProgressAnimation(stream: self.stdoutStream)
        self.isVerbose = isVerbose
        self.diagnostics = diagnostics
    }

    func fetchingWillBegin(repository: String) {
        stdoutStream <<< "Fetching \(repository)"
        stdoutStream <<< "\n"
        stdoutStream.flush()
    }

    func fetchingDidFinish(repository: String, diagnostic: Diagnostic?) {
    }

    func repositoryWillUpdate(_ repository: String) {
        stdoutStream <<< "Updating \(repository)"
        stdoutStream <<< "\n"
        stdoutStream.flush()
    }

    func repositoryDidUpdate(_ repository: String) {
    }

    func dependenciesUpToDate() {
        stdoutStream <<< "Everything is already up-to-date"
        stdoutStream <<< "\n"
        stdoutStream.flush()
    }

    func cloning(repository: String) {
        stdoutStream <<< "Cloning \(repository)"
        stdoutStream <<< "\n"
        stdoutStream.flush()
    }

    func checkingOut(repository: String, atReference reference: String, to path: AbsolutePath) {
        stdoutStream <<< "Resolving \(repository) at \(reference)"
        stdoutStream <<< "\n"
        stdoutStream.flush()
    }

    func removing(repository: String) {
        stdoutStream <<< "Removing \(repository)"
        stdoutStream <<< "\n"
        stdoutStream.flush()
    }

    func warning(message: String) {
        // FIXME: We should emit warnings through the diagnostic engine.
        stdoutStream <<< "warning: " <<< message
        stdoutStream <<< "\n"
        stdoutStream.flush()
    }

    func willResolveDependencies(reason: WorkspaceResolveReason) {
        guard isVerbose else { return }

        stdoutStream <<< "Running resolver because "

        switch reason {
        case .forced:
            stdoutStream <<< "it was forced"
        case .newPackages(let packages):
            let dependencies = packages.lazy.map({ "'\($0.path)'" }).joined(separator: ", ")
            stdoutStream <<< "the following dependencies were added: \(dependencies)"
        case .packageRequirementChange(let package, let state, let requirement):
            stdoutStream <<< "dependency '\(package.name)' was "

            switch state {
            case .checkout(let checkoutState)?:
                let requirement = checkoutState.requirement()
                switch requirement {
                case .versionSet(.exact(let version)):
                    stdoutStream <<< "resolved to '\(version)'"
                case .versionSet(_):
                    // Impossible
                    break
                case .revision(let revision):
                    stdoutStream <<< "resolved to '\(revision)'"
                case .unversioned:
                    stdoutStream <<< "unversioned"
                }
            case .edited?:
                stdoutStream <<< "edited"
            case .local?:
                stdoutStream <<< "versioned"
            case nil:
                stdoutStream <<< "root"
            }

            stdoutStream <<< " but now has a "

            switch requirement {
            case .versionSet:
                stdoutStream <<< "different version-based"
            case .revision:
                stdoutStream <<< "different revision-based"
            case .unversioned:
                stdoutStream <<< "unversioned"
            }

            stdoutStream <<< " requirement."
        default:
            stdoutStream <<< " requirements have changed."
        }

        stdoutStream <<< "\n"
        stdoutStream.flush()
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
}

/// Handler for the main DiagnosticsEngine used by the SwiftTool class.
private final class DiagnosticsEngineHandler {
    /// The standard output stream.
    var stdoutStream = TSCBasic.stdoutStream

    /// The default instance.
    static let `default` = DiagnosticsEngineHandler()

    private init() {}

    func diagnosticsHandler(_ diagnostic: Diagnostic) {
        print(diagnostic: diagnostic, stdoutStream: stderrStream)
    }
}

protocol SwiftCommand: ParsableCommand {
    var swiftOptions: SwiftToolOptions { get }
  
    func run(_ swiftTool: SwiftTool) throws
}

extension SwiftCommand {
    public func run() throws {
        let swiftTool = try SwiftTool(options: swiftOptions)
        try self.run(swiftTool)
        if swiftTool.diagnostics.hasErrors || swiftTool.executionStatus == .failure {
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
            throw Error.rootManifestFileNotFound
        }
        return packageRoot
    }

    /// Get the current workspace root object.
    func getWorkspaceRoot() throws -> PackageGraphRootInput {
        let packages: [AbsolutePath]

        if let workspace = options.multirootPackageDataFile {
            packages = try XcodeWorkspaceLoader(diagnostics: diagnostics).load(workspace: workspace)
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

    /// The diagnostics engine.
    let diagnostics: DiagnosticsEngine = DiagnosticsEngine(
        handlers: [DiagnosticsEngineHandler.default.diagnosticsHandler])

    /// The execution status of the tool.
    var executionStatus: ExecutionStatus = .success

    /// The stream to print standard output on.
    fileprivate(set) var stdoutStream: OutputByteStream = TSCBasic.stdoutStream

    /// Create an instance of this tool.
    ///
    /// - parameter args: The command line arguments to be passed to this tool.
    public init(options: SwiftToolOptions) throws {
        // Capture the original working directory ASAP.
        guard let cwd = localFileSystem.currentWorkingDirectory else {
            diagnostics.emit(error: "couldn't determine the current working directory")
            throw ExitCode.failure
        }
        originalWorkingDirectory = cwd

        do {
            try Self.postprocessArgParserResult(options: options, diagnostics: diagnostics)
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
              #elseif os(macOS)
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
            handle(error: error)
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
        
        if options.netrcFilePath != nil {
            // --netrc-file option only supported on macOS >=10.13
            #if os(macOS)
            if #available(macOS 10.13, *) {
                // ok, check succeeds
            } else {
                diagnostics.emit(error: "'--netrc-file' option is only supported on macOS >=10.13")
            }
            #else
            diagnostics.emit(error: "'--netrc-file' option is only supported on macOS >=10.13")
            #endif
        }
    }

    func editablesPath() throws -> AbsolutePath {
        if let multiRootPackageDataFile = options.multirootPackageDataFile {
            return multiRootPackageDataFile.appending(component: "Packages")
        }
        return try getPackageRoot().appending(component: "Packages")
    }

    func resolvedFilePath() throws -> AbsolutePath {
        if let multiRootPackageDataFile = options.multirootPackageDataFile {
            return multiRootPackageDataFile.appending(components: "xcshareddata", "swiftpm", "Package.resolved")
        }
        return try getPackageRoot().appending(component: "Package.resolved")
    }

    func configFilePath() throws -> AbsolutePath {
        // Look for the override in the environment.
        if let envPath = ProcessEnv.vars["SWIFTPM_MIRROR_CONFIG"] {
            return try AbsolutePath(validating: envPath)
        }

        // Otherwise, use the default path.
        if let multiRootPackageDataFile = options.multirootPackageDataFile {
            return multiRootPackageDataFile.appending(components: "xcshareddata", "swiftpm", "config")
        }
        return try getPackageRoot().appending(components: ".swiftpm", "config")
    }

    func getSwiftPMConfig() throws -> SwiftPMConfig {
        return try _swiftpmConfig.get()
    }
    private lazy var _swiftpmConfig: Result<SwiftPMConfig, Swift.Error> = {
        return Result(catching: { SwiftPMConfig(path: try configFilePath()) })
    }()
    
    func resolvedNetrcFilePath() -> AbsolutePath? {
        return options.netrcFilePath 
    }

    /// Holds the currently active workspace.
    ///
    /// It is not initialized in init() because for some of the commands like package init , usage etc,
    /// workspace is not needed, infact it would be an error to ask for the workspace object
    /// for package init because the Manifest file should *not* present.
    private var _workspace: Workspace?

    /// Returns the currently active workspace.
    func getActiveWorkspace() throws -> Workspace {
        if let workspace = _workspace {
            return workspace
        }
        let isVerbose = options.verbosity != 0
        let delegate = ToolWorkspaceDelegate(self.stdoutStream, isVerbose: isVerbose, diagnostics: diagnostics)
        let provider = GitRepositoryProvider(processSet: processSet)
        let workspace = Workspace(
            dataPath: buildPath,
            editablesPath: try editablesPath(),
            pinsFile: try resolvedFilePath(),
            manifestLoader: try getManifestLoader(),
            toolsVersionLoader: ToolsVersionLoader(),
            delegate: delegate,
            config: try getSwiftPMConfig(),
            repositoryProvider: provider,
            netrcFilePath: resolvedNetrcFilePath(),
            isResolverPrefetchingEnabled: options.shouldEnableResolverPrefetching,
            skipUpdate: options.skipDependencyUpdate,
            enableResolverTrace: options.enableResolverTrace
        )
        _workspace = workspace
        return workspace
    }

    /// Start redirecting the standard output stream to the standard error stream.
    func redirectStdoutToStderr() {
        self.stdoutStream = TSCBasic.stderrStream
        DiagnosticsEngineHandler.default.stdoutStream = TSCBasic.stderrStream
    }

    /// Resolve the dependencies.
    func resolve() throws {
        let workspace = try getActiveWorkspace()
        let root = try getWorkspaceRoot()

        if options.forceResolvedVersions {
            workspace.resolveToResolvedVersion(root: root, diagnostics: diagnostics)
        } else {
            workspace.resolve(root: root, diagnostics: diagnostics)
        }

        // Throw if there were errors when loading the graph.
        // The actual errors will be printed before exiting.
        guard !diagnostics.hasErrors else {
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
                root: getWorkspaceRoot(),
                explicitProduct: explicitProduct,
                createMultipleTestProducts: createMultipleTestProducts,
                createREPLProduct: createREPLProduct,
                forceResolvedVersions: options.forceResolvedVersions,
                diagnostics: diagnostics
            )

            // Throw if there were errors when loading the graph.
            // The actual errors will be printed before exiting.
            guard !diagnostics.hasErrors else {
                throw ExitCode.failure
            }
            return graph
        } catch {
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

    private func canUseBuildManifestCaching() throws -> Bool {
        let buildParameters = try self.buildParameters()
        let haveBuildManifestAndDescription =
        localFileSystem.exists(buildParameters.llbuildManifest) &&
        localFileSystem.exists(buildParameters.buildDescriptionPath)

        // Perform steps for build manifest caching if we can enabled it.
        //
        // FIXME: We don't add edited packages in the package structure command yet (SR-11254).
        let hasEditedPackages = try getActiveWorkspace().state.dependencies.contains(where: { $0.isEdited })

        let enableBuildManifestCaching = ProcessEnv.vars.keys.contains("SWIFTPM_ENABLE_BUILD_MANIFEST_CACHING") || options.enableBuildManifestCaching

        return enableBuildManifestCaching && haveBuildManifestAndDescription && !hasEditedPackages
    }

    func createBuildOperation(explicitProduct: String? = nil, useBuildManifestCaching: Bool = true) throws -> BuildOperation {
        // Load a custom package graph which has a special product for REPL.
        let graphLoader = { try self.loadPackageGraph(explicitProduct: explicitProduct) }

        // Construct the build operation.
        let buildOp = try BuildOperation(
            buildParameters: buildParameters(),
            useBuildManifestCaching: useBuildManifestCaching && canUseBuildManifestCaching(),
            packageGraphLoader: graphLoader,
            diagnostics: diagnostics,
            stdoutStream: self.stdoutStream
        )

        // Save the instance so it can be cancelled from the int handler.
        buildSystemRef.buildSystem = buildOp
        return buildOp
    }

    func createBuildSystem(explicitProduct: String? = nil, useBuildManifestCaching: Bool = true) throws -> BuildSystem {
        let buildSystem: BuildSystem
        switch options.buildSystem {
        case .native:
            let graphLoader = { try self.loadPackageGraph(explicitProduct: explicitProduct) }
            buildSystem = try BuildOperation(
                buildParameters: buildParameters(),
                useBuildManifestCaching: useBuildManifestCaching && canUseBuildManifestCaching(),
                packageGraphLoader: graphLoader,
                diagnostics: diagnostics,
                stdoutStream: stdoutStream
            )
        case .xcode:
            let graphLoader = { try self.loadPackageGraph(explicitProduct: explicitProduct, createMultipleTestProducts: true) }
            buildSystem = try XcodeBuildSystem(
                buildParameters: buildParameters(),
                packageGraphLoader: graphLoader,
                isVerbose: verbosity != .concise,
                diagnostics: diagnostics,
                stdoutStream: stdoutStream
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
                indexStoreMode: options.indexStore,
                enableParseableModuleInterfaces: options.shouldEnableParseableModuleInterfaces,
                enableTestDiscovery: options.enableTestDiscovery,
                emitSwiftModuleSeparately: options.emitSwiftModuleSeparately,
                useIntegratedSwiftDriver: options.useIntegratedSwiftDriver,
                useExplicitModuleBuild: options.useExplicitModuleBuild,
                isXcodeBuildSystemEnabled: options.buildSystem == .xcode,
                printManifestGraphviz: options.printManifestGraphviz
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
            try ManifestLoader(
                // Always use the host toolchain's resources for parsing manifest.
                manifestResources: self._hostToolchain.get().manifestResources,
                isManifestSandboxEnabled: !self.options.shouldDisableSandbox,
                cacheDir: self.options.shouldDisableManifestCaching ? nil : self.buildPath,
                extraManifestFlags: self.options.manifestFlags
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

/// Returns the sandbox profile to be used when parsing manifest on macOS.
private func sandboxProfile(allowedDirectories: [AbsolutePath]) -> String {
    let stream = BufferedOutputByteStream()
    stream <<< "(version 1)" <<< "\n"
    // Deny everything by default.
    stream <<< "(deny default)" <<< "\n"
    // Import the system sandbox profile.
    stream <<< "(import \"system.sb\")" <<< "\n"
    // Allow reading all files.
    stream <<< "(allow file-read*)" <<< "\n"
    // These are required by the Swift compiler.
    stream <<< "(allow process*)" <<< "\n"
    stream <<< "(allow sysctl*)" <<< "\n"
    // Allow writing in temporary locations.
    stream <<< "(allow file-write*" <<< "\n"
    for directory in Platform.darwinCacheDirectories() {
        // For compiler module cache.
        stream <<< "    (regex #\"^\(directory.pathString)/org\\.llvm\\.clang.*\")" <<< "\n"
        // For archive tool.
        stream <<< "    (regex #\"^\(directory.pathString)/ar.*\")" <<< "\n"
        // For xcrun cache.
        stream <<< "    (regex #\"^\(directory.pathString)/xcrun.*\")" <<< "\n"
        // For autolink files.
        stream <<< "    (regex #\"^\(directory.pathString)/.*\\.(swift|c)-[0-9a-f]+\\.autolink\")" <<< "\n"
    }
    for directory in allowedDirectories {
        stream <<< "    (subpath \"\(directory.pathString)\")" <<< "\n"
    }
    stream <<< ")" <<< "\n"
    return stream.bytes.description
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
