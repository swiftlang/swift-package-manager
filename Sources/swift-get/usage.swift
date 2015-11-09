/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

func usage(print: (String) -> Void = { print($0) }) {
          //.........10.........20.........30.........40.........50.........60.........70..
    print("OVERVIEW: Fetch, update and manage remote packages")
    print("")
    print("USAGE: swift get [options] [<urls>]")
    print("")
    print("OPTIONS:")
    print("  --chdir <value>    Change working directory before any other operation [-C]")
    print("  -v                 Increase verbosity of informational output")
}

enum Mode {
    case Usage
    case Version
    case Install(urls: [String])

    init?(rawValue: String) {
        switch rawValue {
            case "--help": self = .Usage
            case "--version": self = .Version
        default:
            return nil
        }
    }
}

func ==(lhs: Mode, rhs: Mode) -> Bool {
    switch (lhs, rhs) {
    case (.Usage, .Usage), (.Version, .Version):
        return true
    default:
        return false
    }
}

enum CommandLineError: ErrorType {
    enum UsageMode {
        case Print, Imply
    }

    case InvalidUsage(String, UsageMode)
}

func parse(commandLineArguments args: [String]) throws -> (Mode, chdir: String?, verbosity: Int) {

    guard args.count > 0 else {
        throw CommandLineError.InvalidUsage("Please specify a package URL", .Print)
    }

    var verbosity = 0
    var chdir: String?
    var names = [String]()
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
            if let newMode = Mode(rawValue: arg) {
                guard mode == nil else {
                    if mode! == newMode {
                        continue
                    } else {
                        throw CommandLineError.InvalidUsage("Multiple modes specified", .Print)
                    }
                }
                mode = newMode
            } else if arg.hasPrefix("-") {
                throw CommandLineError.InvalidUsage("Unknown argument: \(arg)", .Imply)
            } else {
                names.append(arg)
            }
        }
    }

    if mode == nil {
        guard names.count > 0 else {
            throw CommandLineError.InvalidUsage("Please specify a package URL", .Imply)
        }
        mode = .Install(urls: names)
    }

    return (mode!, chdir, verbosity)
}
