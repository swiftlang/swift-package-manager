/*
This source file is part of the Swift.org open source project

Copyright 2015 - 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Multitool

func usage(print: (String) -> Void = { print($0) }) {
    //.........10.........20.........30.........40.........50.........60.........70..
    print("OVERVIEW: Build and run tests")
    print("")
    print("USAGE: swift test [specifier] [options]")
    print("")
    print("SPECIFIER:")
    print("  TestModule.TestCase         Run a test case subclass")
    print("  TestModule.TestCase/test1   Run a specific test method")
    print("")
    print("OPTIONS:")
    print("  --chdir         Change working directory before any other operation [-C]")
}

enum Mode: ModeArgument {
    case Usage
    case Run(String?)

    init?(argument: String, pop: () -> String?) throws {
        switch argument {
        case "--help", "--usage", "-h":
            self = .Usage
        default:
            return nil
        }
    }

    var description: String {
        switch self {
        case .Usage:
            return "--help"
        case .Run(let specifier):
            return specifier ?? ""
        }
    }
}

func ==(lhs: Mode, rhs: Mode) -> Bool {
    return lhs.description == rhs.description
}

enum Flag: Argument {
    case chdir(String)

    init?(argument: String, pop: () -> String?) throws {
        switch argument {
        case "--chdir", "-C":
            guard let path = pop() else { throw Multitool.Error.ExpectedAssociatedValue(argument) }
            self = .chdir(path)
        default:
            return nil
        }
    }
}

struct Options {
    var chdir: String? = nil
}

func parse(commandLineArguments args: [String]) throws -> (Mode, Options) {
    let mode: Mode?
    let flags: [Flag]
    (mode, flags) = try parse(arguments: args)

    var opts = Options()
    for flag in flags {
        switch flag {
        case .chdir(let path):
            opts.chdir = path
        }
    }

    return (mode ?? .Run(nil), opts)
}
