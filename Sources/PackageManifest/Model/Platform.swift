public struct Platform: Codable, Equatable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

extension Platform {
    /// The macOS platform.
    public static let macOS = Platform(name: "macos")

    /// The Mac Catalyst platform.
    public static let macCatalyst = Platform(name: "maccatalyst")

    /// The iOS platform.
    public static let iOS = Platform(name: "ios")

    /// The tvOS platform.
    public static let tvOS = Platform(name: "tvos")

    /// The watchOS platform.
    public static let watchOS = Platform(name: "watchos")

    /// The DriverKit platform
    public static let driverKit = Platform(name: "driverkit")

    /// The Linux platform.
    public static let linux = Platform(name: "linux")

    /// The Windows platform.
    public static let windows = Platform(name: "windows")

    /// The Android platform.
    public static let android = Platform(name: "android")

    /// The WebAssembly System Interface platform.
    public static let wasi = Platform(name: "wasi")

    /// The OpenBSD platform.
    public static let openbsd = Platform(name: "openbsd")
}
