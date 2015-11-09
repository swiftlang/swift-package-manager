/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

func usage(print: (String) -> Void = { print($0) }) {
    //.........10.........20.........30.........40.........50.........60.........70..
    print("OVERVIEW: Build sources into binary products")
    print("")
    print("USAGE: swift build [options]")
    print("")
    print("MODES:")
    print("  --build            Default mode, if no mode is specified --build is run")
    print("  --clean            Delete all build intermediaries and products")
    print("")
    print("OPTIONS:")
    print("  --chdir <value>    Change working directory before any other operation [-C]")
    print("  -v                 Increase verbosity of informational output")
}

enum Mode: String {
    case Build = "--build"
    case Clean = "--clean"
    case Usage = "--help"
    case Version = "--version"
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

    var it = args.generate()
    while let arg = it.next() {
        switch arg {
        case "--chdir", "-C":
            guard let dir = it.next() else {
                throw CommandLineError.InvalidUsage("Option `\(arg)' requires subsequent directory argument", .Imply)
            }
            chdir = dir
        case "-vv":
            verbosity += 2
        case "-v":
            verbosity += 1
        default:
            let newMode = Mode(rawValue: arg)

            switch (mode, newMode) {
            case (.Some(let a), .Some(let b)) where a == b:
                continue
            case (.Some(.Usage), .None):
                throw CommandLineError.InvalidUsage("Unknown argument: \(arg)", .Print)
            case (.Some(.Usage), .Some(let ignoredArgument)):
                throw CommandLineError.InvalidUsage("Both --help and \(ignoredArgument) specified", .Print)
            case (.Some(let ignoredArgument), .Some(.Usage)):
                throw CommandLineError.InvalidUsage("Both --help and \(ignoredArgument) specified", .Print)
            case (.Some(let oldMode), .Some(let newMode)):
                throw CommandLineError.InvalidUsage("Multiple modes specified: \(oldMode), \(newMode)", .Imply)
            case (_, .None):
                throw CommandLineError.InvalidUsage("Unknown argument: \(arg)", .Imply)
            case (.None, .Some):
                mode = newMode
            }
        }
    }

    return (mode ?? .Build, chdir, verbosity)
}



extension Mode: CustomStringConvertible {
    var description: String {   //FIXME shouldn't be necessary!
        switch self {
        case .Build: return "--build"
        case .Clean: return "--clean"
        case .Usage: return "--help"
        case .Version: return "--version"
        }
    }
}
