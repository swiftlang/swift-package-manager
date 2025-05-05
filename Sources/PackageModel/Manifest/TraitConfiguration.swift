//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// The trait configuration.
public enum TraitConfiguration: Codable, Hashable {
    case enableAllTraits
    case disableAllTraits
    case enabledTraits(Set<String>)
    case `default`

    public init(
        enabledTraits: Set<String>? = nil,
        enableAllTraits: Bool = false
    ) {
        // If all traits are enabled, then no other checks are necessary.
        guard !enableAllTraits else {
            self = .enableAllTraits
            return
        }

        // There can be two possible cases here:
        //  - The set of enabled traits is empty, which means that no traits are enabled.
        //  - The set of enabled traits is not empty and specifies which traits are enabled.
        if let enabledTraits {
            if enabledTraits.isEmpty {
                self = .disableAllTraits
            } else {
                self = .enabledTraits(enabledTraits)
            }
        } else {
            // Since enableAllTraits isn't enabled and there isn't a set of enabled traits,
            // there is no configuration passed by the user.
            self = .default
        }
    }

    /// The set of enabled traits, if available.
    public var enabledTraits: Set<String>? {
        switch self {
        case .default:
            ["default"]
        case .enabledTraits(let traits):
            traits
        case .disableAllTraits:
            []
        case .enableAllTraits:
            nil
        }
    }
}
