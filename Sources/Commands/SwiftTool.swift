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
    }

    func cloning(repository: String) {
    }

    func checkingOut(repository: String, at reference: String) {
    }
}

enum SwiftToolError: Swift.Error {
    case rootManifestFileNotFound
}

public class SwiftTool<Mode: Argument, OptionType: Options> {
    /// The command line arguments this tool should honor.
    let args: [String]

    /// The mode in which this tool is currently executing.
    let mode: Mode

    /// The options of this tool.
    let options: OptionType

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

    public init() {
        let args = Array(CommandLine.arguments.dropFirst())
        self.args = args
        let dynamicSelf = type(of: self)
        do {
            (self.mode, self.options) = try dynamicSelf.parse(commandLineArguments: args)
            // Honor chdir option is provided.
            if let dir = options.chdir {
                try chdir(dir.asString)
            }
        } catch {
            handle(error: error, usage: dynamicSelf.usage)
        }

        // Create local variables to use while finding build path to avoid capture self before init error.
        let customBuildPath = options.buildPath
        let packageRoot = findPackageRoot()

        self.packageRoot = packageRoot
        self.buildPath = getEnvBuildPath() ?? customBuildPath ?? (packageRoot ?? currentWorkingDirectory).appending(component: ".build")
    }

    class func parse(commandLineArguments args: [String]) throws -> (Mode, OptionType) {
        fatalError("Must be implmented by subclasses")
    }

    /// Returns the currently active workspace.
    func getActiveWorkspace() throws -> Workspace {
        // Get the active workspace.
        let delegate = ToolWorkspaceDelegate()
        return try Workspace(rootPackage: try getPackageRoot(), dataPath: buildPath, manifestLoader: manifestLoader, delegate: delegate)
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
            handle(error: error, usage: type(of: self).usage)
        }
    }

    /// Run method implmentation to be overridden by subclasses.
    func runImpl() throws {
        fatalError("Must be implmented by subclasses")
    }

    /// Method to be called to print the usage text of this tool.
    class func usage(_ print: (String) -> Void = { print($0) }) {
        fatalError("Must be implmented by subclasses")
    }

    /// Fetch and load the complete package at the given path.
    func loadPackage() throws -> PackageGraph {
        if options.enableNewResolver {
            let workspace = try getActiveWorkspace()

            // Fetch and load the package graph.
            let graph = try workspace.loadPackageGraph()

            // Create the legacy `Packages` subdirectory.
            try workspace.createPackagesDirectory(graph)

            return graph
        } else {
            // Create the packages directory container.
            let packagesDirectory = PackagesDirectory(root: try getPackageRoot(), manifestLoader: manifestLoader)

            // Fetch and load the manifests.
            let (rootManifest, externalManifests) = try packagesDirectory.loadManifests()
        
            return try PackageGraphLoader().load(rootManifest: rootManifest, externalManifests: externalManifests)
        }
    }
}

/// Returns path of the nearest directory containing the manifest file w.r.t
/// current working directory.
private func findPackageRoot() -> AbsolutePath? {
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
    guard let env = getenv("SWIFT_BUILD_PATH") else { return nil }
    return AbsolutePath(env, relativeTo: currentWorkingDirectory)
}
