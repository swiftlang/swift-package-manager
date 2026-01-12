//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2015-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser

// MARK: - XcovArgument

/// A single `-Xcov` argument that parses coverage-specific options with optional format specification.
///
/// The `-Xcov` argument supports the syntax `[<coverage-format>=]<value>` where:
/// - `<coverage-format>` is an optional format specifier matching a `CoverageFormat` case
/// - `<value>` is the argument value to pass to the coverage tool
///
/// ## Examples:
/// - `html=/custom/path` - Specifies a custom output path for HTML format
/// - `json=--exclude-paths` - Adds an exclusion flag for JSON format
/// - `--verbose` - Generic flag applied to all coverage formats
///
/// ## Behavior:
/// - If the format is specified and supported, the argument is only returned for that format
/// - If the format is unsupported or not specified, the argument is returned for all formats
/// - This allows generic arguments to be applied universally while format-specific ones are targeted
package struct XcovArgument: ExpressibleByArgument {
    /// The coverage format this argument is specific to, or nil if it applies to all formats
    package let format: CoverageFormat?

    /// The argument value to pass to the coverage tool
    package let value: String

    /// Creates an XcovArgument from a command-line string.
    ///
    /// - Parameter argument: The raw argument string from the command line
    /// - Returns: A parsed XcovArgument, or nil if parsing fails (which shouldn't happen in practice)
    package init?(argument: String) {
        if let equalsIndex = argument.firstIndex(of: "=") {
            let formatString = String(argument[..<equalsIndex])
            let valueString = String(argument[argument.index(after: equalsIndex)...])

            if let coverageFormat = CoverageFormat(rawValue: formatString) {
                // Recognized format - argument is format-specific
                self.format = coverageFormat
                self.value = valueString
            } else {
                // Unrecognized format - treat entire string as generic value
                self.format = nil
                self.value = argument
            }
        } else {
            // No equals sign - treat as generic value
            self.format = nil
            self.value = argument
        }
    }

    /// Returns the argument value if it should be applied to the specified coverage format.
    ///
    /// - Parameter coverageFormat: The coverage format to check compatibility with
    /// - Returns: An array containing the value if applicable, or empty array otherwise
    ///
    /// ## Logic:
    /// - If this argument has a specific format, return value only if formats match
    /// - If this argument has no format (generic), return value for any format
    /// - If this argument has an unsupported format, return value for any format
    package func getArguments(for coverageFormat: CoverageFormat) -> [String] {
        if let format = self.format {
            // Format-specific argument - only return if it matches the requested format
            return format == coverageFormat ? [value] : []
        } else {
            // Generic argument - return for any format
            return [value]
        }
    }
}

// MARK: - XcovArgumentCollection

/// A collection of `-Xcov` arguments that maintains command-line order and provides format filtering.
///
/// This collection preserves the order in which `-Xcov` arguments were specified on the command line,
/// ensuring that when arguments are retrieved for a specific format, they maintain their original
/// ordering which may be important for some coverage tools.
package struct XcovArgumentCollection {
    /// The underlying array of XcovArgument instances, in command-line order
    package let arguments: [XcovArgument]

    /// Creates a collection from an array of XcovArgument instances.
    ///
    /// - Parameter arguments: The arguments to include in the collection
    package init(_ arguments: [XcovArgument]) {
        self.arguments = arguments
    }

    /// Returns all argument values applicable to the specified coverage format.
    ///
    /// - Parameter coverageFormat: The coverage format to get arguments for
    /// - Returns: An array of argument values in command-line order
    ///
    /// The returned arguments include:
    /// - Arguments with matching format specification
    /// - Arguments with no format specified (generic arguments)
    /// - Arguments with unsupported format specifications (treated as generic)
    package func getArguments(for coverageFormat: CoverageFormat) -> [String] {
        return arguments.flatMap { $0.getArguments(for: coverageFormat) }
    }
}
