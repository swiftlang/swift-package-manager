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
    case noConfiguration
    case noEnabledTraits
    case enabledTraits(Set<String>)

    public init(
        enabledTraits: Set<String>? = nil,
        enableAllTraits: Bool = false
    ) {
        // If all traits are enabled, then no other checks are necessary.
        guard !enableAllTraits else {
            self = .enableAllTraits
            return
        }

        if let enabledTraits {
            if enabledTraits.isEmpty {
                self = .noEnabledTraits
            } else {
                self = .enabledTraits(enabledTraits)
            }
        } else {
            // Since enableAllTraits isn't enabled and there isn't a set of traits set,
            // there is no configuration passed by the user.
            self = .noConfiguration
        }
    }

    /// Default instance of `TraitConfiguration`.
    public static var `default`: TraitConfiguration {
        .init(enabledTraits: nil)
    }

    public var enabledTraits: Set<String>? {
        switch self {
        case .enabledTraits(let traits):
            return traits
        case .noConfiguration, .enableAllTraits:
            return nil
        case .noEnabledTraits:
            return []
        }
    }

    public var enableAllTraits: Bool {
        if case .enableAllTraits = self {
            return true
        }

        return false
    }

    public var enablesDefaultTraits: Bool {
        switch self {
        case .enabledTraits(let traits):
            return traits.contains("default")
        case .noConfiguration, .enableAllTraits:
            return true
        case .noEnabledTraits:
            return false
        }
    }

    public var enablesNonDefaultTraits: Bool {
        switch self {
        case .enabledTraits(let traits):
            let traitsWithoutDefault = traits.subtracting(["default"])
            return !traitsWithoutDefault.isEmpty
        case .enableAllTraits:
            return true
        case .noConfiguration, .noEnabledTraits:
            return false
        }
    }

//    public var enablesDefaultTraits: Bool {
//        switch self {
//        case .enableAllTraits, .noConfiguration:
//            return true
//        case .enabledTraits(let traits):
//            return traits.contains("default")
//        case .noEnabledTraits:
//            return false
//        }
//    }

//    public var enabledTraitsWithoutDefault: Set<String>? {
//        switch self {
//        case .enabledTraits(let traits):
//        }
//    }
}
