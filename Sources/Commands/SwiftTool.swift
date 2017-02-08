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

enum SwiftToolError: Swift.Error {
    case rootManifestFileNotFound
}

public class SwiftTool<Options: ToolOptions> {
    /// The options of this tool.
    let options: Options

    /// The package graph loader.
    let manifestLoader = ManifestLoader(resources: ToolDefaults())

    /// Path to the root package directory, nil if manifest is not found.
    let packageRoot: AbsolutePath?

    /// Helper function to get package root or throw error if it is not found.
    func getPackageRoot() throws -> AbsolutePath {
        guard let packageRoot = packageRoot else {
            throw SwiftToolError.rootManifestFileNotFound
        }
        return packageRoot
    }

    /// Path to directory of the checkouts.
    func getCheckoutsDirectory() throws -> AbsolutePath {
        return try getPackageRoot().appending(component: "Packages")
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
                option: "--build-path", kind: String.self, 
                usage: "Specify build/cache directory [default: ./.build]"),
            to: { $0.buildPath = $0.absolutePathRelativeToWorkingDir($1) })

        binder.bind(
            option: parser.add(
                option: "--chdir", shortName: "-C", kind: String.self,
                usage: "Change working directory before any other operation"),
            to: { $0.chdir = $0.absolutePathRelativeToWorkingDir($1) })

        binder.bind(
            option: parser.add(option: "--color", kind: ColorWrap.Mode.self,
                usage: "Specify color mode (auto|always|never) [default: auto]"),
            to: { $0.colorMode = $1 })

        binder.bind(
            option: parser.add(option: "--enable-prefetching", kind: Bool.self, 
            usage: "Enable prefetching in resolver"),
            to: { $0.enableResolverPrefetching = $1 })

        binder.bind(
            option: parser.add(option: "--version", kind: Bool.self),
            to: { $0.printVersion = $1 })

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
                action.__sigaction_handler = unsafeBitCast(SIG_DFL, to: sigaction.__Unnamed_union___sigaction_handler.self)
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
        self.buildPath = getEnvBuildPath() ?? customBuildPath ?? (packageRoot ?? currentWorkingDirectory).appending(component: ".build")
    }

    class func defineArguments(parser: ArgumentParser, binder: ArgumentBinder<Options>) {
        fatalError("Must be implmented by subclasses")
    }

    /// Holds the currently active workspace.
    ///
    /// It is not initialized in init() because for some of the commands like package init , usage etc,
    /// workspace is not needed, infact it would be an error to ask for the workspace object
    /// for package init because the Manifest file should *not* present.
    private var _workspace: Workspace? = nil

    /// Returns the currently active workspace.
    func getActiveWorkspace() throws -> Workspace {
        if let workspace = _workspace {
            return workspace
        }
        let delegate = ToolWorkspaceDelegate()
        let rootPackage = try getPackageRoot()
        let provider = GitRepositoryProvider(processSet: processSet)
        let workspace = try Workspace(
            dataPath: buildPath,
            editablesPath: rootPackage.appending(component: "Packages"),
            pinsFile: rootPackage.appending(component: "Package.pins"),
            manifestLoader: manifestLoader,
            delegate: delegate,
            repositoryProvider: provider,
            enableResolverPrefetching: options.enableResolverPrefetching
        )
        workspace.registerPackage(at: rootPackage)
        _workspace = workspace
        return workspace
    }

    /// Execute the tool.
    public func run() {
        do {
            // Setup the globals.
            verbosity = Verbosity(rawValue: options.verbosity)
            colorMode = options.colorMode
            // Call the implementation.
            try runImpl()
        } catch {
            handle(error: error)
        }
    }

    /// Run method implmentation to be overridden by subclasses.
    func runImpl() throws {
        fatalError("Must be implmented by subclasses")
    }

    /// Fetch and load the complete package at the given path.
    func loadPackage() throws -> PackageGraph {
        let workspace = try getActiveWorkspace()
        // Fetch and load the package graph.
        return try workspace.loadPackageGraph()
    }

    /// Build the package graph using swift-build-tool.
    func build(graph: PackageGraph, includingTests: Bool, config: Build.Configuration) throws {
        // Create build parameters.
        let buildParameters = BuildParameters(
            dataPath: buildPath,
            configuration: config,
            toolchain: try UserToolchain(),
            flags: options.buildFlags
        )
        let yaml = buildPath.appending(component: config.dirname + ".yaml")
        // Create build plan.
        let buildPlan = try BuildPlan(buildParameters: buildParameters, graph: graph, delegate: self)
        // Generate llbuild manifest.
        let llbuild = LLbuildManifestGenerator(buildPlan)
        try llbuild.generateManifest(at: yaml)
        // Run the swift-build-tool with the generated manifest.
        try Commands.build(yamlPath: yaml, target: includingTests ? "test" : nil)
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
