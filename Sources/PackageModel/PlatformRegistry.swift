//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A registry for available platforms.
public struct PlatformRegistry {
    /// The current registry is hardcoded and static so we can just use
    /// a singleton for now.
    public static let `default`: PlatformRegistry = .init()

    /// The list of known platforms.
    public let knownPlatforms: [Platform]

    /// The mapping of platforms to their name.
    public let platformByName: [String: Platform]

    /// The list of known platform groups.
    public let knownPlatformGroups: [PlatformGroup]

    /// The mapping of platform groups to their name.
    public let platformGroupByName: [String: PlatformGroup]

    /// Create a registry with the given list of platforms and platform groups.
    init(
        platforms: [Platform] = PlatformRegistry._knownPlatforms,
        platformGroups: [PlatformGroup] = PlatformRegistry._knownPlatformGroups
    ) {
        self.knownPlatforms = platforms
        self.platformByName = Dictionary(uniqueKeysWithValues: knownPlatforms.map({ ($0.name, $0) }))
        self.knownPlatformGroups = platformGroups
        self.platformGroupByName = Dictionary(uniqueKeysWithValues: knownPlatformGroups.map({ ($0.name, $0) }))
    }

    /// The platforms named by the given platform or platform group name.
    public func platforms(named name: String) -> [Platform] {
        if let group = self.platformGroupByName[name] {
            group.platforms
        } else if let platform = self.platformByName[name] {
            [platform]
        } else {
            [.custom(name: name, oldestSupportedVersion: .unknown)]
        }
    }

    /// The static list of known platform groups.
    private static var _knownPlatformGroups: [PlatformGroup] {
        [
            .anyAppleOS,
        ]
    }

    /// The static list of known platforms.
    private static var _knownPlatforms: [Platform] {
        [
            .android,
            .driverKit,
            .iOS,
            .linux,
            .macOS,
            .macCatalyst,
            .openbsd,
            .freebsd,
            .tvOS,
            .visionOS,
            .wasi,
            .watchOS,
            .windows,
        ]
    }
}
