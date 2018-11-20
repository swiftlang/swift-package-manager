/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Represents a platform supported by the package.
public struct SupportedPlatform: Encodable {

    /// The platform name.
    let platform: String

    /// The platform version.
    let version: VersionedValue<String>?

    /// Creates supported platform instance.
    init(platform: String, version: VersionedValue<String>? = nil) {
        self.platform = platform
        self.version = version
    }

    /// The macOS platform.
    public static func macOS(_ version: SupportedPlatform.MacOSVersion) -> SupportedPlatform {
        return SupportedPlatform(platform: "macos", version: version.version)
    }

    /// The iOS platform.
    public static func iOS(_ version: SupportedPlatform.IOSVersion) -> SupportedPlatform {
        return SupportedPlatform(platform: "ios", version: version.version)
    }

    /// The tvOS platform.
    public static func tvOS(_ version: SupportedPlatform.TVOSVersion) -> SupportedPlatform {
        return SupportedPlatform(platform: "tvos", version: version.version)
    }

    /// The watchOS platform.
    public static func watchOS(_ version: SupportedPlatform.WatchOSVersion) -> SupportedPlatform {
        return SupportedPlatform(platform: "watchos", version: version.version)
    }

    /// The Linux platform.
    public static func linux() -> SupportedPlatform {
        return SupportedPlatform(platform: "linux")
    }

    /// Represents all platforms that are unspecified.
    public static var all: SupportedPlatform {
        return SupportedPlatform(platform: "<all>")
    }
}

extension SupportedPlatform {
    /// The macOS version.
    public struct MacOSVersion: Encodable {

        /// The underlying version representation.
        let version: VersionedValue<String>

        private init(_ version: String, supportedVersions: [ManifestVersion]) {
            let api = "v" + version.split(separator: ".").joined(separator: "_")
            self.init(VersionedValue(version, api: api, versions: supportedVersions))
        }

        private init(_ version: VersionedValue<String>) {
            self.version = version
        }

        /// Create a macOS version from the given string.
        ///
        /// The version string must be in format: 10.XX.XX
        public static func version(_ string: String) -> MacOSVersion {
            // Perform a quick validation.
            let components = string.split(separator: ".", omittingEmptySubsequences: false).map({ Int($0) })
            var error = components.compactMap({ $0 }).count != components.count
            error = error || !(components.first == 10 && (components.count == 2 || components.count == 3))
            if error {
                errors.append("invalid macOS version string: \(string)")
            }

            return self.init(VersionedValue(string, api: ""))
        }

        public static let v10_10: MacOSVersion = .init("10.10", supportedVersions: [.v5])
        public static let v10_11: MacOSVersion = .init("10.11", supportedVersions: [.v5])
        public static let v10_12: MacOSVersion = .init("10.12", supportedVersions: [.v5])
        public static let v10_13: MacOSVersion = .init("10.13", supportedVersions: [.v5])
        public static let v10_14: MacOSVersion = .init("10.14", supportedVersions: [.v5])
    }

    public struct TVOSVersion: Encodable {
        /// The underlying version representation.
        let version: VersionedValue<String>

        private init(_ version: String, supportedVersions: [ManifestVersion]) {
            let api = "v" + version
            self.init(VersionedValue(version, api: api, versions: supportedVersions))
        }

        private init(_ version: VersionedValue<String>) {
            self.version = version
        }

        /// Create a tvOS version from the given string.
        ///
        /// The version string must be in format: XX.XX
        public static func version(_ string: String) -> TVOSVersion {
            // Perform a quick validation.
            let components = string.split(separator: ".", omittingEmptySubsequences: false).map({ Int($0) })
            var error = components.compactMap({ $0 }).count != components.count
            error = error || !(components.count == 2 || components.count == 3)
            if error {
                errors.append("invalid tvOS version string: \(string)")
            }

            return self.init(VersionedValue(string, api: ""))
        }

        public static let v9: TVOSVersion = .init("9.0", supportedVersions: [.v5])
        public static let v10: TVOSVersion = .init("10.0", supportedVersions: [.v5])
        public static let v11: TVOSVersion = .init("11.0", supportedVersions: [.v5])
        public static let v12: TVOSVersion = .init("12.0", supportedVersions: [.v5])
    }

    public struct IOSVersion: Encodable {
        /// The underlying version representation.
        let version: VersionedValue<String>

        private init(_ version: String, supportedVersions: [ManifestVersion]) {
            let api = "v" + version
            self.init(VersionedValue(version, api: api, versions: supportedVersions))
        }

        private init(_ version: VersionedValue<String>) {
            self.version = version
        }

        /// Create an iOS version from the given string.
        ///
        /// The version string must be in format: XX.XX
        public static func version(_ string: String) -> IOSVersion {
            // Perform a quick validation.
            let components = string.split(separator: ".", omittingEmptySubsequences: false).map({ Int($0) })
            var error = components.compactMap({ $0 }).count != components.count
            error = error || !(components.count == 2 || components.count == 3)
            if error {
                errors.append("invalid iOS version string: \(string)")
            }

            return self.init(VersionedValue(string, api: ""))
        }

        public static let v8: IOSVersion = .init("8.0", supportedVersions: [.v5])
        public static let v9: IOSVersion = .init("9.0", supportedVersions: [.v5])
        public static let v10: IOSVersion = .init("10.0", supportedVersions: [.v5])
        public static let v11: IOSVersion = .init("11.0", supportedVersions: [.v5])
        public static let v12: IOSVersion = .init("12.0", supportedVersions: [.v5])
    }

    public struct WatchOSVersion: Encodable {
        /// The underlying version representation.
        let version: VersionedValue<String>

        private init(_ version: String, supportedVersions: [ManifestVersion]) {
            let api = "v" + version
            self.init(VersionedValue(version, api: api, versions: supportedVersions))
        }

        private init(_ version: VersionedValue<String>) {
            self.version = version
        }

        /// Create a watchOS version from the given string.
        ///
        /// The version string must be in format: XX.XX
        public static func version(_ string: String) -> WatchOSVersion {
            // Perform a quick validation.
            let components = string.split(separator: ".", omittingEmptySubsequences: false).map({ Int($0) })
            var error = components.compactMap({ $0 }).count != components.count
            error = error || !(components.count == 2 || components.count == 3)
            if error {
                errors.append("invalid watchOS version string: \(string)")
            }

            return self.init(VersionedValue(string, api: ""))
        }

        public static let v2: WatchOSVersion = .init("2.0", supportedVersions: [.v5])
        public static let v3: WatchOSVersion = .init("3.0", supportedVersions: [.v5])
        public static let v4: WatchOSVersion = .init("4.0", supportedVersions: [.v5])
        public static let v5: WatchOSVersion = .init("5.0", supportedVersions: [.v5])
    }
}
