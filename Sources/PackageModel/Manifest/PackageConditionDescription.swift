//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Represents a manifest condition.
public struct PackageConditionDescription: Codable, Equatable, Sendable {
    public let platformNames: [String]
    public let config: String?

    public init(platformNames: [String] = [], config: String? = nil) {
        assert(!(platformNames.isEmpty && config == nil))
        self.platformNames = platformNames
        self.config = config
    }
}

/// A manifest condition.
public protocol PackageConditionProtocol: Codable {
    func satisfies(_ environment: BuildEnvironment) -> Bool
}

/// Wrapper for package condition so it can be conformed to Codable.
struct PackageConditionWrapper: Codable {
    var platform: PlatformsCondition?
    var config: ConfigurationCondition?

    var condition: PackageConditionProtocol {
        if let platform {
            return platform
        } else if let config {
            return config
        } else {
            fatalError("unreachable")
        }
    }

    init(_ condition: PackageConditionProtocol) {
        switch condition {
        case let platform as PlatformsCondition:
            self.platform = platform
        case let config as ConfigurationCondition:
            self.config = config
        default:
            fatalError("unknown condition \(condition)")
        }
    }
}

/// Platforms condition implies that an assignment is valid on these platforms.
public struct PlatformsCondition: PackageConditionProtocol {
    public let platforms: [Platform]

    public init(platforms: [Platform]) {
        assert(!platforms.isEmpty, "List of platforms should not be empty")
        self.platforms = platforms
    }

    public func satisfies(_ environment: BuildEnvironment) -> Bool {
        platforms.contains(environment.platform)
    }
}

/// A configuration condition implies that an assignment is valid on
/// a particular build configuration.
public struct ConfigurationCondition: PackageConditionProtocol {
    public let configuration: BuildConfiguration

    public init(configuration: BuildConfiguration) {
        self.configuration = configuration
    }

    public func satisfies(_ environment: BuildEnvironment) -> Bool {
        if environment.configuration == nil {
            return true
        } else {
            return configuration == environment.configuration
        }
    }
}
