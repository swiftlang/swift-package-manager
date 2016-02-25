/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import enum Build.Configuration
import Multitool

func usage(print: (String) -> Void = { print($0) }) {
         //.........10.........20.........30.........40.........50.........60.........70..
    print("OVERVIEW: Build sources into binary products")
    print("")
    print("USAGE: swift build [options]")
    print("")
    print("MODES:")
    print("  --configuration <value>  Build with configuration (debug|release) [-c]")
    print("  --clean[=<mode>]         Delete artefacts (build|dist) [-k]")
    print("  --init                   Creates a new Swift project")
    print("  --fetch                  Fetch package dependencies")
    print("")
    print("OPTIONS:")
    print("  --chdir <value>    Change working directory before any other operation [-C]")
    print("  -v[v]              Increase verbosity of informational output")
    print("  -Xcc <flag>        Pass flag through to all C compiler instantiations")
    print("  -Xlinker <flag>    Pass flag through to all linker instantiations")
    print("  -Xswiftc <flag>    Pass flag through to all Swift compiler instantiations")
}

enum CleanMode: String {
    case Build = "build"
    case Dist  = "dist"
}

enum Mode {
    case Build(Configuration)
    case Clean(CleanMode)
    case Fetch
    case Init
    case Usage
    case Version
    case Dump
}

struct Options {
    var chdir: String? = nil
    var verbosity: Int = 0
    var Xcc: [String] = []
    var Xld: [String] = []
    var Xswiftc: [String] = []
}

func parse(commandLineArguments args: [String]) throws -> (Mode, Options) {
    var opts = Options()
    var mode: Mode?

    //TODO refactor
    var skipNext = false
    var cruncher = Cruncher(args: args.flatMap { arg -> [String] in

        if skipNext {
            skipNext = false
            return [arg]
        }

        if "-Xcc" == arg || "-Xlinker" == arg || "-Xswiftc" == arg {
            skipNext = true
            return [arg]
        }

        // split short form arguments so Cruncher can work with them,
        // eg. -vv is split into -v -v

        if arg.hasPrefix("-") && !arg.hasPrefix("--") {
            return arg.characters.dropFirst().map{ "-" + String($0) }
        }

        // split applicative arguments so Cruncher can work with them,
        // eg. --mode=value splits into --mode =value
        let argParts = arg.characters.split{ $0 == "=" }.map{ String($0) }
        if argParts.count > 1 {
            return argParts
        }

        return [arg]
    })

    while cruncher.shouldContinue {
        switch try cruncher.pop() {
        case .Mode(let newMode):
            switch (mode, newMode) {
            case (let a?, let b) where a == b:
                break
            case (.Usage?, let ignoredArgument):
                throw CommandLineError.InvalidUsage("Both --help and \(ignoredArgument) specified", .Print)
            case (let ignoredArgument?, .Usage):
                throw CommandLineError.InvalidUsage("Both --help and \(ignoredArgument) specified", .Print)
            case (let oldMode?, let newMode):
                throw CommandLineError.InvalidUsage("Multiple modes specified: \(oldMode), \(newMode)", .Imply)
            case (nil, .Build):
                switch try cruncher.peek() {
                case .Name("debug")?:
                    mode = .Build(.Debug)
                    cruncher.postPeekPop()
                case .Name("release")?:
                    mode = .Build(.Release)
                    cruncher.postPeekPop()
                case .Name(let name)?:
                    throw CommandLineError.InvalidUsage("Unknown build configuration: \(name)", .Imply)
                default:
                    break
                }
            case (nil, .Usage):
                mode = .Usage
            case (nil, .Init):
                mode = .Init
            case (nil, .Clean):
                mode = .Clean(.Build)
                switch try cruncher.peek() {
                case .Name("build")?:
                    cruncher.postPeekPop()
                case .Name("dist")?:
                    mode = .Clean(.Dist)
                    cruncher.postPeekPop()
                case .Name(let name)?:
                    throw CommandLineError.InvalidUsage("Unknown clean mode: \(name)", .Imply)
                default:
                    break
                }
            case (nil, .Version):
                mode = .Version
            case (nil, .Fetch):
                mode = .Fetch
            case (nil, .Dump):
                mode = .Dump
            }

        case .Switch(.Chdir):
            switch try cruncher.peek() {
            case .Name(let name)?:
                cruncher.postPeekPop()
                opts.chdir = name
            default:
                throw CommandLineError.InvalidUsage("Option `--chdir' requires subsequent directory argument", .Imply)
            }

        case .Switch(.Verbose):
            opts.verbosity += 1

        case .Name(let name):
            throw CommandLineError.InvalidUsage("Unknown argument: \(name)", .Imply)

        case .Switch(.Xcc):
            opts.Xcc.append(try cruncher.rawPop())

        case .Switch(.Xlinker):
            opts.Xld.append(try cruncher.rawPop())

        case .Switch(.Xswiftc):
            opts.Xswiftc.append(try cruncher.rawPop())
        }
    }

    return (mode ?? .Build(.Debug), opts)
}

extension CleanMode: CustomStringConvertible {
    var description: String {
        return "=\(self.rawValue)"
    }
}

extension Mode: CustomStringConvertible {
    var description: String {   //FIXME shouldn't be necessary!
        switch self {
            case .Build(let conf): return "--build \(conf)"
            case .Clean(let cleanMode): return "--clean=\(cleanMode)"
            case .Dump: return "--dump"
            case .Fetch: return "--fetch"
            case .Init: return "--init"
            case .Usage: return "--help"
            case .Version: return "--version"
        }
    }
}

private struct Cruncher {

    enum Crunch {
        enum TheMode: String {
            case Build = "--configuration"
            case Clean = "--clean"
            case Dump = "--dump"
            case Fetch = "--fetch"
            case Init = "--init"
            case Usage = "--help"
            case Version = "--version"

            init?(rawValue: String) {
                switch rawValue {
                case Build.rawValue, "-c":
                    self = .Build
                case Clean.rawValue, "-k":
                    self = .Clean
                case Dump.rawValue:
                    self =  .Dump
                case Fetch.rawValue:
                    self = .Fetch
                case Init.rawValue:
                    self = .Init
                case Usage.rawValue, "-h":
                    self = .Usage
                case Version.rawValue:
                    self = .Version
                default:
                    return nil
                }
            }
        }
        enum TheSwitch: String {
            case Chdir = "--chdir"
            case Verbose = "--verbose"
            case Xcc = "-Xcc"
            case Xlinker = "-Xlinker"
            case Xswiftc = "-Xswiftc"
            
            init?(rawValue: String) {
                switch rawValue {
                case Chdir.rawValue, "-C":
                    self = .Chdir
                case Verbose.rawValue, "-v":
                    self = .Verbose
                case Xcc.rawValue:
                    self = .Xcc
                case Xlinker.rawValue:
                    self = .Xlinker
                case Xswiftc.rawValue:
                    self = .Xswiftc
                default:
                    return nil
                }
            }
        }

        case Mode(TheMode)
        case Switch(TheSwitch)
        case Name(String)
    }

    var args: [String]

    var shouldContinue: Bool {
        return !args.isEmpty
    }

    func parse(arg: String) throws -> Crunch {
        if let mode = Crunch.TheMode(rawValue: arg) {
            return .Mode(mode)
        }
        
        if let theSwitch = Crunch.TheSwitch(rawValue: arg) {
            return .Switch(theSwitch)
        }
        
        guard !arg.hasPrefix("-") else {
            throw CommandLineError.InvalidUsage("unknown argument: \(arg)", .Imply)
        }

        return .Name(arg)
    }

    mutating func rawPop() throws -> String {
        guard args.count > 0 else { throw CommandLineError.InvalidUsage("expected argument", .Imply) }
        return args.removeFirst()
    }

    mutating func pop() throws -> Crunch {
        return try parse(args.removeFirst())
    }

    mutating func postPeekPop() {
        args.removeFirst()
    }

    func peek() throws -> Crunch? {
        guard let arg = args.first else {
            return nil
        }
        return try parse(arg)
    }
}

private func ==(lhs: Mode, rhs: Cruncher.Crunch.TheMode) -> Bool {
    switch lhs {
        case .Build: return rhs == .Build
        case .Clean: return rhs == .Clean
        case .Dump: return rhs == .Dump
        case .Fetch: return rhs == .Fetch
        case .Init: return rhs == .Init
        case .Version: return rhs == .Version
        case .Usage: return rhs == .Usage
    }
}
