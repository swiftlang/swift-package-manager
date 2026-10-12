//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2018-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A platform supported by Swift Package Manager.
public struct Platform: Equatable, Sendable {

    /// The name of the platform.
    public let name: String

    private init(name: String) {
        self.name = name
    }

    /// Creates a custom platform.
    ///
    /// Use this function if none of the predefined platform names match the platform you are targeting.
    /// - Parameter platformName: The name of the platform.
    /// - Returns: A `Platform` instance.
    @available(_PackageDescription, introduced: 5.6)
    public static func custom(_ platformName: String) -> Platform {
        return Platform(name: platformName)
    }

    /// The macOS platform.
    public static let macOS: Platform = Platform(name: "macos")

    /// The Mac Catalyst platform.
    public static let macCatalyst: Platform = Platform(name: "maccatalyst")

    /// The iOS platform.
    public static let iOS: Platform = Platform(name: "ios")

    /// The tvOS platform.
    public static let tvOS: Platform = Platform(name: "tvos")

    /// The watchOS platform.
    public static let watchOS: Platform = Platform(name: "watchos")

    /// The visionOS platform.
    public static let visionOS: Platform = Platform(name: "visionos")

    /// The DriverKit platform
    public static let driverKit: Platform = Platform(name: "driverkit")

    /// The Linux platform.
    public static let linux: Platform = Platform(name: "linux")

    /// The Windows platform.
    @available(_PackageDescription, introduced: 5.2)
    public static let windows: Platform = Platform(name: "windows")

    /// The Android platform.
    @available(_PackageDescription, introduced: 5.2)
    public static let android: Platform = Platform(name: "android")

    /// The WebAssembly System Interface platform.
    @available(_PackageDescription, introduced: 5.3)
    public static let wasi: Platform = Platform(name: "wasi")

    /// The OpenBSD platform.
    @available(_PackageDescription, introduced: 5.8)
    public static let openbsd: Platform = Platform(name: "openbsd")

    /// The FreeBSD platform.
    @available(_PackageDescription, introduced: 999.0)
    public static let freebsd: Platform = Platform(name: "freebsd")
}

