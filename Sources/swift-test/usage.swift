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
    print("  TestModule.TestCase         Run a test case subclass")
    print("  TestModule.TestCase/test1   Run a specific test method")
}

enum Mode {
    case Usage
    case Run(String?)
}

func parse(commandLineArguments args: [String]) throws -> Mode {

    if args.count == 0 {
        return .Run(nil)
    }

    guard let argument = args.first where args.count == 1 else {
        throw CommandLineError.InvalidUsage("Unknown arguments: \(args)", .ImplySwiftTest)
    }

    switch argument {
    case "--help", "-h":
        return .Usage
    case argument where argument.hasPrefix("-"):
        throw CommandLineError.InvalidUsage("Unknown argument: \(argument)", .ImplySwiftTest)
    default:
        return .Run(argument)
    }
}
