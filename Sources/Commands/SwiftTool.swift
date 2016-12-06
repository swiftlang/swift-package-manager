/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import Get
import PackageLoading
import PackageGraph
import PackageModel
import POSIX
import Utility

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

    let parser: ArgumentParser

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
            option: parser.add(option: "--enable-new-resolver", kind: Bool.self),
            to: { $0.enableNewResolver = $1 })

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
                try chdir(dir.asString)
            }
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
        _workspace = try Workspace(rootPackage: try getPackageRoot(), dataPath: buildPath, manifestLoader: manifestLoader, delegate: delegate)
        return _workspace!
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
        if options.enableNewResolver {
            let workspace = try getActiveWorkspace()
            // Fetch and load the package graph.
            return try workspace.loadPackageGraph()
        } else {
            // Create the packages directory container.
            let packagesDirectory = PackagesDirectory(root: try getPackageRoot(), manifestLoader: manifestLoader)

            // Fetch and load the manifests.
            let (rootManifest, externalManifests) = try packagesDirectory.loadManifests()
        
            return try PackageGraphLoader().load(rootManifest: rootManifest, externalManifests: externalManifests)
        }
    }

    /// Cleans the build artefacts.
    // FIXME: Move this to swift-package once its not needed in swift-build.
    func clean() throws {
        if options.enableNewResolver {
            try getActiveWorkspace().clean()
        } else {
            // FIXME: This test is lame, `removeFileTree` shouldn't error on this.
            if exists(buildPath) {
                try removeFileTree(buildPath)
            }
        }
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
    guard getenv("IS_SWIFTPM_TEST") == nil else { return nil }
    guard let env = getenv("SWIFT_BUILD_PATH") else { return nil }
    return AbsolutePath(env, relativeTo: currentWorkingDirectory)
}
