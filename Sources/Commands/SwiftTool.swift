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

private class ToolWorkspaceDelegate: WorkspaceDelegate {
    func fetchingMissingRepositories(_ urls: Set<String>) {
    }

    func fetching(repository: String) {
        print("Fetching \(repository)")
    }

    func cloning(repository: String) {
        print("Cloning \(repository)")
    }

    func checkingOut(repository: String, at reference: String) {
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
}

public class SwiftTool<Options: ToolOptions> {
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

    /// Create an instance of this tool.
    ///
    /// - parameter args: The command line arguments to be passed to this tool.
    public init(toolName: String, usage: String, overview: String, args: [String]) {

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
                option: "-Xcc", kind: [String].self,
                usage: "Pass flag through to all C compiler invocations"),
            parser.add(
                option: "-Xswiftc", kind: [String].self,
                usage: "Pass flag through to all Swift compiler invocations"),
            parser.add(
                option: "-Xlinker", kind: [String].self,
                usage: "Pass flag through to all linker invocations"),
            to: { $0.buildFlags = BuildFlags(xcc: $1, xswiftc: $2, xlinker: $3) })

        binder.bind(
            option: parser.add(
                option: "--build-path", kind: PathArgument.self,
                usage: "Specify build/cache directory [default: ./.build]"),
            to: { $0.buildPath = $1.path })

        binder.bind(
            option: parser.add(
                option: "--chdir", shortName: "-C", kind: PathArgument.self,
                usage: "Change working directory before any other operation"),
            to: { $0.chdir = $1.path })

        binder.bind(
            option: parser.add(option: "--enable-prefetching", kind: Bool.self,
            usage: "Enable prefetching in resolver"),
            to: { $0.shouldEnableResolverPrefetching = $1 })

        binder.bind(
            option: parser.add(option: "--disable-manifest-sandbox", kind: Bool.self,
            usage: "Disable using the sandbox when parsing manifests on macOS"),
            to: { $0.shouldDisableManifestSandbox = $1 })

        binder.bind(
            option: parser.add(option: "--version", kind: Bool.self),
            to: { $0.shouldPrintVersion = $1 })

        // If manifest should be assumed to be PackageDescription4.
        // This is temporary and will go away when the compiler bumps its major version to 4.
        binder.bind(
            option: parser.add(option: "--experimental-use-v4-manifest", kind: Bool.self),
            to: { _, on in Versioning.simulateVersionFour = on })

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
            // Honor chdir option is provided.
            if let dir = options.chdir {
                // FIXME: This should be an API which takes AbsolutePath and maybe
                // should be moved to file system APIs with currentWorkingDirectory.
                try POSIX.chdir(dir.asString)
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
        }

        // Create local variables to use while finding build path to avoid capture self before init error.
        let customBuildPath = options.buildPath
        let packageRoot = findPackageRoot()

        self.packageRoot = packageRoot
        self.buildPath = getEnvBuildPath() ??
            customBuildPath ??
            (packageRoot ?? currentWorkingDirectory).appending(component: ".build")
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
            pinsFile: rootPackage.appending(component: "Package.pins"),
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
            // Call the implementation.
            try runImpl()
            guard !diagnostics.hasErrors else {
                throw Error.hasFatalDiagnostics
            }
        } catch {
            printDiagnostics()
            handle(error: error)
        }
    }

    private func printDiagnostics() {
        for diag in diagnostics.diagnostics {
            print(error: diag.localizedDescription)
        }
    }

    /// Run method implmentation to be overridden by subclasses.
    func runImpl() throws {
        fatalError("Must be implmented by subclasses")
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

    /// Returns the user toolchain.
    func getToolchain() throws -> UserToolchain {
        return try _toolchain.dematerialize()
    }

    func getManifestLoader() throws -> ManifestLoader {
        return try _manifestLoader.dematerialize()
    }

    /// Build the package graph using swift-build-tool.
    func build(graph: PackageGraph, includingTests: Bool, config: Build.Configuration) throws {
        // Create build parameters.
        let buildParameters = BuildParameters(
            dataPath: buildPath,
            configuration: config,
            toolchain: try getToolchain(),
            flags: options.buildFlags
        )
        let yaml = buildPath.appending(component: config.dirname + ".yaml")
        // Create build plan.
        let buildPlan = try BuildPlan(buildParameters: buildParameters, graph: graph, delegate: self)
        // Generate llbuild manifest.
        let llbuild = LLbuildManifestGenerator(buildPlan)
        try llbuild.generateManifest(at: yaml)
        assert(isFile(yaml), "llbuild manifest not present: \(yaml.asString)")
        // Run the swift-build-tool with the generated manifest.
        try Commands.build(
            yamlPath: yaml,
            llbuild: getToolchain().llbuild,
            target: includingTests ? "test" : nil,
            processSet: processSet)
    }

    /// Lazily compute the toolchain.
    private lazy var _toolchain: Result<UserToolchain, AnyError> = {

      #if Xcode
        // For Xcode, set bin directory to the build directory containing the fake
        // toolchain created during bootstraping. This is obviously not production ready
        // and only exists as a development utility right now.
        //
        // This also means that we should have bootstrapped with the same Swift toolchain
        // we're using inside Xcode otherwise we will not be able to load the runtime libraries.
        //
        // FIXME: We may want to allow overriding this using an env variable but that
        // doesn't seem urgent or extremely useful as of now.
        let binDir = AbsolutePath(#file).parentDirectory
            .parentDirectory.parentDirectory.appending(components: ".build", "debug")
      #else
        let binDir = AbsolutePath(
            CommandLine.arguments[0], relativeTo: currentWorkingDirectory).parentDirectory
      #endif

        return Result(anyError: { try UserToolchain(binDir) })
    }()

    private lazy var _manifestLoader: Result<ManifestLoader, AnyError> = {
        return Result(anyError: {
            try ManifestLoader(
                resources: self.getToolchain(),
                isManifestSandboxEnabled: !self.options.shouldDisableManifestSandbox
            )
        })
    }()
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
