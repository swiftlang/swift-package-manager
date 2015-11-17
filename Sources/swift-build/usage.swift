/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct dep.BuildParameters

func usage(print: (String) -> Void = { print($0) }) {
    //.........10.........20.........30.........40.........50.........60.........70..
    print("OVERVIEW: Build sources into binary products")
    print("")
    print("USAGE: swift build [options]")
    print("")
    print("MODES:")
    print("  --configuration <value>  Build with configuration (debug|release) [-c]")
    print("  --clean                  Delete all build intermediaries and products [-k]")
    print("")
    print("OPTIONS:")
    print("  --chdir <value>    Change working directory before any other operation [-C]")
    print("  -v                 Increase verbosity of informational output")
}

enum Mode {
    case Build(BuildParameters.Configuration)
    case Clean
    case Usage
    case Version
}

enum CommandLineError: ErrorType {
    enum UsageMode {
        case Print, Imply
    }
    case InvalidUsage(String, UsageMode)
}

func parse(commandLineArguments args: [String]) throws -> (Mode, chdir: String?, verbosity: Int) {
    var verbosity = 0
    var chdir: String?
    var mode: Mode?

    var cruncher = Cruncher(args: args)

    while cruncher.shouldContinue {
        switch try cruncher.pop() {
        case .Mode(let newMode):
            switch (mode, newMode) {
            case (.Some(let a), let b) where a == b:
                break
            case (.Some(.Usage), let ignoredArgument):
                throw CommandLineError.InvalidUsage("Both --help and \(ignoredArgument) specified", .Print)
            case (.Some(let ignoredArgument), .Usage):
                throw CommandLineError.InvalidUsage("Both --help and \(ignoredArgument) specified", .Print)
            case (.Some(let oldMode), let newMode):
                throw CommandLineError.InvalidUsage("Multiple modes specified: \(oldMode), \(newMode)", .Imply)
            case (.None, .Build):
                switch try cruncher.peek() {
                case .Some(.Name("debug")):
                    mode = .Build(.Debug)
                    cruncher.postPeekPop()
                case .Some(.Name("release")):
                    mode = .Build(.Release)
                    cruncher.postPeekPop()
                case .Some(.Name(let name)):
                    throw CommandLineError.InvalidUsage("Unknown build configuration: \(name)", .Imply)
                default:
                    break
                }
            case (.None, .Usage):
                mode = .Usage
            case (.None, .Clean):
                mode = .Clean
            case (.None, .Version):
                mode = .Version
            }

        case .Switch(.chdir):
            switch try cruncher.peek() {
            case .Some(.Name(let name)):
                chdir = name
                cruncher.postPeekPop()
            default:
                throw CommandLineError.InvalidUsage("Option `--chdir' requires subsequent directory argument", .Imply)
            }

        case .Switch(.v):
            verbosity += 1

        case .Name(let name):
            throw CommandLineError.InvalidUsage("Unknown argument: \(name)", .Imply)
        }
    }

    return (mode ?? .Build(.Debug), chdir, verbosity)
}

extension Mode: CustomStringConvertible {
    var description: String {   //FIXME shouldn't be necessary!
        switch self {
            case .Build(let conf): return "--build \(conf)"
            case .Clean: return "--clean"
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
            case Usage = "--help"
            case Version = "--version"

            init?(rawValue: String) {
                switch rawValue {
                case Build.rawValue, "-c":
                    self = .Build
                case Clean.rawValue, "-k":
                    self = .Clean
                case Usage.rawValue:
                    self = .Usage
                case Version.rawValue:
                    self = .Version
                default:
                    return nil
                }
            }
        }
        enum TheSwitch: String {
            case chdir = "--chdir"
            case v = "-v"
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
        switch arg {
        case "--chdir", "-C":
            return .Switch(.chdir)
        case "-v", "-vv":
            return .Switch(.v)
        default:
            guard !arg.hasPrefix("-") else {
                throw CommandLineError.InvalidUsage("Unknown argument: \(arg)", .Imply)
            }
            return .Name(arg)
        }
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
        case .Version: return rhs == .Version
        case .Usage: return rhs == .Usage
    }
}
