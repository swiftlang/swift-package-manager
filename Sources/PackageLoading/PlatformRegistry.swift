/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageModel

/// A registry for available platforms.
public final class PlatformRegistry {

    /// The current registery is hardcoded and static so we can just use
    /// a singleton for now.
    public static let `default`: PlatformRegistry = .init()

    /// The list of known platforms.
    public let knownPlatforms: [Platform]

    /// The mapping of platforms to their name.
    public let platformByName: [String: Platform]

    /// Create a registry with the given list of platforms.
    init(platforms: [Platform] = PlatformRegistry._knownPlatforms) {
        self.knownPlatforms = platforms
        self.platformByName = Dictionary(uniqueKeysWithValues: knownPlatforms.map({ ($0.name, $0) }))
    }

    /// The static list of known platforms.
    private static var _knownPlatforms: [Platform] {
        return [.macOS, .macCatalyst, .iOS, .tvOS, .watchOS, .linux, .windows, .android, .wasi, .driverKit]
    }
}
