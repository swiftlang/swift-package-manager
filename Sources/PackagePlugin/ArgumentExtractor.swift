//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A structure that extracts options and flags from a string list representing command-line arguments.
///
/// `ArgumentExtractor` leaves positional arguments, and extracts option arguments and flags.
/// It supports long-form option names with two hyphens (for example, `--verbose`), and treats `--` as an indicator that all remaining arguments are positional.
///
/// > Warning:
/// > `ArgumentExtractor` doesn't detect situations in which positional arguments or optional parameters have the same name as a long option argument.
public struct ArgumentExtractor {
    private var args: [String]
    private let literals: [String]

    /// Initializes an argument with a list of strings from which to extract flags and options.
    ///
    /// If the list contains `--`, `ArgumentExtractor` treats any arguments that follow it as positional arguments.
    ///
    /// - Parameter arguments: The list of command-line arguments.
    public init(_ arguments: [String]) {
        // Split the array on the first `--`, if there is one. Everything after that is a literal.
        let parts = arguments.split(separator: "--", maxSplits: 1, omittingEmptySubsequences: false)
        self.args = Array(parts[0])
        self.literals = Array(parts.count == 2 ? parts[1] : [])
    }

    /// Extracts the value of a named argument from the list of remaining arguments.
    ///
    /// A named argument has one of these two forms:
    /// * `--<name>=<value>`
    /// * `--<name> <value>`
    ///
    /// If this method detects an argument that matches the supplied name, it removes the argument and its value from the list of arguments and returns the value.
    /// The same name can appear in the list of arguments multiple times, and this method returns a list of all matching values.
    ///
    /// - Parameters:
    ///   - name: The option name to extract the value for.
    /// - Returns: An array of values for the named option.
    public mutating func extractOption(named name: String) -> [String] {
        var values: [String] = []
        var idx = 0
        while idx < args.count {
            var arg = args[idx]
            if arg == "--\(name)" {
                args.remove(at: idx)
                if idx < args.count {
                    let val = args[idx]
                    values.append(val)
                    args.remove(at: idx)
                }
            }
            else if arg.starts(with: "--\(name)=") {
                arg.removeFirst(2 + name.count + 1)
                values.append(arg)
                args.remove(at: idx)
            }
            else {
                idx += 1
            }
        }
        return values
    }

    /// Extracts options with the given name from the remaining arguments.
    ///
    /// - Parameter name: The option to search for. The method prefixes it with two hyphens. For example, pass `verbose` to extract the `--verbose` option.
    /// - Returns: The number of matching options in the list of arguments.
    public mutating func extractFlag(named name: String) -> Int {
        var count = 0
        var idx = 0
        while idx < args.count {
            let arg = args[idx]
            if arg == "--\(name)" {
                args.remove(at: idx)
                count += 1
            }
            else {
                idx += 1
            }
        }
        return count
    }

    /// A list of unextracted flags or options.
    ///
    /// A flag or option is any argument that has the prefix `--` (two hyphens).
    public var unextractedOptionsOrFlags: [String] {
        return args.filter{ $0.hasPrefix("--") }
    }

    /// A list of all remaining arguments.
    ///
    /// If the arguments list contains the string `--`, then all arguments after it are included in this list even if they would otherwise match named flags or options.
    public var remainingArguments: [String] {
        return args + literals
    }
}
