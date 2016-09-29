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

import enum Build.Configuration
import protocol Build.Toolchain

import func POSIX.chdir

public enum BuildToolMode: Argument, Equatable, CustomStringConvertible {
    case build(Configuration, Toolchain)
    case clean(CleanMode)
    case usage
    case version

    public init?(argument: String, pop: @escaping () -> String?) throws {
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

    public var description: String {
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
    case enableNewResolver
    case buildTests
    case chdir(AbsolutePath)
    case colorMode(ColorWrap.Mode)
    case verbose(Int)

    init?(argument: String, pop: @escaping () -> String?) throws {
        func forcePop() throws -> String {
            guard let value = pop() else { throw OptionParserError.expectedAssociatedValue(argument) }
            return value
        }
        
        switch argument {
        case Flag.chdir, Flag.C:
            self = try .chdir(AbsolutePath(forcePop(), relativeTo: currentWorkingDirectory))
        case "--verbose", "-v":
            self = .verbose(1)
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
        case "--build-tests":
            self = .buildTests
        case "--color":
            let rawValue = try forcePop()
            guard let mode = ColorWrap.Mode(rawValue) else  {
                throw OptionParserError.invalidUsage("invalid color mode: \(rawValue)")
            }
            self = .colorMode(mode)
        default:
            return nil
        }
    }
}

public class BuildToolOptions: Options {
    var flags = BuildFlags()
    var buildTests: Bool = false
}

/// swift-build tool namespace
public class SwiftBuildTool: SwiftTool<BuildToolMode, BuildToolOptions> {

    override func runImpl() throws {
        switch mode {
        case .usage:
            SwiftBuildTool.usage()

        case .version:
            print(Versioning.currentVersion.completeDisplayString)

        case .build(let conf, let toolchain):
            #if os(Linux)
            // Emit warning if clang is older than version 3.6 on Linux.
            // See: <rdar://problem/28108951> SR-2299 Swift isn't using Gold by default on stock 14.04.
            checkClangVersion()
            #endif
            let graph = try loadPackage()
            let yaml = try describe(buildPath, conf, graph, flags: options.flags, toolchain: toolchain)
            try build(yamlPath: yaml, target: options.buildTests ? "test" : nil)

        case .clean(.dist):
            print("warning: This is deprecated and will be removed in Swift 4. Use 'swift package reset' instead.")
            if options.enableNewResolver {
                try getActiveWorkspace().reset()
            } else {
                if try exists(getCheckoutsDirectory()) {
                    try removeFileTree(getCheckoutsDirectory())
                }
                fallthrough
            }
        case .clean(.build):
            if options.enableNewResolver {
                try getActiveWorkspace().clean()
            } else {
                // FIXME: This test is lame, `removeFileTree` shouldn't error on this.
                if exists(buildPath) {
                    try removeFileTree(buildPath)
                }
            }
        }
    }

    override class func usage(_ print: (String) -> Void = { print($0) }) {
        //     .........10.........20.........30.........40.........50.........60.........70..
        print("OVERVIEW: Build sources into binary products")
        print("")
        print("USAGE: swift build [mode] [options]")
        print("")
        print("MODES:")
        print("  -c, --configuration <value>   Build with configuration (debug|release) [default: debug]")
        print("  --clean [<mode>]              Delete artifacts (build|dist) [default: build]")
        print("")
        print("OPTIONS:")
        print("  -C, --chdir <path>       Change working directory before any other operation")
        print("  --build-path <path>      Specify build/cache directory [default: ./.build]")
        print("  --color <mode>           Specify color mode (auto|always|never) [default: auto]")
        print("  -v, --verbose            Increase verbosity of informational output")
        print("  -Xcc <flag>              Pass flag through to all C compiler invocations")
        print("  -Xlinker <flag>          Pass flag through to all linker invocations")
        print("  -Xswiftc <flag>          Pass flag through to all Swift compiler invocations")
        print("")
        print("NOTE: Use `swift package` to perform other functions on packages")
    }
    
    override class func parse(commandLineArguments args: [String]) throws -> (BuildToolMode, BuildToolOptions) {
        let (mode, flags): (BuildToolMode?, [BuildToolFlag]) = try Basic.parseOptions(arguments: args)
    
        let options = BuildToolOptions()
        for flag in flags {
            switch flag {
            case .chdir(let path):
                options.chdir = path
            case .verbose(let amount):
                options.verbosity += amount
            case .xcc(let value):
                options.flags.cCompilerFlags.append(value)
            case .xld(let value):
                options.flags.linkerFlags.append(value)
            case .xswiftc(let value):
                options.flags.swiftCompilerFlags.append(value)
            case .buildPath(let path):
                options.buildPath = path
            case .enableNewResolver:
                options.enableNewResolver = true
            case .buildTests:
                options.buildTests = true
            case .colorMode(let mode):
                options.colorMode = mode
            }
        }
    
        return try (mode ?? .build(.debug, UserToolchain()), options)
    }

    private func checkClangVersion() {
        // We only care about this on Ubuntu 14.04
        guard let uname = try? popen(["lsb_release", "-r"]).chomp(),
              uname.hasSuffix("14.04"),
              let clangVersionOutput = try? popen(["clang", "--version"]).chomp(),
              let clang = getClangVersion(versionOutput: clangVersionOutput) else {
            return
        }

        if clang.major <= 3 && clang.minor < 6 {
            print("warning: minimum recommended clang is version 3.6, otherwise you may encounter linker errors.")
        }
    }
}

extension Build.Configuration {
    fileprivate init(_ rawValue: String?) throws {
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

public enum CleanMode: CustomStringConvertible {
    case build, dist

    public init(_ rawValue: String?) throws {
        switch rawValue?.lowercased() {
        case nil, "build"?:
            self = .build
        case "dist"?, "distribution"?:
            self = .dist
        case let value?:
            throw OptionParserError.invalidUsage("invalid clean mode: \(value)")
        }
    }

    public var description: String {
        switch self {
            case .dist: return "distribution"
            case .build: return "build"
        }
    }
}

public func ==(lhs: BuildToolMode, rhs: BuildToolMode) -> Bool {
    return lhs.description == rhs.description
}
