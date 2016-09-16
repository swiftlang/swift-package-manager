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

public class SwiftTool<Mode: Argument, OptionType: Options> {
    /// The command line arguments this tool should honor.
    let args: [String]

    /// The mode in which this tool is currently executing.
    let mode: Mode

    /// The options of this tool.
    let options: OptionType

    /// The package graph loader.
    let manifestLoader = ManifestLoader(resources: ToolDefaults())

    public init() {
        let args = Array(CommandLine.arguments.dropFirst())
        self.args = Array(CommandLine.arguments.dropFirst())
        let dynamicSelf = type(of: self)
        do {
            (self.mode, self.options) = try dynamicSelf.parse(commandLineArguments: args)
        } catch {
            handle(error: error, usage: dynamicSelf.usage)
        }
    }

    class func parse(commandLineArguments args: [String]) throws -> (Mode, OptionType) {
        fatalError("Must be implmented by subclasses")
    }

    /// Execute the tool.
    public func run() {
        runImpl()
    }

    /// Run method implmentation to be overridden by subclasses.
    func runImpl() {
        fatalError("Must be implmented by subclasses")
    }

    /// Method to be called to print the usage text of this tool.
    class func usage(_ print: (String) -> Void = { print($0) }) {
        fatalError("Must be implmented by subclasses")
    }

    /// Fetch and load the complete package at the given path.
    func loadPackage(at path: AbsolutePath, _ opts: Options) throws -> PackageGraph {
        if opts.enableNewResolver {
            // Get the active workspace.
            let delegate = ToolWorkspaceDelegate()
            let workspace = try Workspace(rootPackage: path, dataPath: opts.path.build, manifestLoader: manifestLoader, delegate: delegate)

            // Fetch and load the package graph.
            let graph = try workspace.loadPackageGraph()

            // Create the legacy `Packages` subdirectory.
            try workspace.createPackagesDirectory(graph)

            return graph
        } else {
            // Create the packages directory container.
            let packagesDirectory = PackagesDirectory(root: path, manifestLoader: manifestLoader)

            // Fetch and load the manifests.
            let (rootManifest, externalManifests) = try packagesDirectory.loadManifests()
        
            return try PackageGraphLoader().load(rootManifest: rootManifest, externalManifests: externalManifests)
        }
    }
}
