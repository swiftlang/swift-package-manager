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
import struct PackageDescription.Version

import func POSIX.chdir

private enum Mode: Argument, Equatable, CustomStringConvertible {
    case build(Configuration, Toolchain)
    case clean(CleanMode)
    case usage
    case version

    init?(argument: String, pop: () -> String?) throws {
        switch argument {
        case "--configuration", "--config", "-c":
            self = try .build(Configuration(pop()), UserToolchain())
        case "--clean":
            self = try .clean(CleanMode(pop()))
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
            case .build(let conf, _): return "--configuration \(conf)"
            case .clean(let mode): return "--clean \(mode)"
            case .usage: return "--help"
            case .version: return "--version"
        }
    }
}

private enum BuildToolFlag: Argument {
    case xcc(String)
    case xld(String)
    case xswiftc(String)
    case buildPath(AbsolutePath)
    case buildTests
    case chdir(AbsolutePath)
    case colorMode(ColorWrap.Mode)
    case ignoreDependencies
    case verbose(Int)

    init?(argument: String, pop: () -> String?) throws {

        func forcePop() throws -> String {
            guard let value = pop() else { throw OptionParserError.expectedAssociatedValue(argument) }
            return value
        }
        
        switch argument {
        case Flag.chdir, Flag.C:
            self = try .chdir(AbsolutePath(forcePop().abspath))
        case "--verbose", "-v":
            self = .verbose(1)
        case "-Xcc":
            self = try .xcc(forcePop())
        case "-Xlinker":
            self = try .xld(forcePop())
        case "-Xswiftc":
            self = try .xswiftc(forcePop())
        case "--build-path":
            self = try .buildPath(AbsolutePath(forcePop().abspath))
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
        default:
            return nil
        }
    }
}

private class BuildToolOptions: Options {
    var verbosity: Int = 0
    var flags = BuildFlags()
    var buildTests: Bool = false
    var colorMode: ColorWrap.Mode = .Auto
    var ignoreDependencies: Bool = false
}

/// swift-build tool namespace
public struct SwiftBuildTool: SwiftTool {
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
            
            let manifestLoader = ManifestLoader(resources: ToolDefaults())
            func fetch(_ root: AbsolutePath) throws -> (rootPackage: Package, externalPackages:[Package]) {
                let packagesDirectory = PackagesDirectory(root: opts.path.root, manifestLoader: manifestLoader)
                return try packagesDirectory.loadPackages(ignoreDependencies: opts.ignoreDependencies)
            }
        
            switch mode {
            case .build(let conf, let toolchain):
                let (rootPackage, externalPackages) = try fetch(opts.path.root)
                let (modules, externalModules, products) = try transmute(rootPackage, externalPackages: externalPackages)
                let yaml = try describe(opts, conf, modules, Set(externalModules), products, toolchain: toolchain)
                try build(yamlPath: yaml, target: opts.buildTests ? "test" : nil)
        
            case .usage:
                usage()
        
            case .clean(.dist):
                if opts.path.packages.asString.exists {
                    try Utility.removeFileTree(opts.path.packages.asString)
                }
                fallthrough
        
            case .clean(.build):
                let artifacts = ["debug", "release"].map{ AbsolutePath(opts.path.build, $0) }.map{ ($0, AbsolutePath("\($0.asString).yaml")) }
                for (dir, yml) in artifacts {
                    if dir.asString.isDirectory { try Utility.removeFileTree(dir.asString) }
                    if yml.asString.isFile { try Utility.removeFileTree(yml.asString) }
                }
        
                let db = opts.path.build.appending("build.db")
                if db.asString.isFile { try Utility.removeFileTree(db.asString) }
        
                let versionData = opts.path.build.appending("versionData")
                if versionData.asString.isDirectory { try Utility.removeFileTree(versionData.asString) }
        
                if opts.path.build.asString.exists {
                    try Utility.removeFileTree(opts.path.build.asString)
                }
        
            case .version:
                #if HasCustomVersionString
                    print(String(cString: VersionInfo.DisplayString()))
                #else
                    print("Swift Package Manager – Swift 3.0")
                #endif
                
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
        print("  -c, --configuration <value>   Build with configuration (debug|release)")
        print("  --clean <mode>                Delete artifacts (build|dist)")
        print("")
        print("OPTIONS:")
        print("  -C, --chdir <path>       Change working directory before any other operation")
        print("  --build-path <path>      Specify build directory")
        print("  --color <mode>           Specify color mode (auto|always|never)")
        print("  -v, --verbose            Increase verbosity of informational output")
        print("  -Xcc <flag>              Pass flag through to all C compiler invocations")
        print("  -Xlinker <flag>          Pass flag through to all linker invocations")
        print("  -Xswiftc <flag>          Pass flag through to all Swift compiler invocations")
        print("")
        print("NOTE: Use `swift package` to perform other functions on packages")
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
                opts.flags.cCompilerFlags.append(value)
            case .xld(let value):
                opts.flags.linkerFlags.append(value)
            case .xswiftc(let value):
                opts.flags.swiftCompilerFlags.append(value)
            case .buildPath(let path):
                opts.path.build = path
            case .buildTests:
                opts.buildTests = true
            case .colorMode(let mode):
                opts.colorMode = mode
            case .ignoreDependencies:
                opts.ignoreDependencies = true
            }
        }
    
        return try (mode ?? .build(.debug, UserToolchain()), opts)
    }

    private func describe(_ opts: BuildToolOptions, _ conf: Configuration, _ modules: [Module], _ externalModules: Set<Module>, _ products: [Product], toolchain: Toolchain) throws -> AbsolutePath {
        return try Build.describe(opts.path.build, conf, modules, externalModules, products, flags: opts.flags, toolchain: toolchain)
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
        case let value?:
            throw OptionParserError.invalidUsage("invalid clean mode: \(value)")
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
