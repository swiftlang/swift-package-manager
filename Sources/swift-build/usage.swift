/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import protocol Build.Toolchain
import enum Build.Configuration
import OptionsParser
import Multitool

func usage(_ print: (String) -> Void = { print($0) }) {
    //     .........10.........20.........30.........40.........50.........60.........70..
    print("OVERVIEW: Build sources into binary products")
    print("")
    print("USAGE: swift build [mode] [options]")
    print("")
    print("MODES:")
    print("  --configuration <value>        Build with configuration (debug|release) [-c]")
    print("  --clean[=<mode>]               Delete artefacts (build|dist) [-k]")
    print("  --init[=<mode>]                Create a package template (executable|library)")
    print("  --fetch                        Fetch package dependencies")
    print("  --update                       Update package dependencies")
    print("  --generate-xcodeproj[=<path>]  Generates an Xcode project [-X]")
    print("")
    print("OPTIONS:")
    print("  --chdir <path>       Change working directory before any other operation [-C]")
    print("  --build-path <path>  Specify build directory")
    print("  -v[v]                Increase verbosity of informational output")
    print("  -Xcc <flag>          Pass flag through to all C compiler instantiations")
    print("  -Xlinker <flag>      Pass flag through to all linker instantiations")
    print("  -Xswiftc <flag>      Pass flag through to all Swift compiler instantiations")
}

enum Mode: Argument, Equatable, CustomStringConvertible {
    case Build(Configuration, Toolchain)
    case Clean(CleanMode)
    case Doctor
    case Fetch
    case Update
    case Init(InitMode)
    case Usage
    case Version
    case GenerateXcodeproj(String?)

    init?(argument: String, pop: () -> String?) throws {
        switch argument {
        case "--configuration", "--conf":
            self = try .Build(Configuration(pop()), UserToolchain())
        case "--clean":
            self = try .Clean(CleanMode(pop()))
        case "--doctor":
            self = .Doctor
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
        default:
            return nil
        }
    }

    var description: String {
        switch self {
            case .Build(let conf, _): return "--configuration=\(conf)"
            case .Clean(let mode): return "--clean=\(mode)"
            case .Doctor: return "--doctor"
            case .GenerateXcodeproj: return "--generate-xcodeproj"
            case .Fetch: return "--fetch"
            case .Update: return "--update"
            case .Init(let mode): return "--init=\(mode)"
            case .Usage: return "--help"
            case .Version: return "--version"
        }
    }
}

enum Flag: Argument {
    case Xcc(String)
    case Xld(String)
    case chdir(String)
    case Xswiftc(String)
    case verbose(Int)
    case buildPath(String)

    init?(argument: String, pop: () -> String?) throws {

        func forcePop() throws -> String {
            guard let value = pop() else { throw OptionsParser.Error.ExpectedAssociatedValue(argument) }
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
        default:
            return nil
        }
    }
}

class Options: Multitool.Options {
    var verbosity: Int = 0
    var Xcc: [String] = []
    var Xld: [String] = []
    var Xswiftc: [String] = []
}

func parse(commandLineArguments args: [String]) throws -> (Mode, Options) {
    let mode: Mode?
    let flags: [Flag]
    (mode, flags) = try OptionsParser.parse(arguments: args)

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
        }
    }

    return try (mode ?? .Build(.Debug, UserToolchain()), opts)
}


extension Build.Configuration {
    private init(_ rawValue: String?) throws {
        switch rawValue?.lowercased() {
        case "debug"?:
            self = .Debug
        case "release"?:
            self = .Release
        case nil:
            throw OptionsParser.Error.ExpectedAssociatedValue("--configuration")
        default:
            throw OptionsParser.Error.InvalidUsage("invalid build configuration: \(rawValue!)")
        }
    }
}

enum CleanMode: CustomStringConvertible {
    case Build, Dist

    private init(_ rawValue: String?) throws {
        switch rawValue?.lowercased() {
        case nil, "build"?:
            self = Build
        case "dist"?, "distribution"?:
            self = Dist
        default:
            throw OptionsParser.Error.InvalidUsage("invalid clean mode: \(rawValue)")
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
            self = Library
        case nil, "executable"?, "exec"?, "exe"?:
            self = Executable
        default:
            throw OptionsParser.Error.InvalidUsage("invalid initialization mode: \(rawValue)")
        }
    }

    var description: String {
        switch self {
            case .Library: return "library"
            case .Executable: return "executable"
        }
    }
}

func ==(lhs: Mode, rhs: Mode) -> Bool {
    return lhs.description == rhs.description
}
