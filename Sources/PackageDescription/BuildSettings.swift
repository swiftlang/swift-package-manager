/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// The build configuration such as debug or release.
public struct BuildConfiguration: Encodable {
    private let config: String

    private init(_ config: String) {
        self.config = config
    }

    /// The debug build configuration.
    public static let debug: BuildConfiguration = BuildConfiguration("debug")

    /// The release build configuration.
    public static let release: BuildConfiguration = BuildConfiguration("release")
}

/// A condition that limits the application of a build setting.
///
/// By default, build settings are applicable for all platforms and build
/// configurations. Use the `.when` modifier to define  a build
/// setting for a specific condition. Invalid usage of `.when` emits an error during
/// manifest parsing. For example, it's invalid to specify a `.when` condition with
/// both parameters as `nil`.
///
/// The following example shows how to use build setting conditions with various APIs:
///
///     ...
///     .target(
///         name: "MyTool",
///         dependencies: ["Utility"],
///         cSettings: [
///             .headerSearchPath("path/relative/to/my/target"),
///             .define("DISABLE_SOMETHING", .when(platforms: [.iOS], configuration: .release)),
///         ],
///         swiftSettings: [
///             .define("ENABLE_SOMETHING", .when(configuration: .release)),
///         ],
///         linkerSettings: [
///             .linkedLibrary("openssl", .when(platforms: [.linux])),
///         ]
///     ),
public struct BuildSettingCondition: Encodable {

    private let platforms: [Platform]?
    private let config: BuildConfiguration?

    private init(platforms: [Platform]?, config: BuildConfiguration?) {
        self.platforms = platforms
        self.config = config
    }

    /// Creates a build setting condition.
    ///
    /// At least one parameter is mandatory.
    ///
    /// - Parameters:
    ///   - platforms: The applicable platforms for this build setting condition.
    ///   - configuration: The applicable build configuration for this build setting condition.
    public static func when(
        platforms: [Platform]? = nil,
        configuration: BuildConfiguration? = nil
    ) -> BuildSettingCondition {
        // FIXME: This should be an error, not a precondition.
        precondition(!(platforms == nil && configuration == nil))
        return BuildSettingCondition(platforms: platforms, config: configuration)
    }
}

/// The underlying build setting data.
fileprivate struct BuildSettingData: Encodable {

    /// The name of the build setting.
    let name: String

    /// The value of the build setting.
    let value: [String]

    /// A condition that restricts the application of the build setting.
    let condition: BuildSettingCondition?
}

/// A C-language build setting.
public struct CSetting: Encodable {
    private let data: BuildSettingData

    private init(name: String, value: [String], condition: BuildSettingCondition?) {
        self.data = BuildSettingData(name: name, value: value, condition: condition)
    }

    /// Provides a header search path relative to the target's directory.
    ///
    /// Use this setting to add a search path for headers within your target.
    /// You can't use absolute paths and you can't use this setting to provide
    /// headers that are visible to other targets.
    ///
    /// The path must be a directory inside the package.
    ///
    /// - Since: First available in PackageDescription 5.0
    ///
    /// - Parameters:
    ///   - path: The path of the directory that contains the  headers. The path is relative to the target's directory.
    ///   - condition: A condition that restricts the application of the build setting.
    public static func headerSearchPath(_ path: String, _ condition: BuildSettingCondition? = nil) -> CSetting {
        return CSetting(name: "headerSearchPath", value: [path], condition: condition)
    }

    /// Defines a value for a macro.
    ///
    /// If you don't specify a value, the macro's default value is 1.
    ///
    /// - Since: First available in PackageDescription 5.0
    ///
    /// - Parameters:
    ///   - name: The name of the macro.
    ///   - value: The value of the macro.
    ///   - condition: A condition that restricts the application of the build setting.
    public static func define(_ name: String, to value: String? = nil, _ condition: BuildSettingCondition? = nil) -> CSetting {
        var settingValue = name
        if let value = value {
            settingValue += "=" + value
        }
        return CSetting(name: "define", value: [settingValue], condition: condition)
    }

    /// Sets unsafe flags to pass arbitrary command-line flags to the corresponding build tool.
    ///
    /// As the usage of the word "unsafe" implies, the Swift Package Manager
    /// can't safely determine if the build flags have any negative
    /// side effect on the build since certain flags can change the behavior of
    /// how it performs a build.
    ///
    /// As some build flags can be exploited for unsupported or malicious
    /// behavior, the use of unsafe flags make the products containing this
    /// target ineligible for use by other packages.
    ///
    /// - Since: First available in PackageDescription 5.0
    ///
    /// - Parameters:
    ///   - flags: The unsafe flags to set.
    ///   - condition: A condition that restricts the application of the build setting.
    public static func unsafeFlags(_ flags: [String], _ condition: BuildSettingCondition? = nil) -> CSetting {
        return CSetting(name: "unsafeFlags", value: flags, condition: condition)
    }
}

/// A CXX-language build setting.
public struct CXXSetting: Encodable {
    private let data: BuildSettingData

    private init(name: String, value: [String], condition: BuildSettingCondition?) {
        self.data = BuildSettingData(name: name, value: value, condition: condition)
    }

    /// Provides a header search path relative to the target's directory.
    ///
    /// Use this setting to add a search path for headers within your target.
    /// You can't use absolute paths and you can't use this setting to provide
    /// headers that are visible to other targets.
    ///
    /// The path must be a directory inside the package.
    ///
    /// - Since: First available in PackageDescription 5.0
    ///
    /// - Parameters:
    ///   - path: The path of the directory that contains the  headers. The path is relative to the target's directory.
    ///   - condition: A condition that restricts the application of the build setting.
    public static func headerSearchPath(_ path: String, _ condition: BuildSettingCondition? = nil) -> CXXSetting {
        return CXXSetting(name: "headerSearchPath", value: [path], condition: condition)
    }

    /// Defines a value for a macro.
    ///
    /// If you don't specify a value, the macro's default value is 1.
    ///
    /// - Since: First available in PackageDescription 5.0
    ///
    /// - Parameters:
    ///   - name: The name of the macro.
    ///   - value: The value of the macro.
    ///   - condition: A condition that restricts the application of the build setting.
    public static func define(_ name: String, to value: String? = nil, _ condition: BuildSettingCondition? = nil) -> CXXSetting {
        var settingValue = name
        if let value = value {
            settingValue += "=" + value
        }
        return CXXSetting(name: "define", value: [settingValue], condition: condition)
    }

    /// Sets unsafe flags to pass arbitrary command-line flags to the corresponding build tool.
    ///
    /// As the usage of the word "unsafe" implies, the Swift Package Manager
    /// can't safely determine if the build flags have any negative
    /// side effect on the build since certain flags can change the behavior of
    /// how a build is performed.
    ///
    /// As some build flags can be exploited for unsupported or malicious
    /// behavior, a product can't be used as a dependency in another package if one of its targets uses unsafe flags.
    ///
    /// - Since: First available in PackageDescription 5.0
    ///
    /// - Parameters:
    ///   - flags: The unsafe flags to set.
    ///   - condition: A condition that restricts the application of the build setting.
    public static func unsafeFlags(_ flags: [String], _ condition: BuildSettingCondition? = nil) -> CXXSetting {
        return CXXSetting(name: "unsafeFlags", value: flags, condition: condition)
    }
}

/// A Swift language build setting.
public struct SwiftSetting: Encodable {
    private let data: BuildSettingData

    private init(name: String, value: [String], condition: BuildSettingCondition?) {
        self.data = BuildSettingData(name: name, value: value, condition: condition)
    }

    /// Defines a compilation condition.
    ///
    /// Use compilation conditions to only compile statements if a certain condition is true.
    /// For example, the Swift compiler will only compile the
    /// statements inside the `#if` block when `ENABLE_SOMETHING` is defined:
    ///
    ///     #if ENABLE_SOMETHING
    ///        ...
    ///     #endif
    ///
    /// Unlike macros in C/C++, compilation conditions don't have an
    /// associated value.
    ///
    /// - Since: First available in PackageDescription 5.0
    ///
    /// - Parameters:
    ///   - name: The name of the macro.
    ///   - condition: A condition that restricts the application of the build setting.
    public static func define(_ name: String, _ condition: BuildSettingCondition? = nil) -> SwiftSetting {
        return SwiftSetting(name: "define", value: [name], condition: condition)
    }

    /// Sets unsafe flags to pass arbitrary command-line flags to the corresponding build tool.
    ///
    /// As the usage of the word "unsafe" implies, the Swift Package Manager
    /// can't safely determine if the build flags have any negative
    /// side effect on the build since certain flags can change the behavior of
    /// how a build is performed.
    ///
    /// As some build flags can be exploited for unsupported or malicious
    /// behavior, a product can't be used as a dependency in another package if one of its targets uses unsafe flags.
    ///
    /// - Since: First available in PackageDescription 5.0
    ///
    /// - Parameters:
    ///   - flags: The unsafe flags to set.
    ///   - condition: A condition that restricts the application of the build setting..
    public static func unsafeFlags(_ flags: [String], _ condition: BuildSettingCondition? = nil) -> SwiftSetting {
        return SwiftSetting(name: "unsafeFlags", value: flags, condition: condition)
    }
}

/// A linker build setting.
public struct LinkerSetting: Encodable {
    private let data: BuildSettingData

    private init(name: String, value: [String], condition: BuildSettingCondition?) {
        self.data = BuildSettingData(name: name, value: value, condition: condition)
    }

    /// Declares linkage to a system library.
    ///
    /// This setting is most useful when the library can't be linked
    /// automatically, such as C++ based libraries and non-modular
    /// libraries.
    ///
    /// - Since: First available in PackageDescription 5.0
    ///
    /// - Parameters:
    ///   - library: The library name.
    ///   - condition: A condition that restricts the application of the build setting.
    public static func linkedLibrary(_ library: String, _ condition: BuildSettingCondition? = nil) -> LinkerSetting {
        return LinkerSetting(name: "linkedLibrary", value: [library], condition: condition)
    }

    /// Declares linkage to a system framework.
    ///
    /// This setting is most useful when the framework can't be linked
    /// automatically, such as C++ based frameworks and non-modular
    /// frameworks.
    ///
    /// - Since: First available in PackageDescription 5.0
    ///
    /// - Parameters:
    ///   - framework: The framework name.
    ///   - condition: A condition that restricts the application of the build setting.
    public static func linkedFramework(_ framework: String, _ condition: BuildSettingCondition? = nil) -> LinkerSetting {
        return LinkerSetting(name: "linkedFramework", value: [framework], condition: condition)
    }

    /// Sets unsafe flags to pass arbitrary command-line flags to the corresponding build tool.
    ///
    /// As the usage of the word "unsafe" implies, the Swift Package Manager
    /// can't safely determine if the build flags have any negative
    /// side effect on the build since certain flags can change the behavior of
    /// how a build is performed.
    ///
    /// As some build flags can be exploited for unsupported or malicious
    /// behavior, a product can't be used as a dependency in another package if one of its targets uses unsafe flags.
    ///
    /// - Since: First available in PackageDescription 5.0
    ///
    /// - Parameters:
    ///   - flags: The unsafe flags to set.
    ///   - condition: A condition that restricts the application of the build setting.
    public static func unsafeFlags(_ flags: [String], _ condition: BuildSettingCondition? = nil) -> LinkerSetting {
        return LinkerSetting(name: "unsafeFlags", value: flags, condition: condition)
    }
}
