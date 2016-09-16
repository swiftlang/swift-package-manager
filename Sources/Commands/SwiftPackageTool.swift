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

private enum Mode: Argument, Equatable, CustomStringConvertible {
    case dumpPackage
    case fetch
    case generateXcodeproj
    case initPackage
    case showDependencies
    case resolve
    case update
    case usage
    case version

    init?(argument: String, pop: @escaping () -> String?) throws {
        switch argument {
        case "dump-package":
            self = .dumpPackage
        case "fetch":
            self = .fetch
        case "generate-xcodeproj":
            self = .generateXcodeproj
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

    var description: String {
        switch self {
        case .dumpPackage: return "dump-package"
        case .fetch: return "fetch"
        case .generateXcodeproj: return "generate-xcodeproj"
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
        default:
            return nil
        }
    }
}

class PackageToolOptions: Options {
    var initMode: InitMode = InitMode.library
    var showDepsMode: ShowDependenciesMode = ShowDependenciesMode.text
    var inputPath: AbsolutePath? = nil
    var outputPath: AbsolutePath? = nil
    var verbosity: Int = 0
    var colorMode: ColorWrap.Mode = .Auto
    var xcodeprojOptions = XcodeprojOptions()
}

/// swift-build tool namespace
public struct SwiftPackageTool: SwiftTool {
    let args: [String]

    public init(args: [String]) {
        self.args = args
    }

    public func run() {
        do {
            let (mode, opts) = try parse(commandLineArguments: args)
        
            verbosity = Verbosity(rawValue: opts.verbosity)
            colorMode = opts.colorMode
        
            if let dir = opts.chdir {
                try chdir(dir.asString)
            }
        
            switch mode {
            case .usage:
                usage()
        
            case .version:
                print(Versioning.currentVersion.completeDisplayString)
                
            case .initPackage:
                let initPackage = try InitPackage(mode: opts.initMode)
                try initPackage.writePackageStructure()

            case .resolve:
                // NOTE: This command is currently undocumented, and is for
                // bringup of the new dependency resolution logic. This is *NOT*
                // the code currently used to resolve dependencies (which runs
                // off of the infrastructure in the `Get` module).
                try executeResolve(opts)
                break

            case .update:
                // Attempt to ensure that none of the repositories are modified.
                if localFileSystem.exists(opts.path.packages) {
                    for name in try localFileSystem.getDirectoryContents(opts.path.packages) {
                        let item = opts.path.packages.appending(RelativePath(name))

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
                    try removeFileTree(opts.path.packages)
                }
                fallthrough
                
            case .fetch:
                _ = try loadPackage(at: opts.path.root, opts)
        
            case .showDependencies:
                let graph = try loadPackage(at: opts.path.root, opts)
                dumpDependenciesOf(rootPackage: graph.rootPackage, mode: opts.showDepsMode)
            case .generateXcodeproj:
                let graph = try loadPackage(at: opts.path.root, opts)

                let projectName: String
                let dstdir: AbsolutePath
        
                switch opts.outputPath {
                case let outpath? where outpath.suffix == ".xcodeproj":
                    // if user specified path ending with .xcodeproj, use that
                    projectName = String(outpath.basename.characters.dropLast(10))
                    dstdir = outpath.parentDirectory
                case let outpath?:
                    dstdir = outpath
                    projectName = graph.rootPackage.name
                case _:
                    dstdir = opts.path.root
                    projectName = graph.rootPackage.name
                }
                let outpath = try Xcodeproj.generate(dstdir: dstdir, projectName: projectName, graph: graph, options: opts.xcodeprojOptions)
        
                print("generated:", outpath.prettyPath)
                
            case .dumpPackage:
                let manifest = try loadRootManifest(opts)
                // FIXME: It would be nice if this has a pretty print option.
                print(manifest.jsonString())
            }
        
        } catch {
            handle(error: error, usage: usage)
        }
    }

    /// Load the manifest for the root package
    func loadRootManifest(_ opts: PackageToolOptions) throws -> Manifest {
        let root = opts.inputPath ?? opts.path.root
        return try manifestLoader.loadFile(path: root, baseURL: root.asString, version: nil)
    }
    
    private func usage(_ print: (String) -> Void = { print($0) }) {
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
    
    private func parse(commandLineArguments args: [String]) throws -> (Mode, PackageToolOptions) {
        let (mode, flags): (Mode?, [PackageToolFlag]) = try Basic.parseOptions(arguments: args)
    
        let opts = PackageToolOptions()
        for flag in flags {
            switch flag {
            case .initMode(let value):
                opts.initMode = try InitMode(value)
            case .showDepsMode(let value):
                opts.showDepsMode = try ShowDependenciesMode(value)
            case .inputPath(let path):
                opts.inputPath = path
            case .outputPath(let path):
                opts.outputPath = path
            case .chdir(let path):
                opts.chdir = path
            case .enableCodeCoverage:
                opts.xcodeprojOptions.enableCodeCoverage = true
            case .xcc(let value):
                opts.xcodeprojOptions.flags.cCompilerFlags.append(value)
            case .xld(let value):
                opts.xcodeprojOptions.flags.linkerFlags.append(value)
            case .xswiftc(let value):
                opts.xcodeprojOptions.flags.swiftCompilerFlags.append(value)
            case .buildPath(let path):
                opts.path.build = path
            case .enableNewResolver:
                opts.enableNewResolver = true
            case .verbose(let amount):
                opts.verbosity += amount
            case .colorMode(let mode):
                opts.colorMode = mode
            case .xcconfigOverrides(let path):
                opts.xcodeprojOptions.xcconfigOverrides = path
            }
        }
        if let mode = mode {
            return (mode, opts)
        }
        else {
            // FIXME: This needs to produce a properly quoted string, once we have such API.
            throw OptionParserError.noCommandProvided(args.joined(separator: " "))
        }
    }
}

private func ==(lhs: Mode, rhs: Mode) -> Bool {
    return lhs.description == rhs.description
}
