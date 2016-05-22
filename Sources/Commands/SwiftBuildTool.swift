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
extension BuildToolOptions: XcodeprojOptions {}

private enum Mode: Argument, Equatable, CustomStringConvertible {
    case build(Configuration, Toolchain)
    case clean(CleanMode)
    case doctor
    case showDependencies(ShowDependenciesMode)
    case fetch
    case update
    case Init(InitMode)
    case usage
    case version
    case generateXcodeproj(String?)
    case dumpPackage(String?)

    init?(argument: String, pop: () -> String?) throws {
        switch argument {
        case "--configuration", "--conf", "-c":
            self = try .build(Configuration(pop()), UserToolchain())
        case "--clean":
            self = try .clean(CleanMode(pop()))
        case "--doctor":
            self = .doctor
        case "--show-dependencies", "-D":
            self = try .showDependencies(ShowDependenciesMode(pop()))
        case "--fetch":
            self = .fetch
        case "--update":
            self = .update
        case "--init", "--initialize":
            self = try .Init(InitMode(pop()))
        case "--help", "--usage", "-h":
            self = .usage
        case "--version":
            self = .version
        case "--generate-xcodeproj", "-X":
            self = .generateXcodeproj(pop())
        case "--dump-package":
            self = .dumpPackage(pop())
        default:
            return nil
        }
    }

    var description: String {
        switch self {
            case .build(let conf, _): return "--configuration=\(conf)"
            case .clean(let mode): return "--clean=\(mode)"
            case .doctor: return "--doctor"
            case .showDependencies: return "--show-dependencies"
            case .generateXcodeproj: return "--generate-xcodeproj"
            case .fetch: return "--fetch"
            case .update: return "--update"
            case .Init(let mode): return "--init=\(mode)"
            case .usage: return "--help"
            case .version: return "--version"
            case .dumpPackage: return "--dump-package"
        }
    }
}

private enum BuildToolFlag: Argument {
    case xcc(String)
    case xld(String)
    case xswiftc(String)
    case buildPath(String)
    case buildTests
    case chdir(String)
    case colorMode(ColorWrap.Mode)
    case ignoreDependencies
    case verbose(Int)
    case xcconfigOverrides(String)

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
        case "-Xcc":
            self = try .xcc(forcePop())
        case "-Xlinker":
            self = try .xld(forcePop())
        case "-Xswiftc":
            self = try .xswiftc(forcePop())
        case "--build-path":
            self = try .buildPath(forcePop())
        case "--build-tests":
            self = .buildTests
        case "--color":
            let rawValue = try forcePop()
            guard let mode = ColorWrap.Mode(rawValue) else  {
                throw OptionParserError.invalidUsage("invalid color mode: \(rawValue)")
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

private class BuildToolOptions: Options {
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
public struct SwiftBuildTool {
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
            case .build(let conf, let toolchain):
                let (rootPackage, externalPackages) = try fetch(opts.path.root)
                try generateVersionData(opts.path.root, rootPackage: rootPackage, externalPackages: externalPackages)
                let (modules, externalModules, products) = try transmute(rootPackage, externalPackages: externalPackages)
                let yaml = try describe(opts, conf, modules, Set(externalModules), products, toolchain: toolchain)
                try build(YAMLPath: yaml, target: opts.buildTests ? "test" : nil)
        
            case .Init(let initMode):
                let initPackage = try InitPackage(mode: initMode)
                try initPackage.writePackageStructure()
                            
            case .update:
                try Utility.removeFileTree(opts.path.Packages)
                fallthrough
                
            case .fetch:
                _ = try fetch(opts.path.root)
        
            case .usage:
                usage()
        
            case .clean(.dist):
                if opts.path.Packages.exists {
                    try Utility.removeFileTree(opts.path.Packages)
                }
                fallthrough
        
            case .clean(.build):
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
    
    private func parse(commandLineArguments args: [String]) throws -> (Mode, BuildToolOptions) {
        let (mode, flags): (Mode?, [BuildToolFlag]) = try Basic.parseOptions(arguments: args)
    
        let opts = BuildToolOptions()
        for flag in flags {
            switch flag {
            case .chdir(let path):
                opts.chdir = path
            case .verbose(let amount):
                opts.verbosity += amount
            case .xcc(let value):
                opts.Xcc.append(value)
            case .xld(let value):
                opts.Xld.append(value)
            case .xswiftc(let value):
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
    
        return try (mode ?? .build(.debug, UserToolchain()), opts)
    }

    private func describe(_ opts: BuildToolOptions, _ conf: Configuration, _ modules: [Module], _ externalModules: Set<Module>, _ products: [Product], toolchain: Toolchain) throws -> String {
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
            self = .debug
        case "release"?:
            self = .release
        case nil:
            throw OptionParserError.expectedAssociatedValue("--configuration")
        default:
            throw OptionParserError.invalidUsage("invalid build configuration: \(rawValue!)")
        }
    }
}

enum CleanMode: CustomStringConvertible {
    case build, dist

    private init(_ rawValue: String?) throws {
        switch rawValue?.lowercased() {
        case nil, "build"?:
            self = .build
        case "dist"?, "distribution"?:
            self = .dist
        default:
            throw OptionParserError.invalidUsage("invalid clean mode: \(rawValue)")
        }
    }

    var description: String {
        switch self {
            case .dist: return "distribution"
            case .build: return "build"
        }
    }
}

private func ==(lhs: Mode, rhs: Mode) -> Bool {
    return lhs.description == rhs.description
}
