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
    public let platformNames: [String]
    public let config: String?
    public let traits: Set<String>?

    public init(platformNames: [String] = [], config: String? = nil, traits: Set<String>? = nil) {
        assert(!(platformNames.isEmpty && config == nil && traits == nil))
        self.platformNames = platformNames
        self.config = config
        self.traits = traits
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(platformNames, forKey: .platformNames)
        try container.encodeIfPresent(config, forKey: .config)
        try container.encodeIfPresent(traits?.sorted(), forKey: .traits)
    }
}

/// One of possible conditions used in package manifests to restrict modules from being built for certain platforms or
/// build configurations.
public enum PackageCondition: Hashable, Sendable {
    case platforms(PlatformsCondition)
    case host(HostCondition)
    case configuration(ConfigurationCondition)
    case traits(TraitCondition)

    public func satisfies(_ environment: BuildEnvironment) -> Bool {
        switch self {
        case .configuration(let configuration):
            return configuration.satisfies(environment)
        case .platforms(let platforms):
            return platforms.satisfies(environment)
        case .host(let host):
            return host.satisfies(environment)
        case .traits(let traits):
            return traits.satisfies(environment)
        }
    }

    public var platformsCondition: PlatformsCondition? {
        guard case let .platforms(platformsCondition) = self else {
            return nil
        }

        return platformsCondition
    }

    public var hostCondition: HostCondition? {
        guard case let .host(hostCondition) = self else {
            return nil
        }

        return hostCondition
    }

    public var configurationCondition: ConfigurationCondition? {
        guard case let .configuration(configurationCondition) = self else {
            return nil
        }

        return configurationCondition
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

/// Condition that is satisfied if building for host matches the build environment.
/// This is for SwiftPM's use for now to make prebuilts conditional on host builds
/// so are not made available in the manifest.
public struct HostCondition: Hashable, Sendable {
    public let forHost: Bool

    public init(forHost: Bool) {
        self.forHost = forHost
    }

    public func satisfies(_ environment: BuildEnvironment) -> Bool {
        forHost == environment.forHost
    }
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


/// Trait conditions are evaluated at package resolution time so and traits are filtered out
/// based on the requested traits for the package. As such, the build condition is always
/// true since builds do not specify traits.
public struct TraitCondition: Hashable, Sendable {
    public let traits: Set<String>

    public init(traits: Set<String>) {
        self.traits = traits
    }

    public func satisfies(_ environment: BuildEnvironment) -> Bool {
        return true
    }
}

