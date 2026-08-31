//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _Concurrency
import ArgumentParser
import Basics
import Dispatch
import class Foundation.ProcessInfo
import struct Foundation.URL
import struct Foundation.URLResourceValues
import PackageFingerprint
import PackageGraph
import PackageLoading
@_spi(SwiftPMInternal)
import PackageModel
import PackageRegistry
import PackageSigning
import SourceControl
import SPMBuildCore
import Workspace

#if USE_IMPL_ONLY_IMPORTS
@_implementationOnly
@_spi(SwiftPMInternal)
import DriverSupport
#else
@_spi(SwiftPMInternal)
import DriverSupport
#endif

#if canImport(WinSDK)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Bionic)
import Bionic
#endif

import class Basics.AsyncProcess
import func TSCBasic.exec
import class TSCBasic.FileLock
import enum TSCBasic.JSON
import protocol TSCBasic.OutputByteStream
import enum TSCBasic.ProcessEnv
import struct TSCBasic.SHA256
import enum TSCBasic.ProcessLockError
import var TSCBasic.stderrStream
import class TSCBasic.TerminalController
import class TSCBasic.ThreadSafeOutputByteStream
import enum TSCBasic.SystemError

import var TSCUtility.verbosity

typealias Diagnostic = Basics.Diagnostic

public struct ToolWorkspaceConfiguration {
    let shouldInstallSignalHandlers: Bool
    let wantsMultipleTestProducts: Bool
    let wantsREPLProduct: Bool

    public init(
        shouldInstallSignalHandlers: Bool = true,
        wantsMultipleTestProducts: Bool = false,
        wantsREPLProduct: Bool = false
    ) {
        self.shouldInstallSignalHandlers = shouldInstallSignalHandlers
        self.wantsMultipleTestProducts = wantsMultipleTestProducts
        self.wantsREPLProduct = wantsREPLProduct
    }
}

public typealias WorkspaceDelegateProvider = (
    _ observabilityScope: ObservabilityScope,
    _ outputHandler: @escaping (String, OutputCondition) -> Void,
    _ progressHandler: @escaping (Int64, Int64, String?) -> Void,
    _ inputHandler: @escaping (String, (String?) -> Void) -> Void
) -> WorkspaceDelegate

public typealias WorkspaceLoaderProvider = (_ fileSystem: FileSystem, _ observabilityScope: ObservabilityScope)
    -> WorkspaceLoader

public protocol _SwiftCommand {
    var globalOptions: GlobalOptions { get }
    var toolWorkspaceConfiguration: ToolWorkspaceConfiguration { get }
    var workspaceDelegateProvider: WorkspaceDelegateProvider { get }
    var workspaceLoaderProvider: WorkspaceLoaderProvider { get }
    func buildSystemProvider(_ swiftCommandState: SwiftCommandState) throws -> BuildSystemProvider

    // If a packagePath is specificed, this indicates that the command allows
    // creating the directory if it doesn't exist.
    var createPackagePath: Bool { get }
}

extension _SwiftCommand {
    public var toolWorkspaceConfiguration: ToolWorkspaceConfiguration {
        .init()
    }

    public var createPackagePath: Bool {
        return false
    }
}

public protocol SwiftCommand: ParsableCommand, _SwiftCommand {
    func run(_ swiftCommandState: SwiftCommandState) throws
}

extension SwiftCommand {
    public static var _errorLabel: String { "error" }

    public func run() throws {
        let swiftCommandState = try SwiftCommandState(
            options: globalOptions,
            toolWorkspaceConfiguration: self.toolWorkspaceConfiguration,
            workspaceDelegateProvider: self.workspaceDelegateProvider,
            workspaceLoaderProvider: self.workspaceLoaderProvider,
            createPackagePath: self.createPackagePath
        )
        defer {
            _ = createCacheDirFile(inDirectory: swiftCommandState.scratchDirectory)
            _ = createBuildSystemFile(
                inDirectory: swiftCommandState.scratchDirectory,
                for: swiftCommandState.options.build.configuration ?? swiftCommandState.preferredBuildConfiguration,
                buildSystem: swiftCommandState.options.build.buildSystem,
            )
        }

        // We use this to attempt to catch misuse of the locking APIs since we only release the lock from here.
        swiftCommandState.setNeedsLocking()

        swiftCommandState.buildSystemProvider = try buildSystemProvider(swiftCommandState)
        var toolError: Error? = .none
        do {
            try self.run(swiftCommandState)
            if swiftCommandState.observabilityScope.errorsReported || swiftCommandState.executionStatus == .failure {
                throw ExitCode.failure
            }
        } catch {
            toolError = error
        }

        swiftCommandState.releaseLockIfNeeded()

        if globalOptions.build._buildSystem != .swiftbuild {
            swiftCommandState.observabilityScope.emit(
                .deprecatedBuildSystem(buildSystem: globalOptions.build._buildSystem)
            )
        }
        // if SwiftCommandState.packagePathDeprecationWarranted(arguments: CommandLine.arguments) {
        //     swiftCommandState.observabilityScope.emit(
        //         .argumentDeprecated(flag: "--package-path", renamed: "--path")
        //     )
        // }
        swiftCommandState.flushMemberStateFindings()
        // wait for all observability items to process
        swiftCommandState.waitForObservabilityEvents(timeout: .now() + 5)

        if let toolError {
            throw toolError
        }
    }
}

package func createCacheDirFile(
    inDirectory directory: AbsolutePath,
    _ fileSystem: FileSystem = localFileSystem,
) -> AbsolutePath? {
    // https://bford.info/cachedir/
    let path = directory.appending("CACHEDIR.TAG")
    do {
        let contents = """
            Signature: 8a477f597d28d172789f06886806bc55
            # This file is a cache directory tag created by (Swift Package Manager).
            # For information about cache directory tags, see:
            #.   http://www.brynosaurus.com/cachedir/
            """
        try fileSystem.createDirectory(path.parentDirectory, recursive: true)
        _ = excludeFromBackups(directory: directory)
        try fileSystem.writeFileContents(path, string: contents)
        return path
    } catch {
        // Don't error out if we fail to create the CACHEDIR.TAG file, as this is not critical to the functioning of the tool.
        return nil
    }
}

/// Marks a directory as excluded from backups, for example for Time Machine.
package func excludeFromBackups(directory: AbsolutePath) -> Bool {
    #if os(macOS)
    do {
        var url = directory.asURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try url.setResourceValues(resourceValues)
        return true
    } catch {
        // Don't error out if we fail to create the file, as this is not critical to the functioning of the tool.
        return false
    }
    #else
    return false
    #endif
}

package func createBuildSystemFile(
    inDirectory directory: AbsolutePath,
    for configuration: BuildConfiguration,
    buildSystem: BuildSystemProvider.Kind,
    fileSystem fs: FileSystem = localFileSystem,
) -> AbsolutePath? {
    let path = directory.appending(".buildSystem_\(configuration)")
    do {
        try fs.createDirectory(path.parentDirectory, recursive: true)
        try fs.writeFileContents(path, string: "\(buildSystem)")
        return path
    } catch {
        // Don't error out if we fail to create the file, as this is not critical to the functioning of the tool.
        return nil
    }
}

public protocol AsyncSwiftCommand: AsyncParsableCommand, _SwiftCommand {
    func run(_ swiftCommandState: SwiftCommandState) async throws
    var inclueAdditionalScratchPathFiles: Bool { get }

}

extension AsyncSwiftCommand {
    public static var _errorLabel: String { "error" }

    public var inclueAdditionalScratchPathFiles: Bool { true }

    // FIXME: It doesn't seem great to have this be duplicated with `SwiftCommand`.
    public func run() async throws {
        let swiftCommandState = try SwiftCommandState(
            options: globalOptions,
            toolWorkspaceConfiguration: self.toolWorkspaceConfiguration,
            workspaceDelegateProvider: self.workspaceDelegateProvider,
            workspaceLoaderProvider: self.workspaceLoaderProvider,
            createPackagePath: self.createPackagePath
        )
        defer {
            if self.inclueAdditionalScratchPathFiles {
                _ = createCacheDirFile(inDirectory: swiftCommandState.scratchDirectory)
                _ = createBuildSystemFile(
                    inDirectory: swiftCommandState.scratchDirectory,
                    for: swiftCommandState.options.build.configuration ?? swiftCommandState.preferredBuildConfiguration,
                    buildSystem: swiftCommandState.options.build.buildSystem,
                )
            }
        }

        // We use this to attempt to catch misuse of the locking APIs since we only release the lock from here.
        swiftCommandState.setNeedsLocking()

        swiftCommandState.buildSystemProvider = try buildSystemProvider(swiftCommandState)
        var toolError: Error? = .none
        do {
            try await self.run(swiftCommandState)
            if swiftCommandState.observabilityScope.errorsReported || swiftCommandState.executionStatus == .failure {
                throw ExitCode.failure
            }
        } catch {
            toolError = error
        }

        swiftCommandState.releaseLockIfNeeded()

        if globalOptions.build._buildSystem != .swiftbuild {
            swiftCommandState.observabilityScope.emit(
                .deprecatedBuildSystem(buildSystem: globalOptions.build._buildSystem)
            )
        }
        // if SwiftCommandState.packagePathDeprecationWarranted(arguments: CommandLine.arguments) {
        //     swiftCommandState.observabilityScope.emit(
        //         .argumentDeprecated(flag: "--package-path", renamed: "--path")
        //     )
        // }

        swiftCommandState.flushMemberStateFindings()

        // wait for all observability items to process
        swiftCommandState.waitForObservabilityEvents(timeout: .now() + 5)

        if let toolError {
            throw toolError
        }
    }
}

public final class SwiftCommandState {
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

    /// The absolute path of the enclosing `Workspace.swift` directory,
    /// discovered synchronously at init time (mirrors the discovery
    /// used to place `scratchDirectory` at the workspace root). Nil
    /// when no `Workspace.swift` is reachable from the CWD/package
    /// root, or when `--multiroot-data-file` is in use. Consumed by
    /// `getResolvedVersionsFile()` so `Package.resolved` lives at the
    /// workspace root, shared across all members.
    private let workspaceRoot: AbsolutePath?

    /// When a `Workspace.swift` is discovered and CWD is inside one of
    /// its members, this holds the enclosing member's identity. Nil
    /// when CWD is at the workspace root, when no workspace is present,
    /// or when `--multiroot-data-file` is in use. Populated by
    /// `getWorkspaceRoot()`.
    public private(set) var currentWorkspaceMemberFocus: PackageIdentity?

    /// When a `Workspace.swift` is discovered, holds the full set of
    /// declared member identities. Nil when no workspace is present.
    /// Consumed by build/test/run commands to validate `--package
    /// <identity>` selections and to surface "known members" lists in
    /// diagnostics.
    public private(set) var currentWorkspaceMemberIdentities: Set<PackageIdentity>?

    /// Accumulated member-level state-file findings, aggregated across
    /// the workspace's declared members during workspace discovery.
    /// Flushed as a single trailing warning at end of command by
    /// `flushMemberStateFindings()`. `nil` until `getWorkspaceRoot()`
    /// runs; empty `[]` once the scan runs and finds nothing.
    ///
    /// Visibility is `internal` (not `private`) so tests can inject
    /// findings directly and pin the flush behavior without spinning
    /// up a full workspace load.
    @_spi(SwiftPMTesting) public var memberStateFindings: [MemberStateFindings]?

    /// Helper function to get package root or throw error if it is not found.
    public func getPackageRoot() throws -> AbsolutePath {
        guard let packageRoot else {
            throw StringError("Could not find \(Manifest.filename) in this directory or any of its parent directories.")
        }
        return packageRoot
    }

    /// Get the current workspace root object.
    ///
    /// Discovery order:
    /// 1. If `--multiroot-data-file` is specified, load the referenced
    ///    Xcode workspace and use its packages.
    /// 2. Otherwise, walk up from CWD looking for `Workspace.swift`. When
    ///    found, load the workspace manifest and expand its members into
    ///    the root package paths.
    /// 3. Otherwise, fall back to single-package `Package.swift` discovery.
    public func getWorkspaceRoot() async throws -> PackageGraphRootInput {
        let packages: [AbsolutePath]
        var workspaceManifest: WorkspaceManifest?
        var workspaceOverrides: [WorkspaceOverridesJSONParser.Override]?

        if let workspace = options.locations.multirootPackageDataFile {
            packages = try self.workspaceLoaderProvider(self.fileSystem, self.observabilityScope)
                .load(workspace: workspace)
        } else if let workspaceRoot = PackageWorkspace.discoverWorkspaceRoot(
            from: self.fileSystem.currentWorkingDirectory ?? .root,
            fileSystem: self.fileSystem,
        ) {
            let manifestLoader = try ManifestLoader(toolchain: self.getHostToolchain())
            let (manifest, overrides) = try await PackageWorkspace.loadWorkspaceManifestAndOverrides(
                at: workspaceRoot,
                manifestLoader: manifestLoader,
                fileSystem: self.fileSystem,
                observabilityScope: self.observabilityScope,
            )
            packages = manifest.members.map(\.path)
            workspaceManifest = manifest
            workspaceOverrides = overrides
            self.currentWorkspaceMemberIdentities = Set(manifest.members.map(\.identity))
            self.currentWorkspaceMemberFocus = PackageWorkspace.findEnclosingMember(
                cwd: self.fileSystem.currentWorkingDirectory ?? .root,
                in: manifest.members,
            )
            if let diagnostic = Self.workspaceMemberFocusRequiresSwiftBuildDiagnostic(
                focus: self.currentWorkspaceMemberFocus,
                buildSystem: self.options.build.buildSystem,
            ) {
                self.observabilityScope.emit(diagnostic)
                throw ExitCode.failure
            }
            // Scan each member for state files SwiftPM won't use
            // (workspace-root state is authoritative). Findings are
            // buffered here and emitted as a single trailing warning
            // by `flushMemberStateFindings()` at end of command. The
            // scan runs only once per invocation: `getWorkspaceRoot()`
            // is called multiple times by different commands, but the
            // `nil` sentinel on `memberStateFindings` gates it.
            if self.memberStateFindings == nil {
                self.memberStateFindings = manifest.members.compactMap { member in
                    MemberStateFindings.scanMemberStateFiles(
                        member: member,
                        fileSystem: self.fileSystem,
                    )
                }
            }
        } else {
            packages = try [self.getPackageRoot()]
        }

        return PackageGraphRootInput(
            packages: packages,
            traitConfiguration: self.traitConfiguration,
            workspaceManifest: workspaceManifest,
            overrides: workspaceOverrides,
        )
    }

    /// Scratch space (.build) directory.
    public let scratchDirectory: AbsolutePath

    /// Path to the shared security directory
    public let sharedSecurityDirectory: AbsolutePath

    /// Path to the shared cache directory
    public let sharedCacheDirectory: AbsolutePath

    /// Path to the shared configuration directory
    public let sharedConfigurationDirectory: AbsolutePath

    /// Path to the package manager's own resources directory.
    public let packageManagerResourcesDirectory: AbsolutePath?

    /// Path to the cross-compilation Swift SDKs directory.
    public let sharedSwiftSDKsDirectory: AbsolutePath

    /// Cancellator to handle cancellation of outstanding work when handling SIGINT
    public let cancellator: Cancellator

    /// The execution status of the tool.
    public var executionStatus: ExecutionStatus = .success

    /// Holds the currently active workspace.
    ///
    /// It is not initialized in init() because for some of the commands like `package init`, usage etc,
    /// a workspace is not needed. In fact it would be an error to ask for the workspace object
    /// for `package init` because the manifest file should *not* be present.
    private var _workspace: PackageWorkspace?
    private var _workspaceDelegate: WorkspaceDelegate?

    private let observabilityHandler: SwiftCommandObservabilityHandler

    /// The observability scope to emit diagnostics event on
    public let observabilityScope: ObservabilityScope

    /// The min severity at which to log diagnostics
    public let logLevel: Basics.Diagnostic.Severity

    // should use sandbox on external subcommands
    public var shouldDisableSandbox: Bool

    /// The file system in use
    public let fileSystem: FileSystem

    /// Provider which can create a `WorkspaceDelegate` if needed.
    private let workspaceDelegateProvider: WorkspaceDelegateProvider

    /// Provider which can create a `WorkspaceLoader` if needed.
    private let workspaceLoaderProvider: WorkspaceLoaderProvider

    private let toolWorkspaceConfiguration: ToolWorkspaceConfiguration

    fileprivate var buildSystemProvider: BuildSystemProvider?

    private let environment: Environment

    private let hostTriple: Basics.Triple?

    private let targetInfo: JSON?

    package var preferredBuildConfiguration = BuildConfiguration.debug

    package let traitConfiguration: TraitConfiguration

    /// Create an instance of this tool.
    ///
    /// - parameter options: The command line options to be passed to this tool.
    public convenience init(
        options: GlobalOptions,
        toolWorkspaceConfiguration: ToolWorkspaceConfiguration = .init(),
        workspaceDelegateProvider: @escaping WorkspaceDelegateProvider,
        workspaceLoaderProvider: @escaping WorkspaceLoaderProvider,
        createPackagePath: Bool
    ) throws {
        // output from background activities goes to stderr, this includes diagnostics and output from build operations,
        // package resolution that take place as part of another action
        // CLI commands that have user facing output, use stdout directly to emit the final result
        // this means that the build output from "swift build" goes to stdout
        // but the build output from "swift test" goes to stderr, while the tests output go to stdout
        try self.init(
            outputStream: TSCBasic.stderrStream,
            options: options,
            toolWorkspaceConfiguration: toolWorkspaceConfiguration,
            workspaceDelegateProvider: workspaceDelegateProvider,
            workspaceLoaderProvider: workspaceLoaderProvider,
            createPackagePath: createPackagePath
        )
    }

    // marked internal for testing
    package init(
        outputStream: OutputByteStream,
        options: GlobalOptions,
        toolWorkspaceConfiguration: ToolWorkspaceConfiguration,
        workspaceDelegateProvider: @escaping WorkspaceDelegateProvider,
        workspaceLoaderProvider: @escaping WorkspaceLoaderProvider,
        createPackagePath: Bool,
        hostTriple: Basics.Triple? = nil,
        targetInfo: JSON? = nil,
        fileSystem: any FileSystem = localFileSystem,
        environment: Environment = .current
    ) throws {
        self.hostTriple = hostTriple
        self.targetInfo = targetInfo
        self.fileSystem = fileSystem
        self.environment = environment
        // first, bootstrap the observability system
        self.logLevel = options.logging.logLevel
        self.observabilityHandler = SwiftCommandObservabilityHandler(
            outputStream: outputStream,
            logLevel: self.logLevel,
            colorDiagnostics: options.logging.colorDiagnostics
        )
        let observabilitySystem = ObservabilitySystem(self.observabilityHandler)
        let observabilityScope = observabilitySystem.topScope
        self.observabilityScope = observabilityScope
        self.shouldDisableSandbox = options.security.shouldDisableSandbox
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
            try Self.chdirIfNeeded(
                packageDirectory: self.options.locations.packageDirectory,
                createPackagePath: createPackagePath
            )
        } catch {
            self.observabilityScope.emit(error)
            throw ExitCode.failure
        }

        if toolWorkspaceConfiguration.shouldInstallSignalHandlers {
            cancellator.installSignalHandlers()
        }
        self.cancellator = cancellator

        // Create local variables to use while finding build path to avoid capture self before init error.
        let packageRoot: AbsolutePath?
        if options.locations.skipResolvingPackagePaths {
            // Do not use the current working directory to determine the package root, as it will indirectly
            // cause us to reference its sources via their real instead of symlinked paths.
            guard let packageDirectory = options.locations.packageDirectory else {
                self.observabilityScope.emit(
                    error: "'--experimental-skip-resolving-package-paths' requires an explicit '--package-path'"
                )
                throw ExitCode.failure
            }
            packageRoot = packageDirectory
        } else {
            packageRoot = findPackageRoot(fileSystem: fileSystem)
        }

        self.packageRoot = packageRoot
        // Workspaces share a single `.build/` at the workspace root
        // across all members. Detect the enclosing `Workspace.swift`
        // now (at init, before any workspace loading) so paths like
        // `scratchDirectory` reflect that intent even when CWD is
        // inside a member directory (Case A).
        //
        // Start the walk from the just-computed `packageRoot` (or the
        // post-`chdir` CWD when no package root exists yet) — NOT from
        // the `cwd` captured before `chdirIfNeeded` ran, which may sit
        // outside the workspace entirely (e.g. the user's shell CWD
        // when `--package-path` was supplied).
        let workspaceDiscoveryStart =
            packageRoot ?? fileSystem.currentWorkingDirectory ?? cwd
        let discoveredWorkspaceRoot = PackageWorkspace.discoverWorkspaceRoot(
            from: workspaceDiscoveryStart,
            fileSystem: fileSystem,
        )
        // `--multiroot-data-file` vs. `Workspace.swift`: the two
        // mechanisms target incompatible workspace layouts. Rejecting
        // the combination up-front prevents `.build/` and
        // `Package.resolved` state from silently anchoring to the
        // wrong root.
        if let conflictDiagnostic = Self.multirootDataFileConflictDiagnostic(
            multirootDataFile: options.locations.multirootPackageDataFile,
            discoveredWorkspaceRoot: discoveredWorkspaceRoot,
        ) {
            self.observabilityScope.emit(conflictDiagnostic)
            throw ExitCode.failure
        }
        // `--multiroot-data-file` targets an Xcode workspace layout;
        // in that mode `Workspace.swift`-scoped state has no meaning,
        // so suppress the discovery here even if a `Workspace.swift`
        // happens to sit above the CWD.
        self.workspaceRoot = options.locations.multirootPackageDataFile == nil
            ? discoveredWorkspaceRoot
            : nil
        self.scratchDirectory =
            try BuildSystemUtilities.getEnvBuildPath(workingDir: cwd) ??
            options.locations.scratchDirectory ??
            (discoveredWorkspaceRoot ?? packageRoot ?? cwd).appending(".build")

        // make sure common directories are created
        self.sharedSecurityDirectory = try getSharedSecurityDirectory(options: options, fileSystem: fileSystem)
        self.sharedConfigurationDirectory = try getSharedConfigurationDirectory(
            options: options,
            fileSystem: fileSystem
        )
        self.sharedCacheDirectory = try getSharedCacheDirectory(options: options, fileSystem: fileSystem)
        if options.locations.deprecatedSwiftSDKsDirectory != nil {
            self.observabilityScope.emit(
                warning: "`--experimental-swift-sdks-path` is deprecated and will be removed in a future version of SwiftPM. Use `--swift-sdks-path` instead."
            )
        }

        if let packageManagerResourcesDirectory = options.locations.packageManagerResourcesDirectory {
            self.packageManagerResourcesDirectory = packageManagerResourcesDirectory
        } else if let cwd = localFileSystem.currentWorkingDirectory {
            self.packageManagerResourcesDirectory = try? AbsolutePath(validating: CommandLine.arguments[0], relativeTo: cwd)
                .parentDirectory.parentDirectory.appending(components: ["share", "pm"])
        } else {
            self.packageManagerResourcesDirectory = try? AbsolutePath(validating: CommandLine.arguments[0])
                .parentDirectory.parentDirectory.appending(components: ["share", "pm"])
        }

        self.sharedSwiftSDKsDirectory = try fileSystem.getSharedSwiftSDKsDirectory(
            explicitDirectory: options.locations.swiftSDKsDirectory ?? options.locations.deprecatedSwiftSDKsDirectory
        )

        // Set the trait configuration from user-passed trait options.
        self.traitConfiguration = .init(traitOptions: options.traits)

        // set global process logging handler
        AsyncProcess.loggingHandler = { self.observabilityScope.emit(debug: $0) }
    }

    static func postprocessArgParserResult(options: GlobalOptions, observabilityScope: ObservabilityScope) throws {
        if options.locations.multirootPackageDataFile != nil {
            observabilityScope.emit(.unsupportedFlag("--multiroot-data-file"))
        }

        if !options.build.architectures.isEmpty && options.build.customCompileTriple != nil {
            observabilityScope.emit(.mutuallyExclusiveArgumentsError(arguments: ["--arch", "--triple"]))
        }

        // --enable-test-discovery should never be called on darwin based platforms
        #if canImport(Darwin)
        if options.build.enableTestDiscovery {
            observabilityScope
                .emit(
                    warning: "'--enable-test-discovery' option is deprecated; tests are automatically discovered on all platforms"
                )
        }
        #endif

        if options.caching.shouldDisableManifestCaching {
            observabilityScope
                .emit(
                    warning: "'--disable-package-manifest-caching' option is deprecated; use '--manifest-caching' instead"
                )
        }

        if let _ = options.security.netrcFilePath, options.security.netrc == false {
            observabilityScope.emit(.mutuallyExclusiveArgumentsError(arguments: ["--disable-netrc", "--netrc-file"]))
        }

        if !options.build._deprecated_manifestFlags.isEmpty {
            observabilityScope.emit(warning: "'-Xmanifest' option is deprecated; use '-Xbuild-tools-swiftc' instead")
        }

        if options.build.enableTaskBacktraces {
            // Task backtraces require at least verbose output to be logged, unless
            // they're being captured in an event trace file.
            if !options.logging.verbose && !options.logging.veryVerbose && options.build.traceEventsFilePath == nil {
                observabilityScope.emit(
                    warning: "'--experimental-task-backtraces' requires '--verbose', '--very-verbose', or '--experimental-trace-events-file'"
                )
            }

            // Task backtraces are only supported by the swiftbuild build system
            if options.build.buildSystem != .swiftbuild {
                observabilityScope.emit(
                    warning: "'--experimental-task-backtraces' is only supported when using '--build-system swiftbuild'"
                )
            }
        }

        if options.build.traceEventsFilePath != nil {
            if options.build.buildSystem != .swiftbuild {
                observabilityScope.emit(
                    warning: "'--experimental-trace-events-file' is only supported when using '--build-system swiftbuild'"
                )
            }
        }
    }

    package func waitForObservabilityEvents(timeout: DispatchTime) {
        self.observabilityHandler.wait(timeout: timeout)
    }

    /// Emit the aggregated member-state-file warning as a trailing
    /// diagnostic at end of command, if any findings were collected
    /// during workspace discovery. Idempotent — safe to call from
    /// both the sync and async command runners; the second call is a
    /// no-op because the buffer is nil'd out after emission.
    ///
    /// Ordering: this is invoked from the command runner right before
    /// `waitForObservabilityEvents`, so the warning appears AFTER any
    /// resolve/build progress lines the command produced. Users see
    /// their command's output first, then the trailing summary.
    func flushMemberStateFindings() {
        guard let findings = self.memberStateFindings else { return }
        self.memberStateFindings = nil
        if let diagnostic = MemberStateFindings.formatWarning(findings: findings) {
            self.observabilityScope.emit(diagnostic)
        }
    }

    /// Returns the currently active workspace.
    public func getActiveWorkspace(emitDeprecatedConfigurationWarning: Bool = false, enableAllTraits: Bool = false) throws -> PackageWorkspace {
        if var workspace = _workspace {
            // if we decide to override the trait configuration, we can resolve accordingly for
            // calls like createSymbolGraphForPlugin.
            if enableAllTraits {
                workspace = workspace.updateConfiguration(with: .enableAllTraits)
            }
            return workspace
        }

        // Before creating the workspace, we need to acquire a lock on the build directory.
        try self.acquireLockIfNeeded()

        if self.options.resolver.skipDependencyUpdate {
            self.observabilityScope
                .emit(warning: "'--skip-update' option is deprecated and will be removed in a future release")
        }

        let delegate = self.workspaceDelegateProvider(
            self.observabilityScope,
            self.observabilityHandler.print,
            self.observabilityHandler.progress,
            self.observabilityHandler.prompt
        )
        let workspace = try PackageWorkspace(
            fileSystem: self.fileSystem,
            location: .init(
                scratchDirectory: self.scratchDirectory,
                editsDirectory: self.getEditsDirectory(),
                resolvedVersionsFile: self.getResolvedVersionsFile(),
                localConfigurationDirectory: self.getLocalConfigurationDirectory(),
                sharedConfigurationDirectory: self.sharedConfigurationDirectory,
                sharedSecurityDirectory: self.sharedSecurityDirectory,
                sharedCacheDirectory: self.sharedCacheDirectory,
                emitDeprecatedConfigurationWarning: emitDeprecatedConfigurationWarning
            ),
            authorizationProvider: self.getAuthorizationProvider(),
            registryAuthorizationProvider: self.getRegistryAuthorizationProvider(),
            configuration: .init(
                skipDependenciesUpdates: options.resolver.skipDependencyUpdate,
                prefetchBasedOnResolvedFile: options.resolver.shouldEnableResolverPrefetching,
                shouldCreateMultipleTestProducts: toolWorkspaceConfiguration.wantsMultipleTestProducts || options.build.buildSystem.shouldCreateMultipleTestProducts,
                createREPLProduct: toolWorkspaceConfiguration.wantsREPLProduct,
                additionalFileRules: options.build.buildSystem.additionalFileRules,
                sharedDependenciesCacheEnabled: self.options.caching.useDependenciesCache,
                fingerprintCheckingMode: self.options.security.fingerprintCheckingMode,
                signingEntityCheckingMode: self.options.security.signingEntityCheckingMode,
                skipSignatureValidation: !self.options.security.signatureValidation,
                sourceControlToRegistryDependencyTransformation: self.options.resolver
                    .sourceControlToRegistryDependencyTransformation?.workspaceConfiguration,
                defaultRegistry: self.options.resolver.defaultRegistryURL.flatMap {
                    // TODO: should supportsAvailability be a flag as well?
                    .init(url: $0, supportsAvailability: true)
                },
                manifestImportRestrictions: .none,
                usePrebuilts: self.options.caching.usePrebuilts,
                prebuiltsDownloadURL: options.caching.prebuiltsDownloadURL,
                prebuiltsRootCertPath: options.caching.prebuiltsRootCertPath,
                pruneDependencies: self.options.resolver.pruneDependencies,
                traitConfiguration: self.traitConfiguration
            ),
            cancellator: self.cancellator,
            initializationWarningHandler: { self.observabilityScope.emit(warning: $0) },
            customHostToolchain: self.getHostToolchain(),
            customManifestLoader: self.getManifestLoader(),
            delegate: delegate
        )
        self._workspace = workspace
        self._workspaceDelegate = delegate
        return workspace
    }

    /// Purges all global caches without requiring workspace initialization.
    /// This method creates minimal cache managers directly and calls their purgeCache methods.
    public func purgeCaches(observabilityScope: ObservabilityScope) async throws {
        // Create repository manager for repository cache
        let repositoryManager = RepositoryManager(
            fileSystem: self.fileSystem,
            path: self.scratchDirectory.appending("repositories"),
            provider: GitRepositoryProvider(),
            cachePath: self.sharedCacheDirectory.appending("repositories"),
            initializationWarningHandler: { observabilityScope.emit(warning: $0) },
            delegate: nil
        )

        // Create manifest loader for manifest cache
        let manifestLoader = ManifestLoader(
            toolchain: try self.getHostToolchain(),
            cacheDir: PackageWorkspace.DefaultLocations.manifestsDirectory(at: self.sharedCacheDirectory),
            importRestrictions: nil,
            delegate: nil,
            pruneDependencies: false
        )

        // Create registry downloads manager for registry cache
        let registryClient = RegistryClient(
            configuration: .init(),
            fingerprintStorage: nil,
            fingerprintCheckingMode: .strict,
            skipSignatureValidation: false,
            signingEntityStorage: nil,
            signingEntityCheckingMode: .strict,
            authorizationProvider: nil,
            delegate: nil,
            checksumAlgorithm: SHA256()
        )

        let registryDownloadsManager = RegistryDownloadsManager(
            fileSystem: self.fileSystem,
            path: self.scratchDirectory.appending(components: "registry", "downloads"),
            cachePath: self.sharedCacheDirectory.appending(components: "registry", "downloads"),
            registryClient: registryClient,
            delegate: nil
        )

        // Purge all caches
        repositoryManager.purgeCache(observabilityScope: observabilityScope)
        registryDownloadsManager.purgeCache(observabilityScope: observabilityScope)
        await manifestLoader.purgeCache(observabilityScope: observabilityScope)
    }

    public func getRootPackageInformation(_ enableAllTraits: Bool = false) async throws -> (dependencies: [PackageIdentity: [PackageIdentity]], targets: [PackageIdentity: [String]]) {
        let workspace = try self.getActiveWorkspace(enableAllTraits: enableAllTraits)
        let root = try await self.getWorkspaceRoot()
        let rootManifests = try await workspace.loadRootManifests(
            packages: root.packages,
            observabilityScope: self.observabilityScope
        )

        var identities = [PackageIdentity: [PackageIdentity]]()
        var targets = [PackageIdentity: [String]]()

        for rootManifest in rootManifests {
            let identity = PackageIdentity(path: rootManifest.key)
            identities[identity] = rootManifest.value.dependencies.map(\.identity)
            targets[identity] = rootManifest.value.targets.map { $0.name.spm_mangledToC99ExtendedIdentifier() }
        }

        return (identities, targets)
    }

    private static func chdirIfNeeded(packageDirectory: AbsolutePath?, createPackagePath: Bool) throws {
        if let packagePath = packageDirectory {
            do {
                try ProcessEnv.chdir(packagePath)
            } catch let SystemError.chdir(errorCode, path) {
                // If the command allows for the directory at the package path
                // to not be present then attempt to create it and chdir again.
                if createPackagePath {
                    try makeDirectories(packagePath)
                    try ProcessEnv.chdir(packagePath)
                } else {
                    throw SystemError.chdir(errorCode, path)
                }
            }
        }
    }

    private func getEditsDirectory() throws -> AbsolutePath {
        // TODO: replace multiroot-data-file with explicit overrides
        if let multiRootPackageDataFile = options.locations.multirootPackageDataFile {
            return multiRootPackageDataFile.appending("Packages")
        }
        return try PackageWorkspace.DefaultLocations.editsDirectory(forRootPackage: self.getPackageRoot())
    }

    private func getResolvedVersionsFile() throws -> AbsolutePath {
        try Self.computeResolvedVersionsFile(
            multiRootPackageDataFile: options.locations.multirootPackageDataFile,
            workspaceRoot: self.workspaceRoot,
            packageRoot: self.packageRoot,
            buildSystem: options.build.buildSystem,
        )
    }

    func getLocalConfigurationDirectory() throws -> AbsolutePath {
        let newConfigDir = try Self.computeLocalConfigurationDirectory(
            multiRootPackageDataFile: options.locations.multirootPackageDataFile,
            workspaceRoot: self.workspaceRoot,
            packageRoot: self.packageRoot,
        )

        // Migrate the legacy `.swiftpm/config` file (single-file
        // mirror configuration) to the new `.swiftpm/configuration/`
        // directory layout. Applies to the pre-workspace anchors —
        // SwiftPM workspaces are new and have no legacy state to
        // migrate from, so the workspace anchor skips migration.
        let legacyPath: AbsolutePath? = {
            if let multiroot = options.locations.multirootPackageDataFile {
                return multiroot.appending(components: "xcshareddata", "swiftpm", "config")
            }
            if self.workspaceRoot != nil {
                return nil
            }
            if let packageRoot = self.packageRoot {
                return packageRoot.appending(components: ".swiftpm", "config")
            }
            return nil
        }()

        guard let legacyPath else {
            return newConfigDir
        }
        let newPath = PackageWorkspace.DefaultLocations.mirrorsConfigurationFile(at: newConfigDir)
        return try PackageWorkspace.migrateMirrorsConfiguration(
            from: legacyPath,
            to: newPath,
            observabilityScope: self.observabilityScope,
        )
    }

    public func getAuthorizationProvider() throws -> AuthorizationProvider? {
        var authorization = PackageWorkspace.Configuration.Authorization.default
        if !self.options.security.netrc {
            authorization.netrc = .disabled
        } else if let configuredPath = options.security.netrcFilePath {
            authorization.netrc = .custom(configuredPath)
        } else {
            authorization.netrc = .user
        }

        #if canImport(Security)
        authorization.keychain = self.options.security.keychain ? .enabled : .disabled
        #endif

        return try authorization.makeAuthorizationProvider(
            fileSystem: self.fileSystem,
            observabilityScope: self.observabilityScope
        )
    }

    public func getRegistryAuthorizationProvider(
        additionalRegistryURLs: [URL] = []
    ) throws -> AuthorizationProvider? {
        var authorization = PackageWorkspace.Configuration.Authorization.default
        if let configuredPath = options.security.netrcFilePath {
            authorization.netrc = .custom(configuredPath)
        } else {
            authorization.netrc = .user
        }

        // Don't use OS credential store if user wants netrc
        #if canImport(Security)
        authorization.keychain = self.options.security.forceNetrc ? .disabled : .enabled
        #endif

        return try authorization.makeRegistryAuthorizationProvider(
            fileSystem: self.fileSystem,
            observabilityScope: self.observabilityScope,
            registryURLs: { try self.configuredRegistryURLs() + additionalRegistryURLs }
        )
    }

    private func configuredRegistryURLs() throws -> [URL] {
        let registries = try Workspace.Configuration.Registries(
            fileSystem: self.fileSystem,
            localRegistriesFile: Workspace.DefaultLocations
                .registriesConfigurationFile(at: self.getLocalConfigurationDirectory()),
            sharedRegistriesFile: Workspace.DefaultLocations
                .registriesConfigurationFile(at: self.sharedConfigurationDirectory)
        ).configuration

        return registries.registryURLs + [self.options.resolver.defaultRegistryURL].compactMap { $0 }
    }

    /// Resolve the dependencies.
    public func resolve() async throws {
        let workspace = try getActiveWorkspace()
        let root = try await getWorkspaceRoot()

        try await workspace.resolve(
            root: root,
            forceResolution: false,
            forceResolvedVersions: self.options.resolver.forceResolvedVersions,
            observabilityScope: self.observabilityScope
        )

        // Throw if there were errors when loading the graph.
        // The actual errors will be printed before exiting.
        guard !self.observabilityScope.errorsReported else {
            throw ExitCode.failure
        }
    }

    /// Fetch and load the complete package graph.
    ///
    /// - Parameters:
    ///   - explicitProduct: The product specified on the command line to a “swift run” or “swift build” command. This
    /// allows executables from dependencies to be run directly without having to hook them up to any particular target.
    @discardableResult
    public func loadPackageGraph(
        explicitProduct: String? = nil,
        testEntryPointPath: AbsolutePath? = nil
    ) async throws -> ModulesGraph {
        try await self.loadPackageGraph(
            explicitProduct: explicitProduct,
            enableAllTraits: false,
            testEntryPointPath: testEntryPointPath
        )
    }

    /// Fetch and load the complete package graph.
    ///
    /// - Parameters:
    ///   - explicitProduct: The product specified on the command line to a “swift run” or “swift build” command. This
    /// allows executables from dependencies to be run directly without having to hook them up to any particular target.
    ///   - exitOnError: Whether loading errors should cause this method to throw a failure exit code. Defaults to `true`.
    @discardableResult
    package func loadPackageGraph(
        explicitProduct: String? = nil,
        enableAllTraits: Bool = false,
        testEntryPointPath: AbsolutePath? = nil,
        exitOnError: Bool = true
    ) async throws -> ModulesGraph {
        do {
            let workspace = try getActiveWorkspace(enableAllTraits: enableAllTraits)

            // Create a dedicated observability scope for package graph loading so that the `packageGraphObservabilityScope.errorsReported`
            // below only considers errors reported from this call to `loadPackageGraph`. This ensures that in an interactive context like
            // when using `swift package experimental-build-server`, a package graph load which initially fails doesn't cause all subsequent
            // package graph load attempts to also fail due to sharing the same `errorsReported` bit.
            let packageGraphObservabilityScope = self.observabilityScope.makeChildScope(description: "Loading Package Graph")

            // Fetch and load the package graph.
            let graph = try await workspace.loadPackageGraph(
                rootInput: try await self.getWorkspaceRoot(),
                explicitProduct: explicitProduct,
                forceResolvedVersions: self.options.resolver.forceResolvedVersions,
                testEntryPointPath: testEntryPointPath,
                observabilityScope: packageGraphObservabilityScope
            )

            // Throw if there were errors when loading the graph.
            // The actual errors will be printed before exiting.
            guard !exitOnError || !packageGraphObservabilityScope.errorsReported else {
                throw ExitCode.failure
            }
            return graph
        } catch {
            throw error
        }
    }

    public func getPluginScriptRunner(customPluginsDir: AbsolutePath? = .none) throws -> PluginScriptRunner {
        let pluginsDir = try customPluginsDir ?? self.getActiveWorkspace().location.pluginWorkingDirectory
        let cacheDir = pluginsDir.appending("cache")
        let pluginScriptRunner = try DefaultPluginScriptRunner(
            fileSystem: self.fileSystem,
            cacheDir: cacheDir,
            toolchain: self.getHostToolchain(),
            extraPluginSwiftCFlags: self.options.build.pluginSwiftCFlags,
            enableSandbox: !self.shouldDisableSandbox,
            verboseOutput: self.logLevel <= .info
        )
        // register the plugin runner system with the cancellation handler
        self.cancellator.register(name: "plugin runner", handler: pluginScriptRunner)
        return pluginScriptRunner
    }

    /// Returns the user toolchain to compile the actual product.
    public func getTargetToolchain() throws -> UserToolchain {
        try self._targetToolchain.get()
    }

    public func getHostToolchain() throws -> UserToolchain {
        try self._hostToolchain.get()
    }

    /// Fetch the tools version for the root package in the currently active
    /// workspace.
    ///
    /// If there are multiple root packages, returns the lowest tools version.
    ///
    /// - Throws: If an error occurs when trying to resolve workspace details.
    /// - Returns: The current tools version, nil if no manifests are found.
    public func getToolsVersion() async throws -> ToolsVersion? {
        let workspace = try self.getActiveWorkspace()
        let root = try await self.getWorkspaceRoot()
        let rootManifests = try await workspace.loadRootManifests(
            packages: root.packages,
            observabilityScope: self.observabilityScope
        )
        return rootManifests.values.map { $0.toolsVersion }.min()
    }

    func getManifestLoader() throws -> ManifestLoader {
        try self._manifestLoader.get()
    }

    public func canUseCachedBuildManifest(_ traitConfiguration: TraitConfiguration = .default, buildDescriptionPath: AbsolutePath) async throws -> Bool {
        if !self.options.caching.cacheBuildManifest {
            return false
        }

        let buildParameters = try self.productsBuildParameters
        let haveBuildManifestAndDescription =
            self.fileSystem.exists(buildParameters.llbuildManifest) &&
            self.fileSystem.exists(buildDescriptionPath)

        if !haveBuildManifestAndDescription {
            return false
        }

        // Perform steps for build manifest caching if we can enabled it.
        //
        // FIXME: We don't add edited packages in the package structure command yet (SR-11254).
        let hasEditedPackages = try await self.getActiveWorkspace().state.dependencies.contains(where: \.isEdited)
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
        enableAllTraits: Bool = false,
        cacheBuildManifest: Bool = true,
        shouldLinkStaticSwiftStdlib: Bool = false,
        productsBuildParameters: BuildParameters? = .none,
        toolsBuildParameters: BuildParameters? = .none,
        packageGraphLoader: (() async throws -> ModulesGraph)? = .none,
        outputStream: OutputByteStream? = .none,
        logLevel: Basics.Diagnostic.Severity? = nil,
        observabilityScope: ObservabilityScope? = .none,
        delegate: BuildSystemDelegate? = nil
    ) async throws -> BuildSystem {

        if self.options.build.useIntegratedSwiftDriver && self.options.build.buildSystem == .native {
            self.observabilityScope.emit(warning: "`--use-integrated-swift-driver` option is deprecated as the feature is not fully functional.")
        }

        guard let buildSystemProvider else {
            fatalError("build system provider not initialized")
        }
        var productsParameters = try productsBuildParameters ?? self.productsBuildParameters
        productsParameters.linkingParameters.shouldLinkStaticSwiftStdlib = shouldLinkStaticSwiftStdlib
        let buildSystem = try await buildSystemProvider.createBuildSystem(
            kind: explicitBuildSystem ?? self.options.build.buildSystem,
            explicitProduct: explicitProduct,
            enableAllTraits: enableAllTraits,
            cacheBuildManifest: cacheBuildManifest,
            productsBuildParameters: productsParameters,
            toolsBuildParameters: toolsBuildParameters,
            packageGraphLoader: packageGraphLoader,
            outputStream: outputStream,
            logLevel: logLevel ?? self.logLevel,
            observabilityScope: observabilityScope,
            delegate: delegate
        )

        // register the build system with the cancellation handler
        self.cancellator.register(name: "build system", handler: buildSystem.cancel)
        return buildSystem
    }

    static let entitlementsMacOSWarning = """
    `--enable-get-task-allow-entitlement` and `--disable-get-task-allow-entitlement` only have an effect \
    when building on macOS.
    """

    package func computeSDKRootOverride() -> AbsolutePath? {
        let sdkRootOverride = self.options.build.customCompileSDK
            ?? self.environment["SDKROOT"].flatMap { try? AbsolutePath(validating: $0) }
        guard let sdkRootOverride else {
            return nil
        }
        if let swiftSDKSelector = self.options.build.swiftSDKSelector {
            let source = self.options.build.customCompileSDK != nil
                ? "'--sdk'"
                : "the 'SDKROOT' environment variable"
            self.observabilityScope.emit(warning: "ignoring the SDK '\(sdkRootOverride)' specified using \(source) because the Swift SDK '\(swiftSDKSelector)' was selected with '--swift-sdk'")
            return nil
        } else {
            return sdkRootOverride
        }
    }

    private func _buildParams(
        toolchain: UserToolchain,
        destination: BuildParameters.Destination,
        prepareForIndexing: Bool
    ) throws -> BuildParameters {
        let triple = toolchain.targetTriple

        let dataPath = self.scratchDirectory.appending(
            component: triple.platformBuildPathComponent(buildSystem: self.options.build.buildSystem)
        )

        if self.options.build.getTaskAllowEntitlement != nil && !triple.isMacOSX {
            self.observabilityScope.emit(warning: Self.entitlementsMacOSWarning)
        }

        let prepareForIndexingMode: BuildParameters.PrepareForIndexingMode =
            switch (prepareForIndexing, self.options.build.prepareForIndexingNoLazy) {
            case (false, _): .off
            case (true, false): .on
            case (true, true): .noLazy
            }

        return try BuildParameters(
            destination: destination,
            dataPath: dataPath,
            configuration: self.options.build.configuration ?? self.preferredBuildConfiguration,
            toolchain: toolchain,
            triple: triple,
            sdkRootOverride: self.computeSDKRootOverride(),
            flags: options.build.buildFlags,
            buildSystemKind: options.build.buildSystem,
            pkgConfigDirectories: options.locations.pkgConfigDirectories,
            customToolsetPaths: options.locations.toolsetPaths,
            architectures: options.build.architectures,
            workers: options.build.jobs,
            shouldCreateDylibForDynamicProducts: !self.options.build.shouldBuildDylibsAsFrameworks,
            sanitizers: options.build.enabledSanitizers,
            indexStoreMode: options.build.indexStoreMode.buildParameter,
            prepareForIndexing: prepareForIndexingMode,
            enableXCFrameworksOnLinux: options.build.enableXCFrameworksOnLinux,
            debuggingParameters: .init(
                debugInfoFormat: self.options.build.debugInfoFormat?.buildParameter,
                triple: triple,
                shouldEnableDebuggingEntitlement:
                self.options.build
                    .getTaskAllowEntitlement ??
                    (self.options.build.configuration ?? self.preferredBuildConfiguration == .debug),
                omitFramePointers: self.options.build.omitFramePointers
            ),
            driverParameters: .init(
                canRenameEntrypointFunctionName: DriverSupport.checkSupportedFrontendFlags(
                    flags: ["entry-point-function-name"],
                    toolchain: toolchain,
                    fileSystem: self.fileSystem
                ) && !options.build.sanitizers.contains(.fuzzer),
                enableParseableModuleInterfaces: self.options.build.shouldEnableParseableModuleInterfaces,
                explicitTargetDependencyImportCheckingMode: self.options.build.explicitTargetDependencyImportCheck
                    .modeParameter,
                useIntegratedSwiftDriver: self.options.build.useIntegratedSwiftDriver,
                isPackageAccessModifierSupported: DriverSupport.isPackageNameSupported(
                    toolchain: toolchain,
                    fileSystem: self.fileSystem
                )
            ),
            linkingParameters: .init(
                linkerDeadStrip: self.options.linker.linkerDeadStrip,
                linkTimeOptimizationMode: self.options.build.linkTimeOptimizationMode?.buildParameter,
                shouldDisableLocalRpath: self.options.linker.shouldDisableLocalRpath
            ),
            outputParameters: .init(
                isColorized: self.options.logging.colorDiagnostics,
                isVerbose: self.logLevel <= .info,
                enableTaskBacktraces: self.options.build.enableTaskBacktraces,
                traceEventsFilePath: try self.options.build.traceEventsFilePath.map {
                    try AbsolutePath(
                        validating: $0,
                        relativeTo: self.fileSystem.currentWorkingDirectory ?? .root
                    )
                }
            ),
            testingParameters: .init(
                forceTestDiscovery: self.options.build.enableTestDiscovery,
                // backwards compatibility, remove with --enable-test-discovery
                testEntryPointPath: self.options.build.testEntryPointPath
            ),
            stripProducts: self.options.build.stripProducts,
            shouldPreserveSymlinks: options.locations.skipResolvingPackagePaths,
        )
    }

    /// Return the build parameters for the host toolchain.
    public var toolsBuildParameters: BuildParameters {
        get throws {
            try self._toolsBuildParameters.get()
        }
    }

    private lazy var _toolsBuildParameters: Result<BuildParameters, Swift.Error> = Result(catching: {
        // Tools need to do a full build
        try self._buildParams(toolchain: self.getHostToolchain(), destination: .host, prepareForIndexing: false)
    })

    public var productsBuildParameters: BuildParameters {
        get throws {
            try self._productsBuildParameters.get()
        }
    }

    private lazy var _productsBuildParameters: Result<BuildParameters, Swift.Error> = Result(catching: {
        try self._buildParams(
            toolchain: self.getTargetToolchain(),
            destination: .target,
            prepareForIndexing: self.options.build.prepareForIndexing
        )
    })

    /// Lazily compute the target toolchain.
    private lazy var _targetToolchain: Result<UserToolchain, Swift.Error> = {
        let swiftSDK: SwiftSDK
        let hostSwiftSDK: SwiftSDK
        do {
            let hostToolchain = try _hostToolchain.get()
            hostSwiftSDK = hostToolchain.swiftSDK

            if self.options.build.deprecatedSwiftSDKSelector != nil {
                self.observabilityScope.emit(
                    warning: "`--experimental-swift-sdk` is deprecated and will be removed in a future version of SwiftPM. Use `--swift-sdk` instead."
                )
            }

            let store = SwiftSDKBundleStore(
                swiftSDKsDirectory: self.sharedSwiftSDKsDirectory,
                hostToolchainBinDir: hostToolchain.swiftCompilerPath.parentDirectory,
                fileSystem: self.fileSystem,
                observabilityScope: self.observabilityScope,
                outputHandler: { print($0.description) }
            )

            swiftSDK = try SwiftSDK.deriveTargetSwiftSDK(
                hostSwiftSDK: hostSwiftSDK,
                hostTriple: hostToolchain.targetTriple,
                customToolsets: self.options.locations.toolsetPaths,
                customCompileDestination: self.options.locations.customCompileDestination,
                customCompileTriple: self.options.build.customCompileTriple,
                customCompileToolchain: self.options.build.customCompileToolchain,
                customCompileSDK: self.options.build.customCompileSDK,
                swiftSDKSelector: self.options.build.swiftSDKSelector ?? self.options.build.deprecatedSwiftSDKSelector,
                architectures: self.options.build.architectures,
                store: store,
                observabilityScope: self.observabilityScope,
                fileSystem: self.fileSystem
            )
        } catch {
            return .failure(error)
        }
        // Check if we ended up with the host toolchain.
        if hostSwiftSDK == swiftSDK {
            return self._hostToolchain
        }

        return Result(catching: {
            try UserToolchain(
                swiftSDK: swiftSDK,
                environment: self.environment,
                customTargetInfo: targetInfo,
                observabilityScope: self.observabilityScope,
                fileSystem: self.fileSystem)
        })
    }()

    /// Lazily compute the host toolchain used to compile the package description.
    private lazy var _hostToolchain: Result<UserToolchain, Swift.Error> = Result(catching: {
        var hostSwiftSDK = try SwiftSDK.hostSwiftSDK(
            environment: self.environment,
            observabilityScope: self.observabilityScope
        )
        hostSwiftSDK.targetTriple = self.hostTriple

        return try UserToolchain(
            swiftSDK: hostSwiftSDK,
            environment: self.environment,
            customTargetInfo: targetInfo,
            observabilityScope: self.observabilityScope,
            fileSystem: self.fileSystem
        )
    })

    private lazy var _manifestLoader: Result<ManifestLoader, Swift.Error> = Result(catching: {
        let cachePath: AbsolutePath? = switch (
            self.options.caching.shouldDisableManifestCaching,
            self.options.caching.manifestCachingMode
        ) {
        case (true, _):
            // backwards compatibility
            .none
        case (false, .none):
            .none
        case (false, .local):
            self.scratchDirectory
        case (false, .shared):
            PackageWorkspace.DefaultLocations.manifestsDirectory(at: self.sharedCacheDirectory)
        }

        var extraManifestFlags = self.options.build.manifestFlags
        if self.logLevel <= .info {
            extraManifestFlags.append("-v")
        }

        return try ManifestLoader(
            // Always use the host toolchain's resources for parsing manifest.
            toolchain: self.getHostToolchain(),
            isManifestSandboxEnabled: !self.shouldDisableSandbox,
            cacheDir: cachePath,
            extraManifestFlags: extraManifestFlags,
            importRestrictions: .none,
            pruneDependencies: self.options.resolver.pruneDependencies
        )
    })

    /// An enum indicating the execution status of run commands.
    public enum ExecutionStatus {
        case success
        case failure
    }

    // MARK: - Locking

    // This is used to attempt to prevent accidental misuse of the locking APIs.
    private enum WorkspaceLockState {
        case unspecified
        case needsLocking
        case locked
        case unlocked
    }

    private var workspaceLockState: WorkspaceLockState = .unspecified
    private var workspaceLock: FileLock?

    fileprivate func setNeedsLocking() {
        assert(
            self.workspaceLockState == .unspecified,
            "attempting to `setNeedsLocking()` from unexpected state: \(self.workspaceLockState)"
        )
        self.workspaceLockState = .needsLocking
    }

    private func acquireLockIfNeeded() throws {
        guard !options.locations.skipAcquiringLock else {
            return
        }
        guard self.packageRoot != nil else {
            return
        }
        assert(
            self.workspaceLockState == .needsLocking,
            "attempting to `acquireLockIfNeeded()` from unexpected state: \(self.workspaceLockState)"
        )
        guard workspaceLock == nil else {
            throw InternalError("acquireLockIfNeeded() called multiple times")
        }
        self.workspaceLockState = .locked

        let workspaceLock = try FileLock.prepareLock(fileToLock: self.scratchDirectory)
        let lockFile = self.scratchDirectory.appending(".lock").pathString

        // Try a non-blocking lock first so that we can inform the user about an already running SwiftPM.
        do {
            try workspaceLock.lock(type: .exclusive, blocking: false)
            let pid = ProcessInfo.processInfo.processIdentifier
            try? String(pid).write(toFile: lockFile, atomically: true, encoding: .utf8)
        } catch ProcessLockError.unableToAquireLock(let errno) {
            if errno == EWOULDBLOCK {
                let lockingPID = try? String(contentsOfFile: lockFile, encoding: .utf8)
                let pidInfo = lockingPID.map { "(PID: \($0)) " } ?? ""

                if self.options.locations.ignoreLock {
                    self.outputStream
                        .write(
                            "Another instance of SwiftPM \(pidInfo)is already running using '\(self.scratchDirectory)', but this will be ignored since `--ignore-lock` has been passed"
                                .utf8
                        )
                    self.outputStream.flush()
                } else {
                    self.outputStream
                        .write(
                            "Another instance of SwiftPM \(pidInfo)is already running using '\(self.scratchDirectory)', waiting until that process has finished execution..."
                                .utf8
                        )
                    self.outputStream.flush()

                    // Only if we fail because there's an existing lock we need to acquire again as blocking.
                    try workspaceLock.lock(type: .exclusive, blocking: true)

                    let pid = ProcessInfo.processInfo.processIdentifier
                    try? String(pid).write(toFile: lockFile, atomically: true, encoding: .utf8)
                }
            }
        }

        self.workspaceLock = workspaceLock
    }

    fileprivate func releaseLockIfNeeded() {
        // Never having acquired the lock is not an error case.
        assert(
            self.workspaceLockState == .locked || self.workspaceLockState == .needsLocking,
            "attempting to `releaseLockIfNeeded()` from unexpected state: \(self.workspaceLockState)"
        )
        self.workspaceLockState = .unlocked

        self.workspaceLock?.unlock()
    }
}

extension SwiftCommandState {
    /// Returns an error `Diagnostic` when a workspace-member focus was
    /// resolved but the selected build system does not support it.
    /// Returns `nil` when the combination is compatible.
    ///
    /// Workspaces are currently only supported with the Swift Build
    /// build system. If a user invokes any workspace-aware command
    /// (i.e. one that runs `getWorkspaceRoot()`) from inside a
    /// workspace member while requesting a different build system, we
    /// surface a hard error rather than silently building the whole
    /// workspace under the wrong backend.
    ///
    /// Extracted as a pure static helper so it can be unit-tested
    /// without instantiating a full `SwiftCommandState`.
    static func workspaceMemberFocusRequiresSwiftBuildDiagnostic(
        focus: PackageIdentity?,
        buildSystem: BuildSystemProvider.Kind,
    ) -> Diagnostic? {
        guard let focus, buildSystem != .swiftbuild else { return nil }
        return .invalidWorkspaceBuildSystem(focus: focus)
    }

    /// Pure decision logic for choosing where `Package.resolved` lives.
    ///
    /// Ordering:
    /// 1. `--multiroot-data-file` — explicit Xcode-workspace override.
    ///    Wins over everything else because it predates the Slice 1
    ///    workspace model and is a stronger signal.
    /// 2. `Workspace.swift` + Swift Build — when the workspace is
    ///    discovered AND the build system is Swift Build,
    ///    `Package.resolved` sits at the workspace root so all members
    ///    share a single resolution file. No member ever writes its
    ///    own. Restricted to Swift Build because the workspace model
    ///    (Slice 1+) is only wired through that backend; letting the
    ///    native / XCBuild systems observe a workspace-root
    ///    `Package.resolved` would leave them looking for a per-package
    ///    file that no longer exists and re-resolving on every build.
    /// 3. Single-package (or workspace under a non-Swift Build
    ///    backend) — the pre-workspaces default: sibling of the root
    ///    `Package.swift`.
    ///
    /// Extracted so the ordering can be unit-tested without spinning
    /// up a full `SwiftCommandState` or touching the filesystem.
    static func
    computeResolvedVersionsFile(
        multiRootPackageDataFile: AbsolutePath?,
        workspaceRoot: AbsolutePath?,
        packageRoot: AbsolutePath?,
        buildSystem: BuildSystemProvider.Kind,
    ) throws -> AbsolutePath {
        if let multiRootPackageDataFile {
            return multiRootPackageDataFile.appending(
                components: "xcshareddata",
                "swiftpm",
                PackageWorkspace.DefaultLocations.resolvedFileName,
            )
        }
        if let workspaceRoot, buildSystem == .swiftbuild {
            return workspaceRoot.appending(PackageWorkspace.DefaultLocations.resolvedFileName)
        }
        guard let packageRoot else {
            throw SwiftCommandStateError.packageManifestNotFound
        }
        return PackageWorkspace.DefaultLocations.resolvedVersionsFile(forRootPackage: packageRoot)
    }

    /// Pure decision helper that computes the local configuration
    /// directory (`.swiftpm/configuration/…`) — the folder that
    /// houses `mirrors.json`, `registries.json`, and
    /// `workspace-overrides.json`.
    ///
    /// Under a SwiftPM workspace the directory anchors to the
    /// workspace root so `swift package config set-mirror` writes a
    /// single file every member reads. Extracted so the ordering can
    /// be unit-tested without spinning up a full `SwiftCommandState`
    /// or touching the filesystem.
    @_spi(SwiftPMTesting)
    public static func computeLocalConfigurationDirectory(
        multiRootPackageDataFile: AbsolutePath?,
        workspaceRoot: AbsolutePath?,
        packageRoot: AbsolutePath?,
    ) throws -> AbsolutePath {
        if let multiRootPackageDataFile {
            return multiRootPackageDataFile
                .appending(components: "xcshareddata", "swiftpm", "configuration")
        }
        if let workspaceRoot {
            return PackageWorkspace.DefaultLocations
                .configurationDirectory(forRootPackage: workspaceRoot)
        }
        guard let packageRoot else {
            throw SwiftCommandStateError.packageManifestNotFound
        }
        return PackageWorkspace.DefaultLocations
            .configurationDirectory(forRootPackage: packageRoot)
    }

    /// Pure decision helper: returns the conflict diagnostic when
    /// both `--multiroot-data-file` and a discovered SwiftPM
    /// `Workspace.swift` are present, `nil` otherwise. The two
    /// mechanisms target incompatible workspace layouts (Xcode
    /// workspace vs. SwiftPM workspace); the caller is expected to
    /// emit the returned diagnostic and abort.
    ///
    /// Extracted so the truth table (four combinations of the two
    /// optional inputs) can be unit-tested without spinning up a
    /// full `SwiftCommandState`.
    @_spi(SwiftPMTesting)
    public static func multirootDataFileConflictDiagnostic(
        multirootDataFile: AbsolutePath?,
        discoveredWorkspaceRoot: AbsolutePath?,
    ) -> Basics.Diagnostic? {
        guard let multirootDataFile, let discoveredWorkspaceRoot else {
            return nil
        }
        return .multirootDataFileConflictsWithWorkspace(
            multirootDataFile: multirootDataFile,
            workspaceRoot: discoveredWorkspaceRoot,
        )
    }

    /// Pure argv-scanning helper: returns `true` iff the deprecated
    /// `--package-path` spelling appears anywhere in `arguments`
    /// (space-separated `--package-path <value>` OR the equals form
    /// `--package-path=<value>`). Consumed by the CLI startup path
    /// to decide whether to emit the deprecation warning that steers
    /// users toward `--path`.
    ///
    /// The aliased `@Option` on `LocationOptions` gives us last-wins
    /// value semantics for the two spellings automatically — this
    /// helper only answers "was the deprecated spelling ever
    /// typed", which ArgumentParser doesn't surface through the
    /// parsed value alone.
    @_spi(SwiftPMTesting)
    public static func packagePathDeprecationWarranted(
        arguments: [String],
    ) -> Bool {
        return Self.isArgumentDeprecationWarranted(for: "--package-path", arguments: arguments)
    }

    @_spi(SwiftPMTesting)
    public static func isArgumentDeprecationWarranted(
        for deprecatedArgument: String,
        arguments: [String],
    ) -> Bool {
        arguments.contains { arg in
            arg == "\(deprecatedArgument)" || arg.hasPrefix("\(deprecatedArgument)=")
        }
    }

}

/// Errors surfaced by `SwiftCommandState` decision helpers.
public enum SwiftCommandStateError: Error, CustomStringConvertible {
    /// `Package.swift` was not discoverable from the current working
    /// directory or any of its parents, and no explicit anchor
    /// (workspace root, `--multiroot-data-file`, or `--package-path`)
    /// was supplied to substitute for one.
    case packageManifestNotFound

    public var description: String {
        switch self {
        case .packageManifestNotFound:
            "Could not find \(Manifest.filename) in this directory or any of its parent directories."
        }
    }
}

extension BuildSystemProvider.Kind {
    fileprivate var shouldCreateMultipleTestProducts: Bool {
        switch self {
        case .xcode, .swiftbuild:
            return true
        case .native:
            return false
        }
    }

    fileprivate var additionalFileRules: [FileRuleDescription] {
        switch self {
        case .xcode:
            FileRuleDescription.xcbuildFileTypes
        case .swiftbuild:
            FileRuleDescription.swiftBuildFileTypes
        case .native:
            FileRuleDescription.swiftpmFileTypes
        }
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
    while !fileSystem.isFile(root.appending(component: Manifest.filename))
        && !fileSystem.isFile(root.appending(component: WorkspaceManifest.filename))
    {
        root = root.parentDirectory
        guard !root.isRoot else {
            return nil
        }
    }
    return root
}

private func getSharedSecurityDirectory(options: GlobalOptions, fileSystem: FileSystem) throws -> AbsolutePath {
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

private func getSharedConfigurationDirectory(options: GlobalOptions, fileSystem: FileSystem) throws -> AbsolutePath {
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

private func getSharedCacheDirectory(options: GlobalOptions, fileSystem: FileSystem) throws -> AbsolutePath {
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

extension SwiftCommandState {
    // FIXME: deprecate these one we are further along refactoring the call sites that use it
    /// The stream to print standard output on.
    public var outputStream: OutputByteStream {
        self.observabilityHandler.outputStream
    }
}

extension PackageWorkspace.ManagedDependency {
    fileprivate var isEdited: Bool {
        if case .edited = self.state { return true }
        return false
    }
}

extension LoggingOptions {
    fileprivate var logLevel: Diagnostic.Severity {
        if self.verbose {
            .info
        } else if self.veryVerbose {
            .debug
        } else if self.quiet {
            .error
        } else {
            .warning
        }
    }
}

extension ResolverOptions.SourceControlToRegistryDependencyTransformation {
    fileprivate var workspaceConfiguration: WorkspaceConfiguration.SourceControlToRegistryDependencyTransformation {
        switch self {
        case .disabled:
            .disabled
        case .identity:
            .identity
        case .swizzle:
            .swizzle
        }
    }
}

extension BuildOptions.StoreMode {
    fileprivate var buildParameter: BuildParameters.IndexStoreMode {
        switch self {
        case .autoIndexStore:
            .auto
        case .enableIndexStore:
            .on
        case .disableIndexStore:
            .off
        }
    }
}

extension BuildOptions.TargetDependencyImportCheckingMode {
    fileprivate var modeParameter: BuildParameters.TargetDependencyImportCheckingMode {
        switch self {
        case .none:
            .none
        case .warn:
            .warn
        case .error:
            .error
        }
    }
}

extension BuildOptions.LinkTimeOptimizationMode {
    fileprivate var buildParameter: BuildParameters.LinkTimeOptimizationMode? {
        switch self {
        case .full:
            .full
        case .thin:
            .thin
        }
    }
}

extension BuildOptions.DebugInfoFormat {
    fileprivate var buildParameter: BuildParameters.DebugInfoFormat {
        switch self {
        case .dwarf:
            .dwarf
        case .codeview:
            .codeview
        case .none:
            .none
        }
    }
}

extension Basics.Diagnostic {
    public static func mutuallyExclusiveArgumentsError(arguments: [String]) -> Self {
        .error(arguments.map { "'\($0)'" }.spm_localizedJoin(type: .conjunction) + " are mutually exclusive")
    }

    package static func deprecatedBuildSystem(buildSystem: BuildSystemProvider.Kind) -> Self {
        .warning(
            "'--build-system \(buildSystem)' has been deprecated and will be removed in a future release; please report an issue at https://github.com/swiftlang/swift-package-manager/issues if you are unable to adopt the default build system."
        )
    }

    /// Deprecation warning for a renamed CLI flag. Used at command
    /// startup when a deprecated spelling is detected in argv (see
    /// `SwiftCommandState.packagePathDeprecationWarranted(arguments:)`).
    /// The message steers users toward the new spelling without
    /// breaking anything — the deprecated flag still functions.
    @_spi(SwiftPMInternal)
    public static func argumentDeprecated(flag: String, renamed: String) -> Self {
        .warning(
            "'\(flag)' is deprecated; use '\(renamed)' instead."
        )
    }

    static func invalidWorkspaceBuildSystem(focus: PackageIdentity) -> Self {
        .error(
            """
            workspace-member focus (current directory is inside member '\(focus)') \
            requires --build-system \(BuildSystemProvider.Kind.swiftbuild); re-run with \
            --build-system \(BuildSystemProvider.Kind.swiftbuild), or run from the workspace \
            root to build every member.
            """,
        )
    }

    /// Diagnostic emitted when `--package <identity>` is supplied but
    /// the identity is not a declared workspace member. Lists the known
    /// identities so the user can correct the invocation.
    @_spi(SwiftPMInternal)
    public static func unknownWorkspaceMember(
        requested: PackageIdentity,
        known: Set<PackageIdentity>,
    ) -> Self {
        let sortedKnown = known.map(\.description).sorted()
        return .error(
            """
            no workspace member with identity '\(requested)'; known members: \
            \(sortedKnown.map { "'\($0)'" }.joined(separator: ", "))
            """,
        )
    }

    /// Diagnostic emitted when `--package <identity>` is supplied but
    /// there is no `Workspace.swift` discoverable from CWD. Points the
    /// user at the missing precondition.
    @_spi(SwiftPMInternal)
    public static func packageSelectorRequiresWorkspace(requested: PackageIdentity) -> Self {
        .error(
            """
            --package '\(requested)' requires a Workspace.swift; either \
            run from inside a workspace, or invoke without --package.
            """,
        )
    }

    /// Diagnostic emitted when `swift package dump-package` is
    /// invoked at a workspace root that has more than one member and
    /// no `--package` selector was supplied. `dump-package` emits a
    /// single manifest, so a multi-member workspace is ambiguous —
    /// list the known members and point the user at `--package`.
    @_spi(SwiftPMInternal)
    public static func dumpPackageRequiresPackageSelector(
        known: Set<PackageIdentity>,
    ) -> Self {
        let sortedKnown = known.map(\.description).sorted()
        return .error(
            """
            dump-package requires --package <identity> in a workspace \
            with multiple members; known members: \
            \(sortedKnown.map { "'\($0)'" }.joined(separator: ", "))
            """,
        )
    }

    /// Diagnostic emitted when `--multiroot-data-file` is supplied
    /// alongside a discoverable `Workspace.swift` — the two
    /// mechanisms target different workspace layouts (Xcode
    /// workspace vs. SwiftPM workspace) and can't coexist for a
    /// single invocation. Points at BOTH paths so the user knows
    /// where each mode is anchored.
    @_spi(SwiftPMInternal)
    public static func multirootDataFileConflictsWithWorkspace(
        multirootDataFile: AbsolutePath,
        workspaceRoot: AbsolutePath,
    ) -> Self {
        .error(
            """
            '--multiroot-data-file \(multirootDataFile.pathString)' cannot be used \
            together with the SwiftPM workspace at '\(workspaceRoot.pathString)'; \
            remove the flag or move the invocation outside the Workspace.swift tree
            """,
        )
    }
}
