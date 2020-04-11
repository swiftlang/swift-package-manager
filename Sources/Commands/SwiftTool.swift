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

protocol ToolName {
    static var toolName: String { get }
}

extension ToolName {
    static func otherToolNames() -> String {
        let allTools: [ToolName.Type] = [SwiftBuildTool.self, SwiftRunTool.self, SwiftPackageTool.self, SwiftTestTool.self]
        return  allTools.filter({ $0 != self }).map({ $0.toolName }).joined(separator: ", ")
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

public class SwiftTool<Options: ToolOptions> {
    /// The original working directory.
    let originalWorkingDirectory: AbsolutePath

    /// The options of this tool.
    let options: Options

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

    /// Reference to the argument parser.
    let parser: ArgumentParser

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
    public init(toolName: String, usage: String, overview: String, args: [String], seeAlso: String? = nil) {
        // Capture the original working directory ASAP.
        guard let cwd = localFileSystem.currentWorkingDirectory else {
            diagnostics.emit(error: "couldn't determine the current working directory")
            SwiftTool.exit(with: .failure)
        }
        originalWorkingDirectory = cwd

        // Create the parser.
        parser = ArgumentParser(
            commandName: "swift \(toolName)",
            usage: usage,
            overview: overview,
            seeAlso: seeAlso)

        // Create the binder.
        let binder = ArgumentBinder<Options>()

        // Bind the common options.
        binder.bindArray(
            parser.add(
                option: "-Xcc", kind: [String].self, strategy: .oneByOne,
                usage: "Pass flag through to all C compiler invocations"),
            parser.add(
                option: "-Xswiftc", kind: [String].self, strategy: .oneByOne,
                usage: "Pass flag through to all Swift compiler invocations"),
            parser.add(
                option: "-Xlinker", kind: [String].self, strategy: .oneByOne,
                usage: "Pass flag through to all linker invocations"),
            to: {
                $0.buildFlags.cCompilerFlags = $1
                $0.buildFlags.swiftCompilerFlags = $2
                $0.buildFlags.linkerFlags = $3
            })
        binder.bindArray(
            option: parser.add(
                option: "-Xcxx", kind: [String].self, strategy: .oneByOne,
                usage: "Pass flag through to all C++ compiler invocations"),
            to: { $0.buildFlags.cxxCompilerFlags = $1 })

        binder.bindArray(
            option: parser.add(
                option: "-Xxcbuild", kind: [String].self, strategy: .oneByOne,
                usage: "Pass flag through to the Xcode build system invocations"),
            to: { $0.xcbuildFlags = $1 })

        binder.bind(
            option: parser.add(
                option: "--configuration", shortName: "-c", kind: BuildConfiguration.self,
                usage: "Build with configuration (debug|release) [default: debug]"),
            to: { $0.configuration = $1 })

        binder.bind(
            option: parser.add(
                option: "--build-path", kind: PathArgument.self,
                usage: "Specify build/cache directory [default: ./.build]"),
            to: { $0.buildPath = $1.path })

        binder.bind(
            option: parser.add(
                option: "--chdir", shortName: "-C", kind: PathArgument.self),
            to: { $0.chdir = $1.path })

        binder.bind(
            option: parser.add(
                option: "--package-path", kind: PathArgument.self,
                usage: "Change working directory before any other operation"),
            to: { $0.packagePath = $1.path })

        binder.bind(
            option: parser.add(
                option: "--multiroot-data-file", kind: PathArgument.self, usage: nil),
            to: { $0.multirootPackageDataFile = $1.path })

        binder.bindArray(
            option: parser.add(option: "--sanitize", kind: [Sanitizer].self,
                strategy: .oneByOne, usage: "Turn on runtime checks for erroneous behavior"),
            to: { $0.sanitizers = EnabledSanitizers(Set($1)) })

        binder.bind(
            option: parser.add(option: "--disable-prefetching", kind: Bool.self, usage: ""),
            to: { $0.shouldEnableResolverPrefetching = !$1 })

        binder.bind(
            option: parser.add(option: "--skip-update", kind: Bool.self, usage: "Skip updating dependencies from their remote during a resolution"),
            to: { $0.skipDependencyUpdate = $1 })

        binder.bind(
            option: parser.add(option: "--disable-sandbox", kind: Bool.self,
            usage: "Disable using the sandbox when executing subprocesses"),
            to: { $0.shouldDisableSandbox = $1 })

        binder.bind(
            option: parser.add(option: "--disable-package-manifest-caching", kind: Bool.self,
            usage: "Disable caching Package.swift manifests"),
            to: { $0.shouldDisableManifestCaching = $1 })

        binder.bind(
            option: parser.add(option: "--version", kind: Bool.self),
            to: { $0.shouldPrintVersion = $1 })

        binder.bind(
            option: parser.add(option: "--destination", kind: PathArgument.self),
            to: { $0.customCompileDestination = $1.path })
        binder.bind(
            option: parser.add(option: "--triple", kind: String.self),
            to: { $0.customCompileTriple = try Triple($1) })
        binder.bind(
            option: parser.add(option: "--sdk", kind: PathArgument.self),
            to: { $0.customCompileSDK = $1.path })
        binder.bind(
            option: parser.add(option: "--toolchain", kind: PathArgument.self),
            to: { $0.customCompileToolchain = $1.path })

        // FIXME: We need to allow -vv type options for this.
        binder.bind(
            option: parser.add(option: "--verbose", shortName: "-v", kind: Bool.self,
                usage: "Increase verbosity of informational output"),
            to: { $0.verbosity = $1 ? 1 : 0 })

        binder.bind(
            option: parser.add(option: "--no-static-swift-stdlib", kind: Bool.self,
                usage: "Do not link Swift stdlib statically [default]"),
            to: { $0.shouldLinkStaticSwiftStdlib = !$1 })

        binder.bind(
            option: parser.add(option: "--static-swift-stdlib", kind: Bool.self,
                usage: "Link Swift stdlib statically"),
            to: { $0.shouldLinkStaticSwiftStdlib = $1 })

        binder.bind(
            option: parser.add(option: "--force-resolved-versions", kind: Bool.self),
            to: { $0.forceResolvedVersions = $1 })

        binder.bind(
            option: parser.add(option: "--disable-automatic-resolution", kind: Bool.self,
               usage: "Disable automatic resolution if Package.resolved file is out-of-date"),
            to: { $0.forceResolvedVersions = $1 })

        binder.bind(
            option: parser.add(option: "--enable-index-store", kind: Bool.self,
                usage: "Enable indexing-while-building feature"),
            to: { if $1 { $0.indexStoreMode = .on } })

        binder.bind(
            option: parser.add(option: "--disable-index-store", kind: Bool.self,
                usage: "Disable indexing-while-building feature"),
            to: { if $1 { $0.indexStoreMode = .off } })

        binder.bind(
            option: parser.add(option: "--enable-parseable-module-interfaces", kind: Bool.self),
            to: { $0.shouldEnableParseableModuleInterfaces = $1 })

        binder.bind(
            option: parser.add(option: "--trace-resolver", kind: Bool.self),
            to: { $0.enableResolverTrace = $1 })

        binder.bind(
            option: parser.add(option: "--jobs", shortName: "-j", kind: Int.self,
                usage: "The number of jobs to spawn in parallel during the build process"),
            to: { $0.jobs = UInt32($1) })

        binder.bind(
            option: parser.add(option: "--enable-test-discovery", kind: Bool.self,
               usage: "Enable test discovery on platforms without Objective-C runtime"),
            to: { $0.enableTestDiscovery = $1 })

        binder.bind(
            option: parser.add(option: "--enable-build-manifest-caching", kind: Bool.self, usage: nil),
            to: { $0.enableBuildManifestCaching = $1 })

        binder.bind(
            option: parser.add(option: "--emit-swift-module-separately", kind: Bool.self, usage: nil),
            to: { $0.emitSwiftModuleSeparately = $1 })

        binder.bind(
            option: parser.add(option: "--build-system", kind: BuildSystemKind.self, usage: nil),
            to: { $0.buildSystem = $1 })

        // Let subclasses bind arguments.
        type(of: self).defineArguments(parser: parser, binder: binder)

        do {
            // Parse the result.
            let result = try parser.parse(args)

            try Self.postprocessArgParserResult(result: result, diagnostics: diagnostics)

            var options = Options()
            try binder.fill(parseResult: result, into: &options)

            self.options = options
            // Honor package-path option is provided.
            if let packagePath = options.packagePath ?? options.chdir {
                try ProcessEnv.chdir(packagePath)
            }

            // Force building with the native build system on other platforms than macOS.
          #if !os(macOS)
            options.buildSystem = .native
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
            SwiftTool.exit(with: .failure)
        }

        // Create local variables to use while finding build path to avoid capture self before init error.
        let customBuildPath = options.buildPath
        let packageRoot = findPackageRoot()

        self.packageRoot = packageRoot
        self.buildPath = getEnvBuildPath(workingDir: cwd) ??
            customBuildPath ??
            (packageRoot ?? cwd).appending(component: ".build")
    }

    class func postprocessArgParserResult(result: ArgumentParser.Result, diagnostics: DiagnosticsEngine) throws {
        if result.exists(arg: "--chdir") || result.exists(arg: "-C") {
            diagnostics.emit(warning: "'--chdir/-C' option is deprecated; use '--package-path' instead")
        }

        if result.exists(arg: "--multiroot-data-file") {
            diagnostics.emit(.unsupportedFlag("--multiroot-data-file"))
        }
    }

    class func defineArguments(parser: ArgumentParser, binder: ArgumentBinder<Options>) {
        fatalError("Must be implemented by subclasses")
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
            isResolverPrefetchingEnabled: options.shouldEnableResolverPrefetching,
            skipUpdate: options.skipDependencyUpdate,
            enableResolverTrace: options.enableResolverTrace
        )
        _workspace = workspace
        return workspace
    }

    /// Execute the tool.
    public func run() {
        do {
            // Setup the globals.
            verbosity = Verbosity(rawValue: options.verbosity)
            Process.verbose = verbosity != .concise
            // Call the implementation.
            try runImpl()
            if diagnostics.hasErrors {
                throw Diagnostics.fatalError
            }
        } catch {
            // Set execution status to failure in case of errors.
            executionStatus = .failure
            handle(error: error)
        }
        SwiftTool.exit(with: executionStatus)
    }

    /// Exit the tool with the given execution status.
    private static func exit(with status: ExecutionStatus) -> Never {
        switch status {
        case .success: TSCLibc.exit(0)
        case .failure: TSCLibc.exit(1)
        }
    }

    /// Run method implementation to be overridden by subclasses.
    func runImpl() throws {
        fatalError("Must be implemented by subclasses")
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
            throw Diagnostics.fatalError
        }
    }

    /// Fetch and load the complete package graph.
    @discardableResult
    func loadPackageGraph(
        createMultipleTestProducts: Bool = false,
        createREPLProduct: Bool = false
    ) throws -> PackageGraph {
        do {
            let workspace = try getActiveWorkspace()

            // Fetch and load the package graph.
            let graph = try workspace.loadPackageGraph(
                root: getWorkspaceRoot(),
                createMultipleTestProducts: createMultipleTestProducts,
                createREPLProduct: createREPLProduct,
                forceResolvedVersions: options.forceResolvedVersions,
                diagnostics: diagnostics
            )

            // Throw if there were errors when loading the graph.
            // The actual errors will be printed before exiting.
            guard !diagnostics.hasErrors else {
                throw Diagnostics.fatalError
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

    func createBuildOperation(useBuildManifestCaching: Bool = true) throws -> BuildOperation {
        // Load a custom package graph which has a special product for REPL.
        let graphLoader = { try self.loadPackageGraph() }

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

    func createBuildSystem(useBuildManifestCaching: Bool = true) throws -> BuildSystem {
        let buildSystem: BuildSystem
        switch options.buildSystem {
        case .native:
            let graphLoader = { try self.loadPackageGraph() }
            buildSystem = try BuildOperation(
                buildParameters: buildParameters(),
                useBuildManifestCaching: useBuildManifestCaching && canUseBuildManifestCaching(),
                packageGraphLoader: graphLoader,
                diagnostics: diagnostics,
                stdoutStream: stdoutStream
            )
        case .xcode:
            let graphLoader = { try self.loadPackageGraph(createMultipleTestProducts: true) }
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
                flags: options.buildFlags,
                xcbuildFlags: options.xcbuildFlags,
                jobs: options.jobs ?? UInt32(ProcessInfo.processInfo.activeProcessorCount),
                shouldLinkStaticSwiftStdlib: options.shouldLinkStaticSwiftStdlib,
                sanitizers: options.sanitizers,
                enableCodeCoverage: options.shouldEnableCodeCoverage,
                indexStoreMode: options.indexStoreMode,
                enableParseableModuleInterfaces: options.shouldEnableParseableModuleInterfaces,
                enableTestDiscovery: options.enableTestDiscovery,
                emitSwiftModuleSeparately: options.emitSwiftModuleSeparately,
                isXcodeBuildSystemEnabled: options.buildSystem == .xcode
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
                cacheDir: self.options.shouldDisableManifestCaching ? nil : self.buildPath
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

extension BuildConfiguration: StringEnumArgument {
    public static var completion: ShellCompletion = .values([
        (debug.rawValue, "build with DEBUG configuration"),
        (release.rawValue, "build with RELEASE configuration"),
    ])
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
