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

import struct TSCUtility.Version

/// Represents a platform.
public struct Platform: Equatable, Hashable, Codable, Sendable {
    /// The name of the platform.
    public let name: String

    /// The oldest supported deployment version by this platform.
    ///
    /// We currently hardcode this value but we should load it from the
    /// SDK's plist file. This value is always present for Apple platforms.
    public let oldestSupportedVersion: PlatformVersion

    /// Create a platform.
    private init(name: String, oldestSupportedVersion: PlatformVersion) {
        self.name = name
        self.oldestSupportedVersion = oldestSupportedVersion
    }

    public static func custom(name: String, oldestSupportedVersion: String) -> Platform {
        return Platform(name: name, oldestSupportedVersion: PlatformVersion(oldestSupportedVersion))
    }

    public static func custom(name: String, oldestSupportedVersion: PlatformVersion) -> Platform {
        return Platform(name: name, oldestSupportedVersion: oldestSupportedVersion)
    }

    public static let macOS: Platform = Platform(name: "macos", oldestSupportedVersion: "10.13")
    public static let macCatalyst: Platform = Platform(name: "maccatalyst", oldestSupportedVersion: "13.0")
    public static let iOS: Platform = Platform(name: "ios", oldestSupportedVersion: "12.0")
    public static let tvOS: Platform = Platform(name: "tvos", oldestSupportedVersion: "12.0")
    public static let watchOS: Platform = Platform(name: "watchos", oldestSupportedVersion: "4.0")
    public static let visionOS: Platform = Platform(name: "visionos", oldestSupportedVersion: "1.0")
    public static let driverKit: Platform = Platform(name: "driverkit", oldestSupportedVersion: "19.0")
    public static let linux: Platform = Platform(name: "linux", oldestSupportedVersion: .unknown)
    public static let android: Platform = Platform(name: "android", oldestSupportedVersion: .unknown)
    public static let windows: Platform = Platform(name: "windows", oldestSupportedVersion: .unknown)
    public static let wasi: Platform = Platform(name: "wasi", oldestSupportedVersion: .unknown)
    public static let openbsd: Platform = Platform(name: "openbsd", oldestSupportedVersion: .unknown)
    public static let freebsd: Platform = Platform(name: "freebsd", oldestSupportedVersion: .unknown)


}

/// Represents a platform supported by a target.
public struct SupportedPlatform: Hashable, Codable, Sendable {
    /// The platform.
    public let platform: Platform

    /// The minimum required version for this platform.
    public let version: PlatformVersion

    /// The options declared by the platform.
    public let options: [String]

    public init(platform: Platform, version: PlatformVersion, options: [String] = []) {
        self.platform = platform
        self.version = version
        self.options = options
    }
}

/// Represents a platform version.
public struct PlatformVersion: Equatable, Hashable, Codable, Sendable {
    // FIXME: this should be optional
    /// The unknown platform version.
    public static let unknown: PlatformVersion = .init("0.0.0")

    /// The underlying version storage.
    private let version: Version

    /// The string representation of the version.
    public var versionString: String {
        var str = "\(version.major).\(version.minor)"
        if version.patch != 0 {
            str += ".\(version.patch)"
        }
        return str
    }

    public var major: Int { version.major }
    public var minor: Int { version.minor }
    public var patch: Int { version.patch }

    /// Create a platform version given a string.
    ///
    /// The platform version is expected to be in format: X.X.X
    public init(_ version: String) {
        let components = version.split(separator: ".").compactMap({ Int($0) })
        assert(!components.isEmpty && components.count <= 3, version)
        switch components.count {
        case 1:
            self.version = Version(components[0], 0, 0)
        case 2:
            self.version = Version(components[0], components[1], 0)
        case 3:
            self.version = Version(components[0], components[1], components[2])
        default:
            fatalError("Unexpected number of components \(components)")
        }
    }
}

extension PlatformVersion: Comparable {
    public static func < (lhs: PlatformVersion, rhs: PlatformVersion) -> Bool {
        return lhs.version < rhs.version
    }
}

extension PlatformVersion: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}
