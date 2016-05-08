/*
This source file is part of the Swift.org open source project

Copyright 2015 - 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import OptionsParser
import Multitool

func usage(_ print: (String) -> Void = { print($0) }) {
    //     .........10.........20.........30.........40.........50.........60.........70..
    print("OVERVIEW: Build and run tests")
    print("")
    print("USAGE: swift test [specifier] [options]")
    print("")
    print("SPECIFIER:")
    print("  -s TestModule.TestCase         Run a test case subclass")
    print("  -s TestModule.TestCase/test1   Run a specific test method")
    print("")
    print("OPTIONS:")
    print("  --chdir              Change working directory before any other operation [-C]")
    print("  --build-path <path>  Specify build directory")
}

enum Mode: Argument, Equatable, CustomStringConvertible {
    case Usage
    case Run(String?)

    init?(argument: String, pop: () -> String?) throws {
        switch argument {
        case "--help", "--usage", "-h":
            self = .Usage
        case "-s":
            guard let specifier = pop() else { throw OptionsParser.Error.ExpectedAssociatedValue(argument) }
            self = .Run(specifier)
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
    case buildPath(String)

    init?(argument: String, pop: () -> String?) throws {
        func forcePop() throws -> String {
            guard let popped = pop() else { throw OptionsParser.Error.ExpectedAssociatedValue(argument) }
            return popped
        }
        switch argument {
        case "--chdir", "-C":
            self = .chdir(try forcePop())
        case "--build-path":
            self = .buildPath(try forcePop())
        default:
            return nil
        }
    }
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
        case .buildPath(let path):
            opts.path.build = path
        }
    }

    return (mode ?? .Run(nil), opts)
}
