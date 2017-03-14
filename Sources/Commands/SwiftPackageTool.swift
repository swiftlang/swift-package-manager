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
import PackageLoading
import PackageGraph
import SourceControl
import Utility
import Xcodeproj
import Workspace

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
            let initPackage = try InitPackage(destinationPath: currentWorkingDirectory, packageType: options.initMode)
            initPackage.progressReporter = { message in
                print(message)
            }
            try initPackage.writePackageStructure()

        case .clean:
            try getActiveWorkspace().clean()

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
            let rootPackages = try [getPackageRoot()]
            let workspace = try getActiveWorkspace()
            let pinsStore = try workspace.pinsStore.load()
            // We repin either on explicit repin option or if autopin is enabled.
            let repin = options.repin || pinsStore.autoPin
            workspace.updateDependencies(
                rootPackages: rootPackages,
                engine: engine,
                repin: repin
            )

        case .fetch:
            try loadPackageGraph()

        case .edit:
            let packageName = options.editOptions.packageName!
            // Load the package graph.
            try loadPackageGraph()

            // Get the current workspace.
            let workspace = try getActiveWorkspace()
            let rootManifests = workspace.loadRootManifests(
                packages: [try getPackageRoot()], engine: engine)
            let manifests = workspace.loadDependencyManifests(
                rootManifests: rootManifests, engine: engine)
            guard !engine.hasErrors() else { return }
            // Look for the package's manifest.
            guard let (manifest, dependency) = manifests.lookup(package: packageName) else {
                throw PackageToolOperationError.packageNotFound
            }
            // Create revision object if provided by user.
            let revision = options.editOptions.revision.flatMap { Revision(identifier: $0) }
            // Put the dependency in edit mode.
            try workspace.edit(
                dependency: dependency,
                packageName: manifest.name,
                path: options.editOptions.path,
                revision: revision,
                checkoutBranch: options.editOptions.checkoutBranch
            )

        case .unedit:
            let packageName = options.editOptions.packageName!

            // Load the package graph.
            try loadPackageGraph()

            let workspace = try getActiveWorkspace()
            let rootManifests = workspace.loadRootManifests(
                packages: [try getPackageRoot()], engine: engine)
            let manifests = workspace.loadDependencyManifests(
                rootManifests: rootManifests, engine: engine)
            guard !engine.hasErrors() else { return }
            // Look for the package's manifest.
            guard let editedDependency = manifests.lookup(package: packageName)?.dependency else {
                throw PackageToolOperationError.packageNotFound
            }
            try workspace.unedit(dependency: editedDependency, forceRemove: options.editOptions.forceRemove)

        case .showDependencies:
            let graph = try loadPackageGraph()
            dumpDependenciesOf(rootPackage: graph.rootPackages[0], mode: options.showDepsMode)

        case .toolsVersion:
            let pkg = try getPackageRoot()

            switch options.toolsVersionMode {
            case .display:
                let toolsVersionLoader = ToolsVersionLoader()
                let version = try toolsVersionLoader.load(at: pkg, fileSystem: localFileSystem)
                print("\(version)")

            case .set(let value):
                guard let toolsVersion = ToolsVersion(string: value) else {
                    // FIXME: Probably lift this error defination to ToolsVersion.
                    throw ToolsVersionLoader.Error.malformed(specifier: value, file: pkg)
                }
                try writeToolsVersion(at: pkg, version: toolsVersion, fs: &localFileSystem)

            case .setCurrent:
                // Write the tools version with current version but with patch set to zero.
                // We do this to avoid adding unnecessary constraints to patch versions, if
                // the package really needs it, they can do it using --set option.
                try writeToolsVersion(
                    at: pkg, version: ToolsVersion.currentToolsVersion.zeroedPatch, fs: &localFileSystem)
            }

        case .generateXcodeproj:
            let graph = try loadPackageGraph()

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
            let graph = try loadPackageGraph()
            describe(graph.rootPackages[0].underlyingPackage, in: options.describeMode, on: stdoutStream)

        case .dumpPackage:
            let graph = try loadPackageGraph()
            let manifest = graph.rootPackages[0].manifest
            print(try manifest.jsonString())

        case .help:
            parser.printUsage(on: stdoutStream)

        case .pin:
            // FIXME: It would be nice to have mutual exclusion pinning options.
            // Argument parser needs to provide that functionality.

            // Toggle enable auto pinning if requested.
            if let enableAutoPin = options.pinOptions.enableAutoPin {
                let workspace = try getActiveWorkspace()
                return try workspace.pinsStore.load().setAutoPin(on: enableAutoPin)
            }

            // Get the pin options.
            // FIXME: We should validate these options here and throw or warn appropriately.
            let pinOptions = options.pinOptions

            // Load the package graph.
            try loadPackageGraph()

            let workspace = try getActiveWorkspace()
            // Load the dependencies.
            let rootManifests = workspace.loadRootManifests(
                packages: [try getPackageRoot()], engine: engine)
            let manifests = workspace.loadDependencyManifests(
                rootManifests: rootManifests, engine: engine)
            guard !engine.hasErrors() else { return }

            // Pin all dependencies if requested.
            if pinOptions.pinAll {
                let pinsStore = try workspace.pinsStore.load()
                return try workspace.pinAll(
                    pinsStore: pinsStore,
                    dependencyManifests: manifests)
            }
            // Ensure we have the package name at this point.
            guard let packageName = pinOptions.packageName else {
                throw PackageToolOperationError.insufficientOptions(usage: pinUsage)
            }
            // Lookup the dependency to pin.
            guard let (_, dependency) = manifests.lookup(package: packageName) else {
                throw PackageToolOperationError.packageNotFound
            }
            // We can't pin something which is in editable mode.
            guard case .checkout = dependency.state else {
                throw PackageToolOperationError.packageInEditableState
            }

            // Pin the dependency.
            try workspace.pin(
                dependency: dependency,
                packageName: packageName,
                rootPackages: [getPackageRoot()],
                engine: engine,
                version: pinOptions.version.flatMap(Version.init(string:)),
                branch: pinOptions.branch,
                revision: pinOptions.revision,
                reason: options.pinOptions.message
            )

        case .unpin:
            guard let packageName = options.pinOptions.packageName else {
                fatalError("Expected package name from parser")
            }
            let workspace = try getActiveWorkspace()
            try workspace.pinsStore.load().unpin(package: packageName)
        }
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

        let editParser = parser.add(subparser: PackageMode.edit.rawValue, overview: "Put a package in editable mode")
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

        binder.bind(
            option: editParser.add(
                option: "--path", kind: PathArgument.self,
                usage: "Create or use the checkout at this path"),
            to: { $0.editOptions.path = $1.path })

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
                option: "--type", kind: InitPackage.PackageType.self,
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

        let toolsVersionParser = parser.add(subparser: PackageMode.toolsVersion.rawValue, overview: "Manipulate tools version of the current package")
        binder.bind(
            option: toolsVersionParser.add(
                option: "--set", kind: String.self,
                usage: "Set tools version of package to the given value"),
            to: { $0.toolsVersionMode = .set($1) })

        binder.bind(
            option: toolsVersionParser.add(
                option: "--set-current", kind: Bool.self,
                usage: "Set tools version of package to the current tools version in use"),
            to: { if $1 { $0.toolsVersionMode = .setCurrent } })

        let generateXcodeParser = parser.add(subparser: PackageMode.generateXcodeproj.rawValue, overview: "Generates an Xcode project")
        binder.bind(
            generateXcodeParser.add(
                option: "--xcconfig-overrides", kind: PathArgument.self,
                usage: "Path to xcconfig file"),
            generateXcodeParser.add(
                option: "--enable-code-coverage", kind: Bool.self,
                usage: "Enable code coverage in the generated project"),
            generateXcodeParser.add(
                option: "--output", kind: PathArgument.self,
                usage: "Path where the Xcode project should be generated"),
            to: { 
                $0.xcodeprojOptions = XcodeprojOptions(flags: $0.buildFlags, xcconfigOverrides: $1?.path, enableCodeCoverage: $2)
                $0.outputPath = $3?.path })

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
            to: {
                $0.pinOptions.pinAll = $1 ?? false
                $0.pinOptions.message = $2 })

        binder.bind(
            pinParser.add(
                option: "--version", kind: String.self,
                usage: "The version to pin at"),
            pinParser.add(
                option: "--branch", kind: String.self,
                usage: "The branch to pin at"),
            pinParser.add(
                option: "--revision", kind: String.self,
                usage: "The revision to pin at"),
            to: {
                $0.pinOptions.version = $1
                $0.pinOptions.branch = $2
                $0.pinOptions.revision = $3 })

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
    var initMode: InitPackage.PackageType = .library

    var inputPath: AbsolutePath?
    var showDepsMode: ShowDependenciesMode = .text

    struct EditOptions {
        var packageName: String?
        var revision: String?
        var checkoutBranch: String?
        var path: AbsolutePath?
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
        var revision: String?
        var branch: String?
    }
    var pinOptions = PinOptions()

    /// Repin the dependencies when running package update.
    var repin = false

    enum ResolveToolMode: String {
        case text
        case json
    }
    var resolveToolMode: ResolveToolMode = .text

    enum ToolsVersionMode {
        case display
        case set(String)
        case setCurrent
    }
    var toolsVersionMode: ToolsVersionMode = .display
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
    case toolsVersion = "tools-version"
    case unedit
    case unpin
    case update
    case version
    case help

    // PackageMode is not used as an argument; completions will be
    // provided by the subparsers.
    public static var completion: ShellCompletion = .none
}

extension InitPackage.PackageType: StringEnumArgument {
    public static var completion: ShellCompletion {
        return .values([
            (empty.description, "generates an empty project"),
            (library.description, "generates project for a dynamic library"),
            (executable.description, "generates a project for a cli executable"),
            (systemModule.description, "generates a project for a system module")
        ])
    }
}

extension ShowDependenciesMode: StringEnumArgument {
    public static var completion: ShellCompletion {
        return .values([
            (text.description, "list dependencies using text format"),
            (dot.description, "list dependencies using dot format"),
            (json.description, "list dependencies using JSON format")
        ])
    }
}

extension DescribeMode: StringEnumArgument {
    public static var completion: ShellCompletion {
        return .values([
            (text.rawValue, "describe using text format"),
            (json.rawValue, "describe using JSON format")
        ])
    }
}

extension PackageToolOptions.ResolveToolMode: StringEnumArgument {
    static var completion: ShellCompletion {
        return .values([
            (text.rawValue, "resolve using text format"),
            (json.rawValue, "resolve using JSON format")
        ])
    }
}
