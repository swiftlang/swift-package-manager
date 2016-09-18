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
import Utility
import Xcodeproj

import enum Build.Configuration
import protocol Build.Toolchain

import func POSIX.chdir

private enum PackageToolError: Swift.Error {
    /// The flag needs to be present to execute some mode.
    case expectedFlag(PackageToolFlag)

    /// The package doesn't exist in the package graph.
    case packageNotFound
}

extension PackageToolError: FixableError {
    var error: String {
        switch self {
        case .expectedFlag(let flag):
            return "expected flag \(flag.description)"
        case .packageNotFound:
            return "the package doesn't exist."
        }
    }
    var fix: String? { return nil }
}

public enum PackageMode: Argument, Equatable, CustomStringConvertible {
    case dumpPackage
    case fetch
    case generateXcodeproj
    case getPackagePath
    case initPackage
    case showDependencies
    case resolve
    case update
    case usage
    case version

    public init?(argument: String, pop: @escaping () -> String?) throws {
        switch argument {
        case "dump-package":
            self = .dumpPackage
        case "fetch":
            self = .fetch
        case "generate-xcodeproj":
            self = .generateXcodeproj
        case "get-package-path":
            self = .getPackagePath
        case "init":
            self = .initPackage
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
        case .fetch: return "fetch"
        case .generateXcodeproj: return "generate-xcodeproj"
        case .getPackagePath: return "get-package-path"
        case .initPackage: return "initPackage"
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
    case package(String)

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
        case "--package":
            self = try .package(forcePop())
        default:
            return nil
        }
    }

    var description: String {
        switch self {
        case .package(_): return "--package"
        // FIXME: This doesn't cover all flags because right now only the .package
        // flag needs be shown in a diagnosis. This repetition of magic string is
        // error prone and is exoect to go away once we have new option parser.
        default: return String(describing: self)
        }
    }
}

public class PackageToolOptions: Options {
    var initMode: InitMode = InitMode.library
    var showDepsMode: ShowDependenciesMode = ShowDependenciesMode.text
    var inputPath: AbsolutePath? = nil
    var outputPath: AbsolutePath? = nil
    var xcodeprojOptions = XcodeprojOptions()
    var package: String? = nil
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

        case .getPackagePath:
            guard let packageName = options.package else {
                throw PackageToolError.expectedFlag(PackageToolFlag.package(""))
            }
            let graph = try loadPackage()
            guard let package = graph.packages.filter({ $0.name == packageName }).first else {
                throw PackageToolError.packageNotFound
            }
            print(package.path.asString)
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
            case .package(let name):
                options.package = name
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
