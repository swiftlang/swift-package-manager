/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Represents a platform.
public struct Platform: Encodable {

    /// The name of the platform.
    fileprivate let name: String

    private init(name: String) {
        self.name = name
    }

    public static let macOS: Platform = Platform(name: "macos")
    public static let iOS: Platform = Platform(name: "ios")
    public static let tvOS: Platform = Platform(name: "tvos")
    public static let watchOS: Platform = Platform(name: "watchos")
    public static let linux: Platform = Platform(name: "linux")
}

/// Represents a platform supported by the package.
public struct SupportedPlatform: Encodable {

    /// The platform.
    let platform: Platform

    /// The platform version.
    let version: String?

    /// Creates supported platform instance.
    init(platform: Platform, version: String? = nil) {
        self.platform = platform
        self.version = version
    }

    /// Create macOS supported platform with the given version.
    public static func macOS(_ version: SupportedPlatform.MacOSVersion) -> SupportedPlatform {
        return SupportedPlatform(platform: .macOS, version: version.version)
    }

    /// Create macOS supported platform with the given version string.
    ///
    /// The version string must be a series of 2 or 3 dot-separated integers, for example "10.10" or "10.10.1".
    public static func macOS(_ versionString: String) -> SupportedPlatform {
        return SupportedPlatform(platform: .macOS, version: SupportedPlatform.MacOSVersion(string: versionString).version)
    }

    /// Create iOS supported platform with the given version.
    public static func iOS(_ version: SupportedPlatform.IOSVersion) -> SupportedPlatform {
        return SupportedPlatform(platform: .iOS, version: version.version)
    }

    /// Create iOS supported platform with the given version string.
    ///
    /// The version string must be a series of 2 or 3 dot-separated integers, for example "8.0" or "8.0.1".
    public static func iOS(_ versionString: String) -> SupportedPlatform {
        return SupportedPlatform(platform: .iOS, version: SupportedPlatform.IOSVersion(string: versionString).version)
    }

    /// Create tvOS supported platform with the given version.
    public static func tvOS(_ version: SupportedPlatform.TVOSVersion) -> SupportedPlatform {
        return SupportedPlatform(platform: .tvOS, version: version.version)
    }

    /// Create tvOS supported platform with the given version string.
    ///
    /// The version string must be a series of 2 or 3 dot-separated integers, for example "9.0" or "9.0.1".
    public static func tvOS(_ versionString: String) -> SupportedPlatform {
        return SupportedPlatform(platform: .tvOS, version: SupportedPlatform.TVOSVersion(string: versionString).version)
    }

    /// Create watchOS supported platform with the given version.
    public static func watchOS(_ version: SupportedPlatform.WatchOSVersion) -> SupportedPlatform {
        return SupportedPlatform(platform: .watchOS, version: version.version)
    }

    /// Create watchOS supported platform with the given version string.
    ///
    /// The version string must be a series of 2 or 3 dot-separated integers, for example "2.0" or "2.0.1".
    public static func watchOS(_ versionString: String) -> SupportedPlatform {
        return SupportedPlatform(platform: .watchOS, version: SupportedPlatform.WatchOSVersion(string: versionString).version)
    }
}

extension SupportedPlatform {
    /// The macOS version.
    public struct MacOSVersion: Encodable, AppleOSVersion {
        fileprivate static let name = "macOS"
        fileprivate static let minimumMajorVersion = 10

        /// The underlying version representation.
        let version: String

        fileprivate init(uncheckedVersion version: String) {
            self.version = version
        }

        public static let v10_10: MacOSVersion = .init(string: "10.10")
        public static let v10_11: MacOSVersion = .init(string: "10.11")
        public static let v10_12: MacOSVersion = .init(string: "10.12")
        public static let v10_13: MacOSVersion = .init(string: "10.13")
        public static let v10_14: MacOSVersion = .init(string: "10.14")
    }

    public struct TVOSVersion: Encodable, AppleOSVersion {
        fileprivate static let name = "tvOS"
        fileprivate static let minimumMajorVersion = 9

        /// The underlying version representation.
        let version: String

        fileprivate init(uncheckedVersion version: String) {
            self.version = version
        }

        public static let v9: TVOSVersion = .init(string: "9.0")
        public static let v10: TVOSVersion = .init(string: "10.0")
        public static let v11: TVOSVersion = .init(string: "11.0")
        public static let v12: TVOSVersion = .init(string: "12.0")
    }

    public struct IOSVersion: Encodable, AppleOSVersion {
        fileprivate static let name = "iOS"
        fileprivate static let minimumMajorVersion = 2

        /// The underlying version representation.
        let version: String

        fileprivate init(uncheckedVersion version: String) {
            self.version = version
        }

        public static let v8: IOSVersion = .init(string: "8.0")
        public static let v9: IOSVersion = .init(string: "9.0")
        public static let v10: IOSVersion = .init(string: "10.0")
        public static let v11: IOSVersion = .init(string: "11.0")
        public static let v12: IOSVersion = .init(string: "12.0")
    }

    public struct WatchOSVersion: Encodable, AppleOSVersion {
        fileprivate static let name = "watchOS"
        fileprivate static let minimumMajorVersion = 2

        /// The underlying version representation.
        let version: String

        fileprivate init(uncheckedVersion version: String) {
            self.version = version
        }

        public static let v2: WatchOSVersion = .init(string: "2.0")
        public static let v3: WatchOSVersion = .init(string: "3.0")
        public static let v4: WatchOSVersion = .init(string: "4.0")
        public static let v5: WatchOSVersion = .init(string: "5.0")
    }
}

fileprivate protocol AppleOSVersion {
    static var name: String { get }
    static var minimumMajorVersion: Int { get }
    init(uncheckedVersion: String)
}

fileprivate extension AppleOSVersion {
    init(string: String) {
        // Perform a quick validation.
        let components = string.split(separator: ".", omittingEmptySubsequences: false).map({ UInt($0) })
        var error = components.compactMap({ $0 }).count != components.count
        error = error || !(components.count == 2 || components.count == 3) || ((components[0] ?? 0) < Self.minimumMajorVersion)
        if error {
            errors.append("invalid \(Self.name) version string: \(string)")
        }

        self.init(uncheckedVersion: string)
    }
}
