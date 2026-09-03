//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Represents a manifest condition.
public struct PackageConditionDescription: Codable, Hashable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case platformNames
        case hostPlatformNames
        case config
        case traits
    }

    public let platformNames: [String]
    public let hostPlatformNames: [String]
    public let config: String?
    public let traits: Set<String>?

    public init(
        platformNames: [String] = [],
        hostPlatformNames: [String] = [],
        config: String? = nil,
        traits: Set<String>? = nil
    ) {
        assert(!(platformNames.isEmpty && hostPlatformNames.isEmpty && config == nil && traits == nil))
        self.platformNames = platformNames
        self.hostPlatformNames = hostPlatformNames
        self.config = config
        self.traits = traits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.platformNames = try container.decodeIfPresent([String].self, forKey: .platformNames) ?? []
        self.hostPlatformNames = try container.decodeIfPresent([String].self, forKey: .hostPlatformNames) ?? []
        self.config = try container.decodeIfPresent(String.self, forKey: .config)
        self.traits = try container.decodeIfPresent(Set<String>.self, forKey: .traits)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(platformNames, forKey: .platformNames)
        try container.encode(hostPlatformNames, forKey: .hostPlatformNames)
        try container.encodeIfPresent(config, forKey: .config)
        try container.encodeIfPresent(traits?.sorted(), forKey: .traits)
    }
}

/// One of possible conditions used in package manifests to restrict modules from being built for certain platforms or
/// build configurations.
public enum PackageCondition: Hashable, Sendable {
    case platforms(PlatformsCondition)
    case hostPlatforms(PlatformsCondition)
    case configuration(ConfigurationCondition)
    case traits(TraitCondition)

    public func satisfies(_ environment: BuildEnvironment) -> Bool {
        self.satisfies(targetEnvironment: environment, hostEnvironment: environment)
    }

    public func satisfies(
        targetEnvironment: BuildEnvironment,
        hostEnvironment: BuildEnvironment
    ) -> Bool {
        switch self {
        case .configuration(let configuration):
            return configuration.satisfies(targetEnvironment)
        case .platforms(let platforms):
            return platforms.satisfies(targetEnvironment)
        case .hostPlatforms(let platforms):
            return platforms.satisfies(hostEnvironment)
        case .traits(let traits):
            return traits.satisfies(targetEnvironment)
        }
    }

    public var platformsCondition: PlatformsCondition? {
        guard case let .platforms(platformsCondition) = self else {
            return nil
        }

        return platformsCondition
    }

    public var configurationCondition: ConfigurationCondition? {
        guard case let .configuration(configurationCondition) = self else {
            return nil
        }

        return configurationCondition
    }

    public var hostPlatformsCondition: PlatformsCondition? {
        guard case let .hostPlatforms(platformsCondition) = self else {
            return nil
        }

        return platformsCondition
    }

    public var traitCondition: TraitCondition? {
        guard case let .traits(traitCondition) = self else {
            return nil
        }

        return traitCondition
    }

    public init(platforms: [Platform]) {
        self = .platforms(.init(platforms: platforms))
    }

    public init(hostPlatforms: [Platform]) {
        self = .hostPlatforms(.init(platforms: hostPlatforms))
    }

    public init(configuration: BuildConfiguration) {
        self = .configuration(.init(configuration: configuration))
    }
}

/// Platforms condition implies that an assignment is valid on these platforms.
public struct PlatformsCondition: Hashable, Sendable {
    public let platforms: [Platform]

    public init(platforms: [Platform]) {
        assert(!platforms.isEmpty, "List of platforms should not be empty")
        self.platforms = platforms
    }

    public func satisfies(_ environment: BuildEnvironment) -> Bool {
        platforms.contains(environment.platform)
    }
}

/// A mini version of target platform constraints that will eventually be user specifiable..
/// For now used to mark modules host only that are only accessed by macros and plugins.
public enum PlatformConstraint {
    case all
    case host
}

/// A configuration condition implies that an assignment is valid on
/// a particular build configuration.
public struct ConfigurationCondition: Hashable, Sendable {
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


/// A configuration condition implies that an assignment is valid on
/// a particular build configuration.
public struct TraitCondition: Hashable, Sendable {
    public let traits: Set<String>

    public init(traits: Set<String>) {
        self.traits = traits
    }

    public func satisfies(_ environment: BuildEnvironment) -> Bool {
        return true
    }
}
