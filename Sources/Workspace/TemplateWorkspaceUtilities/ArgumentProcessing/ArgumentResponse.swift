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

public struct ArgumentResponse {
    public let argument: ArgumentInfoV0
    public let values: [String]
    public let isExplicitlyUnset: Bool

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

        // Final fallback: use valueName with long format
        if let valueName = argument.valueName {
            return "--\(valueName)"
        }

        // Should never reach here, but safety fallback
        return "--unknown"
    }

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
}
