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

/// A rudimentary helper for extracting options and flags from a list of strings that represents command line arguments.
///
/// Create the extractor with the full command line arguments provided, then extract all known
/// options and flags, leaving the positional arguments.
///
/// This does not handle the case where positional arguments (or option argument values) have the same
/// name as an option or a flag. It only handles the long form of options, not short forms, for example: `--<name>`.
/// It respects an argument that consists of two hyphens (`--`) as an indication that all remaining arguments are positional.
public struct ArgumentExtractor {
    private var args: [String]
    private let literals: [String]

    /// Creates an argument extractor with a list of strings from which to extract flags and options.
    ///
    /// If the list contains `--`, any arguments that follow it are considered to be positional arguments.
    public init(_ arguments: [String]) {
        // Split the array on the first `--`, if there is one. Everything after that is a literal.
        let parts = arguments.split(separator: "--", maxSplits: 1, omittingEmptySubsequences: false)
        self.args = Array(parts[0])
        self.literals = Array(parts.count == 2 ? parts[1] : [])
    }

    /// Extracts options of the form `--<name> <value>` or `--<name>=<value>` from the remaining arguments and returns the extracted values.
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

    /// Extracts flags of the form `--<name>` from the remaining arguments, and returns the count.
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

    /// Returns any unextracted flags or options.
    ///
    /// This is based strictly on whether remaining arguments have a "--" prefix.
    public var unextractedOptionsOrFlags: [String] {
        return args.filter{ $0.hasPrefix("--") }
    }

    /// Returns all remaining arguments.
    ///
    /// The returned values include any positional arguments after the first `--`, if there is one.
    public var remainingArguments: [String] {
        return args + literals
    }
}
