/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import Build
import PackageLoading
import PackageGraph
import PackageModel
import POSIX
import SourceControl
import Utility
import Workspace
import libc

struct ChdirDeprecatedDiagnostic: DiagnosticData {
    static let id = DiagnosticID(
        type: AnyDiagnostic.self,
        name: "org.swift.diags.chdir-deprecated",
        defaultBehavior: .warning,
        description: {
            $0 <<< "the '--chdir/-C' option is deprecated; use '--package-path' instead"
        }
    )
}

private class ToolWorkspaceDelegate: WorkspaceDelegate {

    func packageGraphWillLoad(
        currentGraph: PackageGraph,
        dependencies: AnySequence<ManagedDependency>,
        missingURLs: Set<String>
    ) {
    }

    func fetchingWillBegin(repository: String) {
        print("Fetching \(repository)")
    }

    func fetchingDidFinish(repository: String, diagnostic: Diagnostic?) {
    }

    func repositoryWillUpdate(_ repository: String) {
        print("Updating \(repository)")
    }

    func repositoryDidUpdate(_ repository: String) {
    }

    func cloning(repository: String) {
        print("Cloning \(repository)")
    }

    func checkingOut(repository: String, atReference reference: String, to path: AbsolutePath) {
        // FIXME: This is temporary output similar to old one, we will need to figure
        // out better reporting text.
        print("Resolving \(repository) at \(reference)")
    }

    func removing(repository: String) {
        print("Removing \(repository)")
    }

    func warning(message: String) {
        print("warning: " + message)
    }

    func managedDependenciesDidUpdate(_ dependencies: AnySequence<ManagedDependency>) {
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
    func getWorkspaceRoot() throws -> WorkspaceRoot {
        return try WorkspaceRoot(packages: [getPackageRoot()])
    }

    /// Path to the build directory.
    let buildPath: AbsolutePath

    /// Reference to the argument parser.
    let parser: ArgumentParser

    /// The process set to hold the launched processes. These will be terminated on any signal
    /// received by the swift tools.
    let processSet: ProcessSet

    /// The interrupt handler.
    let interruptHandler: InterruptHandler

    /// The diagnostics engine.
    let diagnostics = DiagnosticsEngine()

    /// The execution status of the tool.
    var executionStatus: ExecutionStatus = .success

    /// Create an instance of this tool.
    ///
    /// - parameter args: The command line arguments to be passed to this tool.
    public init(toolName: String, usage: String, overview: String, args: [String]) {
        // Capture the original working directory ASAP.
        originalWorkingDirectory = currentWorkingDirectory
        
        // Create the parser.
        parser = ArgumentParser(
            commandName: "swift \(toolName)",
            usage: usage,
            overview: overview)

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
            to: { $0.buildFlags = BuildFlags(xcc: $1, xswiftc: $2, xlinker: $3) })

        binder.bind(
            option: parser.add(
                option: "--configuration", shortName: "-c", kind: Build.Configuration.self,
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
            option: parser.add(option: "--enable-prefetching", kind: Bool.self, usage: ""),
            to: { $0.shouldEnableResolverPrefetching = $1 })

        binder.bind(
            option: parser.add(option: "--disable-prefetching", kind: Bool.self, usage: ""),
            to: { $0.shouldEnableResolverPrefetching = !$1 })

        binder.bind(
            option: parser.add(option: "--disable-sandbox", kind: Bool.self,
            usage: "Disable using the sandbox when executing subprocesses"),
            to: { $0.shouldDisableSandbox = $1 })

        binder.bind(
            option: parser.add(option: "--version", kind: Bool.self),
            to: { $0.shouldPrintVersion = $1 })

        binder.bind(
            option: parser.add(option: "--destination", kind: PathArgument.self),
            to: { $0.customCompileDestination = $1.path })

        // FIXME: We need to allow -vv type options for this.
        binder.bind(
            option: parser.add(option: "--verbose", shortName: "-v", kind: Bool.self,
                usage: "Increase verbosity of informational output"),
            to: { $0.verbosity = $1 ? 1 : 0 })

        // Let subclasses bind arguments.
        type(of: self).defineArguments(parser: parser, binder: binder)

        do {
            // Parse the result.
            let result = try parser.parse(args)

            var options = Options()
            binder.fill(result, into: &options)

            self.options = options
            // Honor package-path option is provided.
            if let packagePath = options.packagePath ?? options.chdir {
                // FIXME: This should be an API which takes AbsolutePath and maybe
                // should be moved to file system APIs with currentWorkingDirectory.
                try POSIX.chdir(packagePath.asString)
            }

            let processSet = ProcessSet()
            interruptHandler = try InterruptHandler {
                // Terminate all processes on receiving an interrupt signal.
                processSet.terminate()

                // Install the default signal handler.
                var action = sigaction()
              #if os(macOS)
                action.__sigaction_u.__sa_handler = SIG_DFL
              #else
                action.__sigaction_handler = unsafeBitCast(
                    SIG_DFL,
                    to: sigaction.__Unnamed_union___sigaction_handler.self)
              #endif
                sigaction(SIGINT, &action, nil)

                // Die with sigint.
                kill(getpid(), SIGINT)
            }
            self.processSet = processSet

        } catch {
            handle(error: error)
            SwiftTool.exit(with: .failure)
        }

        // Create local variables to use while finding build path to avoid capture self before init error.
        let customBuildPath = options.buildPath
        let packageRoot = findPackageRoot()

        self.packageRoot = packageRoot
        self.buildPath = getEnvBuildPath() ??
            customBuildPath ??
            (packageRoot ?? currentWorkingDirectory).appending(component: ".build")
        
        if options.chdir != nil {
            diagnostics.emit(data: ChdirDeprecatedDiagnostic())
        }
    }

    class func defineArguments(parser: ArgumentParser, binder: ArgumentBinder<Options>) {
        fatalError("Must be implmented by subclasses")
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
        let delegate = ToolWorkspaceDelegate()
        let rootPackage = try getPackageRoot()
        let provider = GitRepositoryProvider(processSet: processSet)
        let workspace = Workspace(
            dataPath: buildPath,
            editablesPath: rootPackage.appending(component: "Packages"),
            pinsFile: rootPackage.appending(component: "Package.resolved"),
            manifestLoader: try getManifestLoader(),
            toolsVersionLoader: ToolsVersionLoader(),
            delegate: delegate,
            repositoryProvider: provider,
            isResolverPrefetchingEnabled: options.shouldEnableResolverPrefetching
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
                throw Error.hasFatalDiagnostics
            }
            // Print any non fatal diagnostics like warnings, notes.
            printDiagnostics()
        } catch {
            // Set execution status to failure in case of errors.
            executionStatus = .failure
            printDiagnostics()
            handle(error: error)
        }
        SwiftTool.exit(with: executionStatus)
    }

    private func printDiagnostics() {
        for diagnostic in diagnostics.diagnostics {
            print(diagnostic: diagnostic)
        }
    }

    /// Exit the tool with the given execution status.
    private static func exit(with status: ExecutionStatus) -> Never {
        switch status {
        case .success: POSIX.exit(0)
        case .failure: POSIX.exit(1)
        }
    }

    /// Run method implmentation to be overridden by subclasses.
    func runImpl() throws {
        fatalError("Must be implmented by subclasses")
    }

    /// Resolve the dependencies.
    func resolve() throws {
        let workspace = try getActiveWorkspace()
        workspace.resolve(root: try getWorkspaceRoot(), diagnostics: diagnostics)

        // Throw if there were errors when loading the graph.
        // The actual errors will be printed before exiting.
        guard !diagnostics.hasErrors else {
            throw Error.hasFatalDiagnostics
        }
    }

    /// Fetch and load the complete package graph.
    @discardableResult
    func loadPackageGraph() throws -> PackageGraph {
        let workspace = try getActiveWorkspace()

        // Fetch and load the package graph.
        let graph = try workspace.loadPackageGraph(
            root: getWorkspaceRoot(), diagnostics: diagnostics)

        // Throw if there were errors when loading the graph.
        // The actual errors will be printed before exiting.
        guard !diagnostics.hasErrors else {
            throw Error.hasFatalDiagnostics
        }
        return graph
    }

    /// Returns the user toolchain to compile the actual product.
    func getToolchain() throws -> UserToolchain {
        return try _destinationToolchain.dematerialize()
    }

    func getManifestLoader() throws -> ManifestLoader {
        return try _manifestLoader.dematerialize()
    }

    /// Build the package graph using swift-build-tool.
    func build(includingTests: Bool) throws {
        try build(plan: buildPlan(), includingTests: includingTests)
    }
    
    /// Build the package graph using swift-build-tool.
    func build(plan: BuildPlan, includingTests: Bool) throws {
        guard !plan.graph.rootPackages[0].targets.isEmpty else {
            warning(message: "no targets to build in package")
            return
        }

        let yaml = buildPath.appending(component: plan.buildParameters.configuration.dirname + ".yaml")
        // Generate llbuild manifest.
        let llbuild = LLbuildManifestGenerator(plan)
        try llbuild.generateManifest(at: yaml)
        assert(isFile(yaml), "llbuild manifest not present: \(yaml.asString)")

        // Run the swift-build-tool with the generated manifest.
        var args = [String]()

      #if os(macOS)
        // If enabled, use sandbox-exec on macOS. This provides some safety
        // against arbitrary code execution. We only allow the permissions which
        // are absolutely necessary for performing a build.
        if !options.shouldDisableSandbox {
            let allowedDirectories = [buildPath, BuildParameters.swiftpmTestCache].map(resolveSymlinks)
            args += ["sandbox-exec", "-p", sandboxProfile(allowedDirectories: allowedDirectories)]
        }
      #endif

        args += [try getToolchain().llbuild.asString, "-f", yaml.asString]
        if includingTests {
            args.append("test")
        }
        if verbosity != .concise {
            args.append("-v")
        }

        // Run llbuild and print output on standard streams.
        let process = Process(arguments: args, redirectOutput: false)
        try process.launch()
        try processSet.add(process)
        let result = try process.waitUntilExit()

        guard result.exitStatus == .terminated(code: 0) else {
            throw ProcessResult.Error.nonZeroExit(result)
        }
    }

    /// Generates a BuildPlan based on the tool's options.
    func buildPlan() throws -> BuildPlan {
        return try BuildPlan(
            buildParameters: BuildParameters(
                dataPath: buildPath,
                configuration: options.configuration,
                toolchain: try getToolchain(),
                flags: options.buildFlags),
            graph: try loadPackageGraph(),
            delegate: self)
    }

    /// Lazily compute the destination toolchain.
    private lazy var _destinationToolchain: Result<UserToolchain, AnyError> = {
        // Create custom toolchain if present.
        if let customDestination = self.options.customCompileDestination {
            return Result(anyError: {
                try UserToolchain(destination: Destination(fromFile: customDestination))
            })
        }
        // Otherwise use the host toolchain.
        return self._hostToolchain
    }()

    /// Lazily compute the host toolchain used to compile the package description.
    private lazy var _hostToolchain: Result<UserToolchain, AnyError> = {
        return Result(anyError: {
            try UserToolchain(destination: Destination.hostDestination(
                        originalWorkingDirectory: self.originalWorkingDirectory))
        })
    }()

    private lazy var _manifestLoader: Result<ManifestLoader, AnyError> = {
        return Result(anyError: {
            try ManifestLoader(
                // Always use the host toolchain's resources for parsing manifest.
                resources: self._hostToolchain.dematerialize().manifestResources,
                isManifestSandboxEnabled: !self.options.shouldDisableSandbox
            )
        })
    }()

    /// An enum indicating the execution status of run commands.
    enum ExecutionStatus {
        case success
        case failure
    }
}

extension SwiftTool: BuildPlanDelegate {
    public func warning(message: String) {
        // FIXME: Coloring would be nice.
        print("warning: " + message)
    }
}

/// Returns path of the nearest directory containing the manifest file w.r.t
/// current working directory.
private func findPackageRoot() -> AbsolutePath? {
    // FIXME: It would be nice to move this to a generalized method which takes path and predicate and
    // finds the lowest path for which the predicate is true.
    var root = currentWorkingDirectory
    while !isFile(root.appending(component: Manifest.filename)) {
        root = root.parentDirectory
        guard !root.isRoot else {
            return nil
        }
    }
    return root
}

private func getEnvBuildPath() -> AbsolutePath? {
    // Don't rely on build path from env for SwiftPM's own tests.
    guard POSIX.getenv("IS_SWIFTPM_TEST") == nil else { return nil }
    guard let env = POSIX.getenv("SWIFT_BUILD_PATH") else { return nil }
    return AbsolutePath(env, relativeTo: currentWorkingDirectory)
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
        stream <<< "    (regex #\"^\(directory.asString)/org\\.llvm\\.clang.*\")" <<< "\n"
        // For archive tool.
        stream <<< "    (regex #\"^\(directory.asString)/ar.*\")" <<< "\n"
        // For xcrun cache.
        stream <<< "    (regex #\"^\(directory.asString)/xcrun.*\")" <<< "\n"
        // For autolink files.
        stream <<< "    (regex #\"^\(directory.asString)/.*\\.swift-[0-9a-f]+\\.autolink\")" <<< "\n"
    }
    for directory in allowedDirectories {
        stream <<< "    (subpath \"\(directory.asString)\")" <<< "\n"
    }
    stream <<< ")" <<< "\n"
    return stream.bytes.asString!
}

extension Build.Configuration: StringEnumArgument {
    public static var completion: ShellCompletion = .values([
        (debug.rawValue, "build with DEBUG configuration"),
        (release.rawValue, "build with RELEASE configuration"),
    ])
}
