/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Build
import PackageModel
import SourceControl
import Utility
import Xcodeproj

/// Errors encountered duing the package tool operations.
enum PackageToolOperationError: Swift.Error {
    /// The provided package name doesn't exist in package graph.
    case packageNotFound

    /// The current mode does not have all the options it requires.
    case insufficientOptions(usage: String)

    /// The package is in editable state.
    case packageInEditableState
}

/// swift-build tool namespace
public class SwiftPackageTool: SwiftTool<PackageToolOptions> {

   public convenience init(args: [String]) {
       self.init(
            toolName: "package",
            usage: "[options] subcommand",
            overview: "Perform operations on Swift packages",
            args: args
        )
    }
    override func runImpl() throws {
        switch options.mode {
        case .version:
            print(Versioning.currentVersion.completeDisplayString)

        case .initPackage:
            let initPackage = try InitPackage(mode: options.initMode)
            try initPackage.writePackageStructure()

        case .clean:
            try clean()

        case .reset:
            try getActiveWorkspace().reset()

        case .resolve:
            // NOTE: This command is currently undocumented, and is for
            // bringup of the new dependency resolution logic. This is *NOT*
            // the code currently used to resolve dependencies (which runs
            // off of the infrastructure in the `Get` module).
            try executeResolve(options)
            break

        case .update:
            let workspace = try getActiveWorkspace()
            // We repin either on explicit repin option or if autopin is enabled.
            let repin = options.repin || workspace.pinsStore.autoPin
            try workspace.updateDependencies(repin: repin)
        case .fetch:
            _ = try loadPackage()

        case .edit:
            // Make sure we have all the options required for editing the package.
            guard let packageName = options.editOptions.packageName, (options.editOptions.revision != nil || options.editOptions.checkoutBranch != nil) else {
                throw PackageToolOperationError.insufficientOptions(usage: editUsage)
            }
            // Get the current workspace.
            let workspace = try getActiveWorkspace()
            try workspace.loadPackageGraph()
            let manifests = try workspace.loadDependencyManifests()
            // Look for the package's manifest.
            guard let (manifest, dependency) = manifests.lookup(package: packageName) else {
                throw PackageToolOperationError.packageNotFound
            }
            // Create revision object if provided by user.
            let revision = options.editOptions.revision.flatMap { Revision(identifier: $0) }
            // Put the dependency in edit mode.
            try workspace.edit(dependency: dependency, at: revision, packageName: manifest.name, checkoutBranch: options.editOptions.checkoutBranch)

        case .unedit:
            guard let packageName = options.editOptions.packageName else {
                throw PackageToolOperationError.insufficientOptions(usage: uneditUsage)
            }
            let workspace = try getActiveWorkspace()
            let manifests = try workspace.loadDependencyManifests()
            // Look for the package's manifest.
            guard let editedDependency = manifests.lookup(package: packageName)?.dependency else {
                throw PackageToolOperationError.packageNotFound
            }
            try workspace.unedit(dependency: editedDependency, forceRemove: options.editOptions.forceRemove)

        case .showDependencies:
            let graph = try loadPackage()
            dumpDependenciesOf(rootPackage: graph.rootPackages[0], mode: options.showDepsMode)
        case .generateXcodeproj:
            let graph = try loadPackage()

            let projectName: String
            let dstdir: AbsolutePath

            switch options.outputPath {
            case let outpath? where outpath.suffix == ".xcodeproj":
                // if user specified path ending with .xcodeproj, use that
                projectName = String(outpath.basename.characters.dropLast(10))
                dstdir = outpath.parentDirectory
            case let outpath?:
                dstdir = outpath
                projectName = graph.rootPackages[0].name
            case _:
                dstdir = try getPackageRoot()
                projectName = graph.rootPackages[0].name
            }
            let outpath = try Xcodeproj.generate(outputDir: dstdir, projectName: projectName, graph: graph, options: options.xcodeprojOptions)

            print("generated:", outpath.prettyPath)

        case .describe:
            let graph = try loadPackage()
            describe(graph.rootPackages[0].underlyingPackage, in: options.describeMode, on: stdoutStream)

        case .dumpPackage:
            let manifest = try loadRootManifest(options)
            print(try manifest.jsonString())
        case .help:
            parser.printUsage(on: stdoutStream)
        case .pin:
            // FIXME: It would be nice to have mutual exclusion pinning options.
            // Argument parser needs to provide that functionality.

            // Toggle enable auto pinning if requested.
            if let enableAutoPin = options.pinOptions.enableAutoPin {
                let workspace = try getActiveWorkspace()
                return try workspace.pinsStore.setAutoPin(on: enableAutoPin)
            }
            // Pin all dependencies if requested.
            if options.pinOptions.pinAll {
                let workspace = try getActiveWorkspace()
                return try workspace.pinAll()
            }
            // Ensure we have the package name at this point.
            guard let packageName = options.pinOptions.packageName else {
                throw PackageToolOperationError.insufficientOptions(usage: pinUsage)
            }
            let workspace = try getActiveWorkspace()
            // Load the package graph.
            _ = try workspace.loadPackageGraph()
            // Load the dependencies.
            let manifests = try workspace.loadDependencyManifests()
            // Lookup the dependency to pin.
            guard let (_, dependency) = manifests.lookup(package: packageName) else {
                throw PackageToolOperationError.packageNotFound
            }
            // We can't pin something which is in editable mode.
            guard !dependency.isInEditableState else {
                throw PackageToolOperationError.packageInEditableState
            }
            // Pin the dependency.
            try workspace.pin(
                dependency: dependency,
                packageName: packageName,
                at: try options.pinOptions.version.flatMap(Version.init(string:)) ?? dependency.currentVersion!,
                reason: options.pinOptions.message
            )
        case .unpin:
            guard let packageName = options.pinOptions.packageName else {
                fatalError("Expected package name from parser")
            }
            let workspace = try getActiveWorkspace()
            try workspace.pinsStore.unpin(package: packageName)
        }
    }

    /// Load the manifest for the root package
    func loadRootManifest(_ options: PackageToolOptions) throws -> Manifest {
        let root = try options.inputPath ?? getPackageRoot()
        return try manifestLoader.loadFile(path: root, baseURL: root.asString, version: nil)
    }
    
    var editUsage: String {
        let stream = BufferedOutputByteStream()
        stream <<< "Expected package edit format:\n"
        stream <<< "swift package edit <packageName> (--revision <revision> | --branch <newBranch>)\n"
        stream <<< "Note: Either revision or branch name is required."
        return stream.bytes.asString!
    }

    var uneditUsage: String {
        let stream = BufferedOutputByteStream()
        stream <<< "Expected package unedit format:\n"
        stream <<< "swift package unedit --name <packageName> [--force]"
        return stream.bytes.asString!
    }
    
    var pinUsage: String {
        let stream = BufferedOutputByteStream()
        stream <<< "Expected package pin format:\n"
        stream <<< "swift package pin (--all | <packageName> [--version <version>])\n"
        stream <<< "Note: Either provide a package to pin or provide pin all option to pin all dependencies."
        return stream.bytes.asString!
    }

    override class func defineArguments(parser: ArgumentParser, binder: ArgumentBinder<PackageToolOptions>) {
        binder.bind(
            option: parser.add(option: "--version", kind: Bool.self),
            to: { options, _ in options.mode = .version })

        let describeParser = parser.add(subparser: PackageMode.describe.rawValue, overview: "Describe the current package")
        binder.bind(
            option: describeParser.add(option: "--type", kind: DescribeMode.self, usage: "json|text"),
            to: { $0.describeMode = $1 })

        _ = parser.add(subparser: PackageMode.dumpPackage.rawValue, overview: "Print parsed Package.swift as JSON")

        let editParser = parser.add(subparser: PackageMode.edit.rawValue, overview: "Put a package in editable mode (either --revision or --branch option is required)")
        binder.bind(
            positional: editParser.add(
                positional: "name", kind: String.self,
                usage: "The name of the package to edit"),
            to: { $0.editOptions.packageName = $1 })
        binder.bind(
            editParser.add(
                option: "--revision", kind: String.self,
                usage: "The revision to edit"),
            editParser.add(
                option: "--branch", kind: String.self,
                usage: "The branch to create"),
            to: { 
                $0.editOptions.revision = $1 
                $0.editOptions.checkoutBranch = $2})

        parser.add(subparser: PackageMode.clean.rawValue, overview: "Delete build artifacts")
        parser.add(subparser: PackageMode.fetch.rawValue, overview: "Fetch package dependencies")
        parser.add(subparser: PackageMode.reset.rawValue, overview: "Reset the complete cache/build directory")

        let resolveParser = parser.add(subparser: PackageMode.resolve.rawValue, overview: "")
        binder.bind(
            option: resolveParser.add(
                option: "--type", kind: PackageToolOptions.ResolveToolMode.self,
                usage: "text|json"),
            to: { $0.resolveToolMode = $1 })

        let updateParser = parser.add(subparser: PackageMode.update.rawValue, overview: "Update package dependencies")
        binder.bind(
            option: updateParser.add(
                option: "--repin", kind: Bool.self,
                usage: "Update without applying pins and repin the updated versions"),
            to: { $0.repin = $1 })

        let initPackageParser = parser.add(subparser: PackageMode.initPackage.rawValue, overview: "Initialize a new package")
        binder.bind(
            option: initPackageParser.add(
                option: "--type", kind: InitMode.self,
                usage: "empty|library|executable|system-module"),
            to: { $0.initMode = $1 })

        let uneditParser = parser.add(subparser: PackageMode.unedit.rawValue, overview: "Remove a package from editable mode")
        binder.bind(
            positional: uneditParser.add(
                positional: "name", kind: String.self,
                usage: "The name of the package to unedit"),
            to: { $0.editOptions.packageName = $1 })
        binder.bind(
            option: uneditParser.add(
                option: "--force", kind: Bool.self,
                usage: "Unedit the package even if it has uncommited and unpushed changes."),
            to: { $0.editOptions.forceRemove = $1 })
        
        let showDependenciesParser = parser.add(subparser: PackageMode.showDependencies.rawValue, overview: "Print the resolved dependency graph")
        binder.bind(
            option: showDependenciesParser.add(
                option: "--format", kind: ShowDependenciesMode.self, 
                usage: "text|dot|json"),
            to: { 
                $0.showDepsMode = $1})

        let generateXcodeParser = parser.add(subparser: PackageMode.generateXcodeproj.rawValue, overview: "Generates an Xcode project")
        binder.bind(
            generateXcodeParser.add(
                option: "--xcconfig-overrides", kind: String.self,
                usage: "Path to xcconfig file"),
            generateXcodeParser.add(
                option: "--enable-code-coverage", kind: Bool.self,
                usage: "Enable code coverage in the generated project"),
            generateXcodeParser.add(
                option: "--output", kind: String.self,
                usage: "Path where the Xcode project should be generated"),
            to: { 
                $0.xcodeprojOptions = XcodeprojOptions(flags: $0.buildFlags, xcconfigOverrides: $0.absolutePathRelativeToWorkingDir($1), enableCodeCoverage: $2)
                $0.outputPath = $0.absolutePathRelativeToWorkingDir($3) })

        let pinParser = parser.add(subparser: PackageMode.pin.rawValue, overview: "Perform pinning operations on a package.")
        binder.bind(
            positional: pinParser.add(
                positional: "name", kind: String.self, optional: true,
                usage: "The name of the package to pin"),
            to: { $0.pinOptions.packageName = $1 })
        binder.bind(
            option: pinParser.add(
                option: "--enable-autopin", kind: Bool.self,
                usage: "Enable automatic pinning"),
            to: { $0.pinOptions.enableAutoPin = $1 })
        binder.bind(
            option: pinParser.add(
                option: "--disable-autopin", kind: Bool.self,
                usage: "Disable automatic pinning"),
            to: { $0.pinOptions.enableAutoPin = !$1 })

        binder.bind(
            pinParser.add(
                option: "--all", kind: Bool.self,
                usage: "Pin all dependencies"),
            pinParser.add(
                option: "--message", kind: String.self,
                usage: "The reason for pinning"),
            pinParser.add(
                option: "--version", kind: String.self,
                usage: "The version to pin at"),
            to: {
                $0.pinOptions.pinAll = $1 ?? false
                $0.pinOptions.message = $2
                $0.pinOptions.version = $3 })

        let unpinParser = parser.add(subparser: PackageMode.unpin.rawValue, overview: "Unpin a package. Note: This can only be used when auto-pinning is disabled.")
        binder.bind(
            positional: unpinParser.add(
                positional: "name", kind: String.self,
                usage: "The name of the package to unpin"),
            to: { $0.pinOptions.packageName = $1 })

        binder.bind(
            parser: parser,
            to: { $0.mode = PackageMode(rawValue: $1)! })
    }
}

public class PackageToolOptions: ToolOptions {
    var mode: PackageMode = .help

    var describeMode: DescribeMode = .text
    var initMode: InitMode = .library

    var inputPath: AbsolutePath?
    var showDepsMode: ShowDependenciesMode = .text

    struct EditOptions {
        var packageName: String?
        var revision: String?
        var checkoutBranch: String?
        var forceRemove = false
    }

    var editOptions = EditOptions()

    var outputPath: AbsolutePath?
    var xcodeprojOptions = XcodeprojOptions()

    struct PinOptions {
        var enableAutoPin: Bool?
        var pinAll = false
        var message: String?
        var packageName: String?
        var version: String?
    }
    var pinOptions = PinOptions()

    /// Repin the dependencies when running package update.
    var repin = false

    enum ResolveToolMode: String, StringEnumArgument {
        case text
        case json
    }
    var resolveToolMode: ResolveToolMode = .text
}

public enum PackageMode: String, StringEnumArgument {
    case clean
    case describe
    case dumpPackage = "dump-package"
    case edit
    case fetch
    case generateXcodeproj = "generate-xcodeproj"
    case initPackage = "init"
    case pin
    case reset
    case resolve
    case showDependencies = "show-dependencies"
    case unedit
    case unpin
    case update
    case version
    case help
}

extension InitMode: StringEnumArgument {}
extension ShowDependenciesMode: StringEnumArgument {}
extension DescribeMode: StringEnumArgument {}
