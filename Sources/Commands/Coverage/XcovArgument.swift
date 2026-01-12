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

/// A single -Xcov argument that parses the format `[<coverage-format>=]<value>` syntax
package struct XcovArgument: ExpressibleByArgument {
    package let format: CoverageFormat?
    package let value: String

    package init?(argument: String) {
        if let equalsIndex = argument.firstIndex(of: "=") {
            let formatString = String(argument[..<equalsIndex])
            let valueString = String(argument[argument.index(after: equalsIndex)...])

            // Try to parse the format
            if let coverageFormat = CoverageFormat(rawValue: formatString) {
                self.format = coverageFormat
                self.value = valueString
            } else {
                // Unsupported format - treat entire string as value
                self.format = nil
                self.value = argument
            }
        } else {
            // No format specified - treat as plain value
            self.format = nil
            self.value = argument
        }
    }

    /// Returns arguments for the specified coverage format
    /// - If this argument has a matching format, returns the value
    /// - If this argument has no format or unsupported format, returns the value for any format
    /// - Otherwise returns empty array
    package func getArguments(for coverageFormat: CoverageFormat) -> [String] {
        if let format = self.format {
            // Has a supported format - only return if it matches
            return format == coverageFormat ? [value] : []
        } else {
            // No format or unsupported format - return for any query
            return [value]
        }
    }
}

/// Collection of multiple -Xcov arguments that preserves order and handles filtering
package struct XcovArgumentCollection {
    private let arguments: [XcovArgument]

    package init(_ arguments: [XcovArgument]) {
        self.arguments = arguments
    }

    /// Returns all argument values for the specified coverage format, preserving command-line order
    /// Includes values from:
    /// - Arguments with matching format
    /// - Arguments with no format specified
    /// - Arguments with unsupported formats
    package func getArguments(for coverageFormat: CoverageFormat) -> [String] {
        return arguments.flatMap { $0.getArguments(for: coverageFormat) }
    }
}
