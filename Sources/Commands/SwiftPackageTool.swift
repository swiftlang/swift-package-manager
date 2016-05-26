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

#if HasCustomVersionString
import VersionInfo
#endif

import enum Build.Configuration
import enum Utility.ColorWrap
import protocol Build.Toolchain

import func POSIX.chdir

/// Additional conformance for our Options type.
extension PackageToolOptions: XcodeprojOptions {}

private enum Mode: Argument, Equatable, CustomStringConvertible {
    case Init(InitMode)
    case doctor
    case showDependencies(ShowDependenciesMode)
    case fetch
    case update
    case usage
    case version
    case generateXcodeproj(String?)
    case dumpPackage(String?)

    init?(argument: String, pop: () -> String?) throws {
        switch argument {
        case "init", "initialize":
            self = try .Init(InitMode(pop()))
        case "doctor":
            self = .doctor
        case "show-dependencies", "-D":
            self = try .showDependencies(ShowDependenciesMode(pop()))
        case "fetch":
            self = .fetch
        case "update":
            self = .update
        case "help", "usage", "--help", "-h":
            self = .usage
        case "version":
            self = .version
        case "generate-xcodeproj":
            self = .generateXcodeproj(pop())
        case "dump-package":
            self = .dumpPackage(pop())
        default:
            return nil
        }
    }

    var description: String {
        switch self {
        case .Init(let type): return "init=\(type)"
        case .doctor: return "doctor"
        case .showDependencies: return "show-dependencies"
        case .generateXcodeproj: return "generate-xcodeproj"
        case .fetch: return "fetch"
        case .update: return "update"
        case .usage: return "help"
        case .version: return "version"
        case .dumpPackage: return "dump-package"
        }
    }
}

private enum PackageToolFlag: Argument {
    case chdir(String)
    case colorMode(ColorWrap.Mode)
    case xcc(String)
    case xld(String)
    case xswiftc(String)
    case xcconfigOverrides(String)
    case ignoreDependencies
    case verbose(Int)

    init?(argument: String, pop: () -> String?) throws {

        func forcePop() throws -> String {
            guard let value = pop() else { throw OptionParserError.expectedAssociatedValue(argument) }
            return value
        }

        switch argument {
        case Flag.chdir, Flag.C:
            self = try .chdir(forcePop())
        case "--verbose", "-v":
            self = .verbose(1)
        case "-vv":
            self = .verbose(2)
        case "--color":
            let rawValue = try forcePop()
            guard let mode = ColorWrap.Mode(rawValue) else  {
                throw OptionParserError.invalidUsage("invalid color mode: \(rawValue)")
            }
            self = .colorMode(mode)
        case "--ignore-dependencies":
            self = .ignoreDependencies
        default:
            return nil
        }
    }
}

private class PackageToolOptions: Options {
    var verbosity: Int = 0
    var colorMode: ColorWrap.Mode = .Auto
    var Xcc: [String] = []
    var Xld: [String] = []
    var Xswiftc: [String] = []
    var xcconfigOverrides: String? = nil
    var ignoreDependencies: Bool = false
}

/// swift-build tool namespace
public struct SwiftPackageTool {
    let args: [String]

    public init(args: [String]) {
        self.args = args
    }

    public func run() {
        do {
            let args = Array(Process.arguments.dropFirst())
            let (mode, opts) = try parse(commandLineArguments: args)
        
            verbosity = Verbosity(rawValue: opts.verbosity)
            colorMode = opts.colorMode
        
            if let dir = opts.chdir {
                try chdir(dir)
            }
        
            func parseManifest(path: String, baseURL: String) throws -> Manifest {
                let swiftc = ToolDefaults.SWIFT_EXEC
                let libdir = ToolDefaults.libdir
                return try Manifest(path: path, baseURL: baseURL, swiftc: swiftc, libdir: libdir)
            }
            
            func fetch(_ root: String) throws -> (rootPackage: Package, externalPackages:[Package]) {
                let manifest = try parseManifest(path: root, baseURL: root)
                if opts.ignoreDependencies {
                    return (Package(manifest: manifest, url: manifest.path.parentDirectory), [])
                } else {
                    return try get(manifest, manifestParser: parseManifest)
                }
            }
        
            switch mode {
            case .Init(let initMode):
                let initPackage = try InitPackage(mode: initMode)
                try initPackage.writePackageStructure()
                            
            case .update:
                // Attempt to ensure that none of the repositories are modified.
                for item in walk(opts.path.Packages, recursively: false) {
                    // Only look at repositories.
                    guard Path.join(item, ".git").exists else { continue }

                    // If there is a staged or unstaged diff, don't remove the
                    // tree. This won't detect new untracked files, but it is
                    // just a safety measure for now.
                    let diffArgs = ["--no-ext-diff", "--quiet", "--exit-code"]
                    do {
                        _ = try Git.runPopen([Git.tool, "-C", item, "diff"] + diffArgs)
                        _ = try Git.runPopen([Git.tool, "-C", item, "diff", "--cached"] + diffArgs)
                    } catch {
                        throw Error.repositoryHasChanges(item)
                    }
                }
                try Utility.removeFileTree(opts.path.Packages)
                fallthrough
                
            case .fetch:
                _ = try fetch(opts.path.root)
        
            case .usage:
                usage()
        
            case .doctor:
                doctor()
            
            case .showDependencies(let mode):
                let (rootPackage, _) = try fetch(opts.path.root)
                dumpDependenciesOf(rootPackage: rootPackage, mode: mode)
        
            case .version:
                #if HasCustomVersionString
                    print(String(cString: VersionInfo.DisplayString()))
                #else
                    print("Swift Package Manager – Swift 3.0")
                #endif
                
            case .generateXcodeproj(let outpath):
                let (rootPackage, externalPackages) = try fetch(opts.path.root)
                let (modules, externalModules, products) = try transmute(rootPackage, externalPackages: externalPackages)
                
                let xcodeModules = modules.flatMap { $0 as? XcodeModuleProtocol }
                let externalXcodeModules  = externalModules.flatMap { $0 as? XcodeModuleProtocol }
        
                let projectName: String
                let dstdir: String
                let packageName = rootPackage.name
        
                switch outpath {
                case let outpath? where outpath.hasSuffix(".xcodeproj"):
                    // if user specified path ending with .xcodeproj, use that
                    projectName = String(outpath.basename.characters.dropLast(10))
                    dstdir = outpath.parentDirectory
                case let outpath?:
                    dstdir = outpath
                    projectName = packageName
                case _:
                    dstdir = opts.path.root
                    projectName = packageName
                }
                let outpath = try Xcodeproj.generate(dstdir: dstdir.abspath, projectName: projectName, srcroot: opts.path.root, modules: xcodeModules, externalModules: externalXcodeModules, products: products, options: opts)
        
                print("generated:", outpath.prettyPath)
                
            case .dumpPackage(let packagePath):
                
                let root = packagePath ?? opts.path.root
                let manifest = try parseManifest(path: root, baseURL: root)
                let package = manifest.package
                let json = try jsonString(package: package)
                print(json)
            }
        
        } catch {
            handle(error: error, usage: usage)
        }
    }

    private func usage(_ print: (String) -> Void = { print($0) }) {
        //     .........10.........20.........30.........40.........50.........60.........70..
        print("OVERVIEW: Perform operations on Swift packages")
        print("")
        print("USAGE: swift package [command] [options]")
        print("")
        print("COMMANDS:")
        print("  init[=<type>]                 Initialize a new package (executable|library)")
        print("  fetch                         Fetch package dependencies")
        print("  update                        Update package dependencies")
        print("  generate-xcodeproj[=<path>]   Generates an Xcode project")
        print("  show-dependencies[=<format>]  Print dependency graph (text|dot|json)")
        print("  dump-package[=<path>]         Print Package.swift as JSON")
        print("")
        print("OPTIONS:")
        print("  --chdir <path>       Change working directory before any command [-C]")
        print("  --color <mode>       Specify color mode (auto|always|never)")
        print("  --verbose            Increase verbosity of informational output [-v]")
        print("  -Xcc <flag>          Pass flag through to all C compiler instantiations")
        print("  -Xlinker <flag>      Pass flag through to all linker instantiations")
        print("  -Xswiftc <flag>      Pass flag through to all Swift compiler instantiations")
        print("")
        print("")
        print("NOTE: Use `swift build` to build packages, and `swift test` to test packages")
    }
    
    private func parse(commandLineArguments args: [String]) throws -> (Mode, PackageToolOptions) {
        let (mode, flags): (Mode?, [PackageToolFlag]) = try Basic.parseOptions(arguments: args)
    
        let opts = PackageToolOptions()
        for flag in flags {
            switch flag {
            case .chdir(let path):
                opts.chdir = path
            case .xcc(let value):
                opts.Xcc.append(value)
            case .xld(let value):
                opts.Xld.append(value)
            case .xswiftc(let value):
                opts.Xswiftc.append(value)
            case .verbose(let amount):
                opts.verbosity += amount
            case .colorMode(let mode):
                opts.colorMode = mode
            case .xcconfigOverrides(let path):
                opts.xcconfigOverrides = path
            case .ignoreDependencies:
                opts.ignoreDependencies = true
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
