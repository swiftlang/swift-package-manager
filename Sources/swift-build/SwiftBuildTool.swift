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
import Multitool
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
extension Options: XcodeprojOptions {}

private enum Mode: Argument, Equatable, CustomStringConvertible {
    case Build(Configuration, Toolchain)
    case Clean(CleanMode)
    case Doctor
    case ShowDependencies(ShowDependenciesMode)
    case Fetch
    case Update
    case Init(InitMode)
    case Usage
    case Version
    case GenerateXcodeproj(String?)
    case DumpPackage(String?)

    init?(argument: String, pop: () -> String?) throws {
        switch argument {
        case "--configuration", "--conf", "-c":
            self = try .Build(Configuration(pop()), UserToolchain())
        case "--clean":
            self = try .Clean(CleanMode(pop()))
        case "--doctor":
            self = .Doctor
        case "--show-dependencies", "-D":
            self = try .ShowDependencies(ShowDependenciesMode(pop()))
        case "--fetch":
            self = .Fetch
        case "--update":
            self = .Update
        case "--init", "--initialize":
            self = try .Init(InitMode(pop()))
        case "--help", "--usage", "-h":
            self = .Usage
        case "--version":
            self = .Version
        case "--generate-xcodeproj", "-X":
            self = .GenerateXcodeproj(pop())
        case "--dump-package":
            self = .DumpPackage(pop())
        default:
            return nil
        }
    }

    var description: String {
        switch self {
            case .Build(let conf, _): return "--configuration=\(conf)"
            case .Clean(let mode): return "--clean=\(mode)"
            case .Doctor: return "--doctor"
            case .ShowDependencies: return "--show-dependencies"
            case .GenerateXcodeproj: return "--generate-xcodeproj"
            case .Fetch: return "--fetch"
            case .Update: return "--update"
            case .Init(let mode): return "--init=\(mode)"
            case .Usage: return "--help"
            case .Version: return "--version"
            case .DumpPackage: return "--dump-package"
        }
    }
}

private enum Flag: Argument {
    case Xcc(String)
    case Xld(String)
    case Xswiftc(String)
    case buildPath(String)
    case buildTests
    case chdir(String)
    case colorMode(ColorWrap.Mode)
    case ignoreDependencies
    case verbose(Int)
    case xcconfigOverrides(String)

    init?(argument: String, pop: () -> String?) throws {

        func forcePop() throws -> String {
            guard let value = pop() else { throw OptionParserError.ExpectedAssociatedValue(argument) }
            return value
        }

        switch argument {
        case Multitool.Flag.chdir, Multitool.Flag.C:
            self = try .chdir(forcePop())
        case "--verbose", "-v":
            self = .verbose(1)
        case "-vv":
            self = .verbose(2)
        case "-Xcc":
            self = try .Xcc(forcePop())
        case "-Xlinker":
            self = try .Xld(forcePop())
        case "-Xswiftc":
            self = try .Xswiftc(forcePop())
        case "--build-path":
            self = try .buildPath(forcePop())
        case "--build-tests":
            self = .buildTests
        case "--color":
            let rawValue = try forcePop()
            guard let mode = ColorWrap.Mode(rawValue) else  {
                throw OptionParserError.InvalidUsage("invalid color mode: \(rawValue)")
            }
            self = .colorMode(mode)
        case "--ignore-dependencies":
            self = .ignoreDependencies
        case "--xcconfig-overrides":
            self = try .xcconfigOverrides(forcePop())
        default:
            return nil
        }
    }
}

private class Options: Multitool.Options {
    var verbosity: Int = 0
    var Xcc: [String] = []
    var Xld: [String] = []
    var Xswiftc: [String] = []
    var buildTests: Bool = false
    var colorMode: ColorWrap.Mode = .Auto
    var ignoreDependencies: Bool = false
    var xcconfigOverrides: String? = nil
}

/// swift-build tool namespace
struct SwiftBuildTool {
    let args: [String]

    func run() {
        do {
            let args = Array(Process.arguments.dropFirst())
            let (mode, opts) = try parse(commandLineArguments: args)
        
            verbosity = Verbosity(rawValue: opts.verbosity)
            colorMode = opts.colorMode
        
            if let dir = opts.chdir {
                try chdir(dir)
            }
        
            func parseManifest(path: String, baseURL: String) throws -> Manifest {
                let swiftc = Multitool.SWIFT_EXEC
                let libdir = Multitool.libdir
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
            case .Build(let conf, let toolchain):
                let (rootPackage, externalPackages) = try fetch(opts.path.root)
                try generateVersionData(opts.path.root, rootPackage: rootPackage, externalPackages: externalPackages)
                let (modules, externalModules, products) = try transmute(rootPackage, externalPackages: externalPackages)
                let yaml = try describe(opts, conf, modules, Set(externalModules), products, toolchain: toolchain)
                try build(YAMLPath: yaml, target: opts.buildTests ? "test" : nil)
        
            case .Init(let initMode):
                let initPackage = try InitPackage(mode: initMode)
                try initPackage.writePackageStructure()
                            
            case .Update:
                try Utility.removeFileTree(opts.path.Packages)
                fallthrough
                
            case .Fetch:
                _ = try fetch(opts.path.root)
        
            case .Usage:
                usage()
        
            case .Clean(.Dist):
                if opts.path.Packages.exists {
                    try Utility.removeFileTree(opts.path.Packages)
                }
                fallthrough
        
            case .Clean(.Build):
                let artifacts = ["debug", "release"].map{ Path.join(opts.path.build, $0) }.map{ ($0, "\($0).yaml") }
                for (dir, yml) in artifacts {
                    if dir.isDirectory { try Utility.removeFileTree(dir) }
                    if yml.isFile { try Utility.removeFileTree(yml) }
                }
        
                let db = Path.join(opts.path.build, "build.db")
                if db.isFile { try Utility.removeFileTree(db) }
        
                let versionData = Path.join(opts.path.build, "versionData")
                if versionData.isDirectory { try Utility.removeFileTree(versionData) }
        
                if opts.path.build.exists {
                    try Utility.removeFileTree(opts.path.build)
                }
        
            case .Doctor:
                doctor()
            
            case .ShowDependencies(let mode):
                let (rootPackage, _) = try fetch(opts.path.root)
                dumpDependenciesOf(rootPackage: rootPackage, mode: mode)
        
            case .Version:
                #if HasCustomVersionString
                    print(String(cString: VersionInfo.DisplayString()))
                #else
                    print("Swift Package Manager – Swift 3.0")
                #endif
                
            case .GenerateXcodeproj(let outpath):
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
                
            case .DumpPackage(let packagePath):
                
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
        print("OVERVIEW: Build sources into binary products")
        print("")
        print("USAGE: swift build [mode] [options]")
        print("")
        print("MODES:")
        print("  --configuration <value>        Build with configuration (debug|release) [-c]")
        print("  --clean[=<mode>]               Delete artifacts (build|dist)")
        print("  --init[=<mode>]                Create a package template (executable|library)")
        print("  --fetch                        Fetch package dependencies")
        print("  --update                       Update package dependencies")
        print("  --generate-xcodeproj[=<path>]  Generates an Xcode project [-X]")
        print("  --show-dependencies[=<mode>]   Print dependency graph (text|dot|json)")
        print("  --dump-package[=<path>]        Print Package.swift as JSON")
        print("")
        print("OPTIONS:")
        print("  --chdir <path>       Change working directory before any other operation [-C]")
        print("  --build-path <path>  Specify build directory")
        print("  --color <mode>       Specify color mode (auto|always|never)")
        print("  -v[v]                Increase verbosity of informational output")
        print("  -Xcc <flag>          Pass flag through to all C compiler instantiations")
        print("  -Xlinker <flag>      Pass flag through to all linker instantiations")
        print("  -Xswiftc <flag>      Pass flag through to all Swift compiler instantiations")
    }
    
    private func parse(commandLineArguments args: [String]) throws -> (Mode, Options) {
        let mode: Mode?
        let flags: [Flag]
        (mode, flags) = try Basic.parseOptions(arguments: args)
    
        let opts = Options()
        for flag in flags {
            switch flag {
            case .chdir(let path):
                opts.chdir = path
            case .verbose(let amount):
                opts.verbosity += amount
            case .Xcc(let value):
                opts.Xcc.append(value)
            case .Xld(let value):
                opts.Xld.append(value)
            case .Xswiftc(let value):
                opts.Xswiftc.append(value)
            case .buildPath(let path):
                opts.path.build = path
            case .buildTests:
                opts.buildTests = true
            case .colorMode(let mode):
                opts.colorMode = mode
            case .xcconfigOverrides(let path):
                opts.xcconfigOverrides = path
            case .ignoreDependencies:
                opts.ignoreDependencies = true
            }
        }
    
        return try (mode ?? .Build(.Debug, UserToolchain()), opts)
    }

    private func describe(_ opts: Options, _ conf: Configuration, _ modules: [Module], _ externalModules: Set<Module>, _ products: [Product], toolchain: Toolchain) throws -> String {
        do {
            return try Build.describe(opts.path.build, conf, modules, externalModules, products, Xcc: opts.Xcc, Xld: opts.Xld, Xswiftc: opts.Xswiftc, toolchain: toolchain)
        } catch {
#if os(Linux)
            // it is a common error on Linux for clang++ to not be installed, but
            // we need it for linking. swiftc itself gives a non-useful error, so
            // we try to help here.
        
            //FIXME we should use C-functions here

            if (try? Utility.popen(["command", "-v", "clang++"])) == nil {
                print("warning: clang++ not found: this will cause build failure", to: &stderr)
            }
#endif
            throw error
        }
    }
}

extension Build.Configuration {
    private init(_ rawValue: String?) throws {
        switch rawValue?.lowercased() {
        case "debug"?:
            self = .Debug
        case "release"?:
            self = .Release
        case nil:
            throw OptionParserError.ExpectedAssociatedValue("--configuration")
        default:
            throw OptionParserError.InvalidUsage("invalid build configuration: \(rawValue!)")
        }
    }
}

enum CleanMode: CustomStringConvertible {
    case Build, Dist

    private init(_ rawValue: String?) throws {
        switch rawValue?.lowercased() {
        case nil, "build"?:
            self = .Build
        case "dist"?, "distribution"?:
            self = .Dist
        default:
            throw OptionParserError.InvalidUsage("invalid clean mode: \(rawValue)")
        }
    }

    var description: String {
        switch self {
            case .Dist: return "distribution"
            case .Build: return "build"
        }
    }
}

enum InitMode: CustomStringConvertible {
    case Library, Executable

    private init(_ rawValue: String?) throws {
        switch rawValue?.lowercased() {
        case "library"?, "lib"?:
            self = .Library
        case nil, "executable"?, "exec"?, "exe"?:
            self = .Executable
        default:
            throw OptionParserError.InvalidUsage("invalid initialization mode: \(rawValue)")
        }
    }

    var description: String {
        switch self {
            case .Library: return "library"
            case .Executable: return "executable"
        }
    }
}

private func ==(lhs: Mode, rhs: Mode) -> Bool {
    return lhs.description == rhs.description
}

enum ShowDependenciesMode: CustomStringConvertible {
    case Text, DOT, JSON
    
    private init(_ rawValue: String?) throws {
        guard let rawValue = rawValue else {
            self = .Text
            return
        }
        
        switch rawValue.lowercased() {
        case "text":
           self = .Text
        case "dot":
           self = .DOT
        case "json":
           self = .JSON
        default:
            throw OptionParserError.InvalidUsage("invalid show dependencies mode: \(rawValue)")
        }
    }
    
    var description: String {
        switch self {
        case .Text: return "text"
        case .DOT: return "dot"
        case .JSON: return "json"
        }
    }
}
