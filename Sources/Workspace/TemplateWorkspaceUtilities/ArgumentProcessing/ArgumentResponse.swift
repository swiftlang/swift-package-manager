//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParserToolInfo

/// Represents the user-provided or computed response for a command-line argument.
///
/// `ArgumentResponse` encapsulates an argument (`ArgumentInfoV0`) along with its values,
/// tracks whether the argument has been explicitly unset, and provides the logic
/// to convert the response into command-line fragments suitable for invoking a CLI tool.
public struct ArgumentResponse {
    /// The metadata describing the argument.
    public let argument: ArgumentInfoV0

    ///  Values provided for this argument
    public let values: [String]

    /// Indicates whether this argument was explicitly unset by the user.
    public let isExplicitlyUnset: Bool

    /// Converts the argument response into command-line fragments suitable for CLI invocation.
    ///
    /// - Returns: An array of strings representing the command-line equivalent of this argument.
    ///            Returns an empty array if the argument is explicitly unset.
    public var commandLineFragments: [String] {
        guard !self.isExplicitlyUnset else { return [] }

        switch self.argument.kind {
        case .flag:
            // For flags, only include if true
            guard self.values.first == "true" else { return [] }
            return [self.formatArgumentName()]

        case .option:
            // For options, include name-value pairs
            return self.values.flatMap { [self.formatArgumentName(), $0] }

        case .positional:
            // Positional arguments are just the values
            return self.values
        }
    }

    /// Creates a new `ArgumentResponse`.
    ///
    /// - Parameters:
    ///   - argument: The metadata describing the argument.
    ///   - values: The values provided for this argument.
    ///   - isExplicitlyUnset: Whether the argument was explicitly unset. Defaults to `false`.
    public init(
        argument: ArgumentInfoV0,
        values: [String],
        isExplicitlyUnset:
        Bool = false
    ) {
        self.argument = argument
        self.values = values
        self.isExplicitlyUnset = isExplicitlyUnset
    }

    /// Formats the argument name according to the preferred style.
    ///
    /// Respects the argument's preferred name (`short`, `long`, or `longWithSingleDash`).
    /// Falls back to the first available name, or to the `valueName` if no names are defined.
    ///
    /// - Returns: A formatted string suitable for the command line (e.g., `-f`, `--file`).
    private func formatArgumentName() -> String {
        // Use preferred name format (respects short vs long preference)
        if let preferredName = argument.preferredName {
            switch preferredName.kind {
            case .short:
                return "-\(preferredName.name)"
            case .long:
                return "--\(preferredName.name)"
            case .longWithSingleDash:
                return "-\(preferredName.name)"
            }
        }

        // Fallback: use first available name
        if let firstName = argument.names?.first {
            switch firstName.kind {
            case .short:
                return "-\(firstName.name)"
            case .long:
                return "--\(firstName.name)"
            case .longWithSingleDash:
                return "-\(firstName.name)"
            }
        }

        // Use valueName with long format if argument name is not known.
        if let valueName = argument.valueName {
            return "--\(valueName)"
        }

        // Should never reach here.
        return ""
    }
}
