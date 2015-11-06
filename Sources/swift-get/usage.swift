/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import sys

func usage(print: (String) -> Void = { Swift.print($0) }) {

          //.........10.........20.........30.........40.........50.........60.........70..
    print("Usage:")
    print("    swift get https://github.com/foo/bar     # => ./foo-x.y.z")
}

enum CommandLine {
    case Usage
    case Version
    case Install(urls: [String])

    static func parse(args: [String]) throws -> CommandLine {

        guard args.count > 0 else { throw Error.InvalidUsage(hint: nil) }

        var cmds = [InstallCommand()]
        var verbosity = 0
        let (names, flags) = partition(args)

        // we do not have need for stdin and so we reject `-` out of hand
        guard !flags.contains("-") else { throw Error.InvalidUsage(hint: "Invalid argument: -") }

        for flag in flags {
            switch flag {
            case "--help", "-h":
                return .Usage
            case "--version", "-V":
                return .Version
            case "-v":
                verbosity += 1
            default:
                for (index, cmd) in cmds.enumerate() {
                    if !cmd.append(flag) {
                        cmds.removeAtIndex(index)
                    }
                }
                guard cmds.count > 0 else {
                    throw Error.InvalidUsage(hint: nil)
                }
            }
        }

        sys.verbosity = Verbosity(rawValue: verbosity)

        guard cmds.count == 1 else {
            throw Error.InvalidUsage(hint: nil)
        }

        return try cmds[0].transform(names: names)
    }
}

extension CommandLine {
    static private func partition(args: [String]) -> ([String], [String]) {
        var names: [String] = []
        var flags: [String] = []
        for (index, arg) in args.enumerate() {
            guard arg != "--" else {
                names += args.skip(index)
                break
            }

            if arg.hasPrefix("--") {
                flags.append(arg)
            } else if arg == "-" {
                flags.append("-")  // special case the “stdin” filename
            } else if arg.hasPrefix("-") {
                for c in arg.characters.dropFirst() {
                    flags.append("-\(c)")
                }
            } else {
                names.append(arg)
            }
        }
        return (names, flags)
    }
}

private protocol Command {
    /**
     Returns false if the new flag would make this command invalid.
     If false is returned, you should remove this command from the 
     running.
    */
    func append(flag: String) -> Bool

    /**
     Convert this command into its corresponding CommandLine enum value,
     based on the current flags and the provided names.
    */
    func transform(names names: [String]) throws -> CommandLine
}

private class InstallCommand: Command {
    var global = false
    var force = false

    func append(flag: String) -> Bool {
        switch flag {
        case "--global", "-g":
            global = true
            return true
        case "--force", "-f":
            force = true
            return true
        default:
            return false
        }
    }

    func transform(names names: [String]) throws -> CommandLine {
        return .Install(urls: names)
    }
}

extension Array {
    func skip(after: Int) -> ArraySlice<Element> {
        guard after < count else { return ArraySlice() }
        return self[after..<count]
    }
}
