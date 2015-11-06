/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

enum CommandLine {
    case Build(chdir: String?)
    case Usage
    case Clean

    enum Error: ErrorType {
        case InvalidUsage(message: String)
    }

    static func parse(args: [String] = Array(Process.arguments.dropFirst(1))) throws -> CommandLine {
        if args == ["--help"] || args == ["-h"] {
            return .Usage
        }

        if args == ["--clean"] {
            return .Clean
        }

        if let index = args.indexOf("--chdir") { //TODO and -C //TODO usage docs
            guard args.count - 1 > index else {
                throw Error.InvalidUsage(message: "--chdir must be followed by a named argument")
            }
            return .Build(chdir: args[index.successor()])
        }
        return .Build(chdir: nil)
    }
}
