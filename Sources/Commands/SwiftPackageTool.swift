/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Build
import Get
import PackageLoading
import PackageModel
import SourceControl
import Utility
import Xcodeproj

import enum Build.Configuration
import protocol Build.Toolchain
import func POSIX.exit
import func POSIX.chdir

/// Errors encountered duing the package tool operations.
enum PackageToolOperationError: Swift.Error {
    /// The provided package name doesn't exist in package graph.
    case packageNotFound

    /// The current mode does not have all the options it requires.
    case insufficientOptions(usage: String)
}

public enum PackageMode: Argument, Equatable, CustomStringConvertible {
    case dumpPackage
    case edit
    case unedit
    case fetch
    case generateXcodeproj
    case initPackage
    case showDependencies
    case reset
    case resolve
    case update
    case usage
    case version

    public init?(argument: String, pop: @escaping () -> String?) throws {
        switch argument {
        case "dump-package":
            self = .dumpPackage
        case "edit":
            self = .edit
        case "unedit":
            self = .unedit
        case "fetch":
            self = .fetch
        case "generate-xcodeproj":
            self = .generateXcodeproj
        case "init":
            self = .initPackage
        case "reset":
            self = .reset
        case "resolve":
            self = .resolve
        case "show-dependencies":
            self = .showDependencies
        case "update":
            self = .update
        case "--help", "-h":
            self = .usage
        case "--version":
            self = .version
        default:
            return nil
        }
    }

    public var description: String {
        switch self {
        case .dumpPackage: return "dump-package"
        case .edit: return "edit"
        case .unedit: return "unedit"
        case .fetch: return "fetch"
        case .generateXcodeproj: return "generate-xcodeproj"
        case .initPackage: return "initPackage"
        case .reset: return "reset"
        case .resolve: return "resolve"
        case .showDependencies: return "show-dependencies"
        case .update: return "update"
        case .usage: return "--help"
        case .version: return "--version"
        }
    }
}

private enum PackageToolFlag: Argument {
    case initMode(String)
    case showDepsMode(String)
    case enableCodeCoverage
    case inputPath(AbsolutePath)
    case outputPath(AbsolutePath)
    case chdir(AbsolutePath)
    case colorMode(ColorWrap.Mode)
    case xcc(String)
    case xld(String)
    case xswiftc(String)
    case buildPath(AbsolutePath)
    case enableNewResolver
    case xcconfigOverrides(AbsolutePath)
    case verbose(Int)
    case packageName(String)
    case editRevision(String)
    case editCheckoutBranch(String)
    case editForceRemove

    init?(argument: String, pop: @escaping () -> String?) throws {

        func forcePop() throws -> String {
            guard let value = pop() else { throw OptionParserError.expectedAssociatedValue(argument) }
            return value
        }

        switch argument {
        case Flag.chdir, Flag.C:
            self = try .chdir(AbsolutePath(forcePop(), relativeTo: currentWorkingDirectory))
        case "--type":
            self = try .initMode(forcePop())
        case "--enable-code-coverage":
            self = .enableCodeCoverage
        case "--format":
            self = try .showDepsMode(forcePop())
        case "--output":
            self = try .outputPath(AbsolutePath(forcePop(), relativeTo: currentWorkingDirectory))
        case "--input":
            self = try .inputPath(AbsolutePath(forcePop(), relativeTo: currentWorkingDirectory))
        case "--verbose", "-v":
            self = .verbose(1)
        case "--color":
            let rawValue = try forcePop()
            guard let mode = ColorWrap.Mode(rawValue) else  {
                throw OptionParserError.invalidUsage("invalid color mode: \(rawValue)")
            }
            self = .colorMode(mode)
        case "-Xcc":
            self = try .xcc(forcePop())
        case "-Xlinker":
            self = try .xld(forcePop())
        case "-Xswiftc":
            self = try .xswiftc(forcePop())
        case "--build-path":
            self = try .buildPath(AbsolutePath(forcePop(), relativeTo: currentWorkingDirectory))
        case "--enable-new-resolver":
            self = .enableNewResolver
        case "--xcconfig-overrides":
            self = try .xcconfigOverrides(AbsolutePath(forcePop(), relativeTo: currentWorkingDirectory))
        case "--name":
            self = try .packageName(forcePop())
        case "--revision":
            self = try .editRevision(forcePop())
        case "--branch", "-b":
            self = try .editCheckoutBranch(forcePop())
        case "--force", "-f":
            self = .editForceRemove
        default:
            return nil
        }
    }
}

public class PackageToolOptions: Options {
    var initMode: InitMode = InitMode.library
    var showDepsMode: ShowDependenciesMode = ShowDependenciesMode.text
    var packageName: String? = nil
    var editRevision: String? = nil
    var editCheckoutBranch: String? = nil
    var editForceRemove = false
    var inputPath: AbsolutePath? = nil
    var outputPath: AbsolutePath? = nil
    var xcodeprojOptions = XcodeprojOptions()
}

/// swift-build tool namespace
public class SwiftPackageTool: SwiftTool<PackageMode, PackageToolOptions> {

    override func runImpl() throws {
        switch mode {
        case .usage:
            SwiftPackageTool.usage()

        case .version:
            print(Versioning.currentVersion.completeDisplayString)

        case .initPackage:
            let initPackage = try InitPackage(mode: options.initMode)
            try initPackage.writePackageStructure()

        case .reset:
            if options.enableNewResolver {
                try getActiveWorkspace().reset()
            } else {
                // Remove the checkouts directory.
                if try exists(getCheckoutsDirectory()) {
                    try removeFileTree(getCheckoutsDirectory())
                }
                // Remove the build directory.
                if exists(buildPath) {
                    try removeFileTree(buildPath)
                }
            }

        case .resolve:
            // NOTE: This command is currently undocumented, and is for
            // bringup of the new dependency resolution logic. This is *NOT*
            // the code currently used to resolve dependencies (which runs
            // off of the infrastructure in the `Get` module).
            try executeResolve(options)
            break

        case .update:
            if options.enableNewResolver {
                let workspace = try getActiveWorkspace()
                try workspace.updateDependencies()
            } else {
                let packagesDirectory = try getCheckoutsDirectory()
                // Attempt to ensure that none of the repositories are modified.
                if localFileSystem.exists(packagesDirectory) {
                    for name in try localFileSystem.getDirectoryContents(packagesDirectory) {
                        let item = packagesDirectory.appending(RelativePath(name))

                        // Only look at repositories.
                        guard exists(item.appending(component: ".git")) else { continue }

                        // If there is a staged or unstaged diff, don't remove the
                        // tree. This won't detect new untracked files, but it is
                        // just a safety measure for now.
                        let diffArgs = ["--no-ext-diff", "--quiet", "--exit-code"]
                        do {
                            _ = try Git.runPopen([Git.tool, "-C", item.asString, "diff"] + diffArgs)
                            _ = try Git.runPopen([Git.tool, "-C", item.asString, "diff", "--cached"] + diffArgs)
                        } catch {
                            throw Error.repositoryHasChanges(item.asString)
                        }
                    }
                    try removeFileTree(packagesDirectory)
                }
                _ = try loadPackage()
            }
        case .fetch:
            _ = try loadPackage()

        case .edit:
            guard options.enableNewResolver else {
                fatalError("This mode requires --enable-new-resolver")
            }
            // Make sure we have all the options required for editing the package.
            guard let packageName = options.packageName, (options.editRevision != nil || options.editCheckoutBranch != nil) else {
                throw PackageToolOperationError.insufficientOptions(usage: editUsage)
            }
            // Get the current workspace.
            let workspace = try getActiveWorkspace()
            let manifests = try workspace.loadDependencyManifests()
            // Look for the package's manifest.
            guard let (manifest, dependency) = manifests.lookup(package: packageName) else {
                throw PackageToolOperationError.packageNotFound
            }
            // Create revision object if provided by user.
            let revision = options.editRevision.flatMap { Revision(identifier: $0) }
            // Put the dependency in edit mode.
            try workspace.edit(dependency: dependency, at: revision, packageName: manifest.name, checkoutBranch: options.editCheckoutBranch)

        case .unedit:
            guard options.enableNewResolver else {
                fatalError("This mode requires --enable-new-resolver")
            }
            guard let packageName = options.packageName else {
                throw PackageToolOperationError.insufficientOptions(usage: uneditUsage)
            }
            let workspace = try getActiveWorkspace()
            let manifests = try workspace.loadDependencyManifests()
            // Look for the package's manifest.
            guard let editedDependency = manifests.lookup(package: packageName)?.dependency else {
                throw PackageToolOperationError.packageNotFound
            }
            try workspace.unedit(dependency: editedDependency, forceRemove: options.editForceRemove)

        case .showDependencies:
            let graph = try loadPackage()
            dumpDependenciesOf(rootPackage: graph.rootPackage, mode: options.showDepsMode)
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
                projectName = graph.rootPackage.name
            case _:
                dstdir = try getPackageRoot()
                projectName = graph.rootPackage.name
            }
            let outpath = try Xcodeproj.generate(outputDir: dstdir, projectName: projectName, graph: graph, options: options.xcodeprojOptions)

            print("generated:", outpath.prettyPath)

        case .dumpPackage:
            let manifest = try loadRootManifest(options)
            // FIXME: It would be nice if this has a pretty print option.
            print(manifest.jsonString())
        }
    }

    /// Load the manifest for the root package
    func loadRootManifest(_ options: PackageToolOptions) throws -> Manifest {
        let root = try options.inputPath ?? getPackageRoot()
        return try manifestLoader.loadFile(path: root, baseURL: root.asString, version: nil)
    }
    
    override class func usage(_ print: (String) -> Void = { print($0) }) {
        //     .........10.........20.........30.........40.........50.........60.........70..
        print("OVERVIEW: Perform operations on Swift packages")
        print("")
        print("USAGE: swift package [command] [options]")
        print("")
        print("COMMANDS:")
        print("  init [--type <type>]                   Initialize a new package")
        print("      (type: empty|library|executable|system-module)")
        print("  fetch                                  Fetch package dependencies")
        print("  update                                 Update package dependencies")
        print("  generate-xcodeproj [--output <path>]   Generates an Xcode project")
        print("  show-dependencies [--format <format>]  Print the resolved dependency graph")
        print("      (format: text|dot|json)")
        print("  dump-package [--input <path>]          Print parsed Package.swift as JSON")
        print("")
        print("OPTIONS:")
        print("  -C, --chdir <path>        Change working directory before any other operation")
        print("  --build-path <path>       Specify build/cache directory [default: ./.build]")
        print("  --color <mode>            Specify color mode (auto|always|never)")
        print("  --enable-code-coverage    Enable code coverage in generated Xcode projects")
        print("  -v, --verbose             Increase verbosity of informational output")
        print("  --version                 Print the Swift Package Manager version")
        print("  -Xcc <flag>               Pass flag through to all C compiler invocations")
        print("  -Xlinker <flag>           Pass flag through to all linker invocations")
        print("  -Xswiftc <flag>           Pass flag through to all Swift compiler invocations")
        print("")
        print("NOTE: Use `swift build` to build packages, and `swift test` to test packages")
    }

    var editUsage: String {
        let stream = BufferedOutputByteStream()
        stream <<< "Expected package edit format:\n"
        stream <<< "swift package edit --name <packageName> (--revision <revision> | --branch <newBranch>)\n"
        stream <<< "Note: Either revision or branch name is required."
        return stream.bytes.asString!
    }

    var uneditUsage: String {
        let stream = BufferedOutputByteStream()
        stream <<< "Expected package unedit format:\n"
        stream <<< "swift package unedit --name <packageName> [--force]"
        return stream.bytes.asString!
    }
    
    override class func parse(commandLineArguments args: [String]) throws -> (PackageMode, PackageToolOptions) {
        let (mode, flags): (PackageMode?, [PackageToolFlag]) = try Basic.parseOptions(arguments: args)
    
        let options = PackageToolOptions()
        for flag in flags {
            switch flag {
            case .initMode(let value):
                options.initMode = try InitMode(value)
            case .showDepsMode(let value):
                options.showDepsMode = try ShowDependenciesMode(value)
            case .inputPath(let path):
                options.inputPath = path
            case .outputPath(let path):
                options.outputPath = path
            case .chdir(let path):
                options.chdir = path
            case .enableCodeCoverage:
                options.xcodeprojOptions.enableCodeCoverage = true
            case .xcc(let value):
                options.xcodeprojOptions.flags.cCompilerFlags.append(value)
            case .xld(let value):
                options.xcodeprojOptions.flags.linkerFlags.append(value)
            case .xswiftc(let value):
                options.xcodeprojOptions.flags.swiftCompilerFlags.append(value)
            case .buildPath(let path):
                options.buildPath = path
            case .enableNewResolver:
                options.enableNewResolver = true
            case .verbose(let amount):
                options.verbosity += amount
            case .colorMode(let mode):
                options.colorMode = mode
            case .xcconfigOverrides(let path):
                options.xcodeprojOptions.xcconfigOverrides = path
            case .packageName(let name):
                options.packageName = name
            case .editRevision(let rev):
                options.editRevision = rev
            case .editCheckoutBranch(let branch):
                options.editCheckoutBranch = branch
            case .editForceRemove:
                options.editForceRemove = true
            }
        }
        if let mode = mode {
            return (mode, options)
        }
        else {
            // FIXME: This needs to produce a properly quoted string, once we have such API.
            throw OptionParserError.noCommandProvided(args.joined(separator: " "))
        }
    }
}

public func ==(lhs: PackageMode, rhs: PackageMode) -> Bool {
    return lhs.description == rhs.description
}
