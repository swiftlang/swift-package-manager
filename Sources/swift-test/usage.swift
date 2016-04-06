/*
This source file is part of the Swift.org open source project

Copyright 2015 - 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import enum Multitool.CommandLineError

func usage(print: (String) -> Void = { print($0) }) {
    //.........10.........20.........30.........40.........50.........60.........70..
    print("OVERVIEW: Build and run tests")
    print("")
    print("USAGE: swift test [options]")
    print("")
    print("OPTIONS:")
    print("  --chdir <value>    Change working directory before any other operation [-C]")
    print("  TestModule.TestCase         Run a test case subclass")
    print("  TestModule.TestCase/test1   Run a specific test method")
}

enum Mode {
    case Usage
    case Run(String?)
}

struct Options {
    var chdir: String? = nil
}

func parse(commandLineArguments args: [String]) throws -> (Mode, Options) {
    var mode: Mode?
    var options = Options()
    var args = args

    func checkModes(old: Mode?, new: Mode) throws {
        switch (old, new) {
        case (let a?, let b) where a != b:
            throw CommandLineError.InvalidUsage("Both Help and Run modes specified", .ImplySwiftTest)
        default:
            return
        }
    }

    while !args.isEmpty {
        let argument = args.removeFirst()

        switch argument {
        case "--help", "-h":
            try checkModes(mode, new: .Usage)
            mode = .Usage
        case "--chdir", "-C":
            guard args.count > 0 else {
                throw CommandLineError.InvalidUsage("Option `--chdir' requires subsequent directory argument", .ImplySwiftTest)
            }
            options.chdir = args.removeFirst()
        case argument where argument.hasPrefix("-"):
            throw CommandLineError.InvalidUsage("Unknown argument: \(argument)", .ImplySwiftTest)
        default:
            try checkModes(mode, new: .Run(argument))
            mode = .Run(argument)
        }
    }
    return (mode ?? .Run(nil), options)
}

extension Mode: Equatable {}
func == (lhs: Mode, rhs: Mode) -> Bool {
    switch (lhs, rhs) {
    case (.Usage, .Usage): return true
    case (.Run, .Run): return true
    default: return false
    }
}
