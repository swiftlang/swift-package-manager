/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import SPMUtility

/// The supported manifest versions.
public enum ManifestVersion: String, Codable, CustomStringConvertible {
    case v4
    case v4_2
    case v5

    /// The Swift language version to use when parsing the manifest file.
    public var swiftLanguageVersion: SwiftLanguageVersion {
        // FIXME: This is not very scalable. We need to store the tools
        // version in the manifest and then use that to compute the right
        // Swift version instead of relying on the manifest version.  The
        // manifest version is just the version that was used to load the
        // manifest and shouldn't contribute to what Swift version is
        // chosen. For e.g., we might have a new manifest version 4.3, but
        // the language version should still be 4.2.
        switch self {
        case .v4: return .v4
        case .v4_2: return .v4_2
        case .v5: return .v5
        }
    }

    public var description: String {
        switch self {
        case .v4: return "4"
        case .v4_2: return "4.2"
        case .v5: return "5"
        }
    }

    /// Subpath to the the runtime for this manifest version.
    public var runtimeSubpath: RelativePath {
        switch self {
        case .v4:
            return RelativePath("4")
        case .v4_2, .v5:
            // PackageDescription 4.2 and 5 are source compatible so they're contained in the same dylib.
            return RelativePath("4_2")
        }
    }
}

/// This contains the declarative specification loaded from package manifest
/// files, and the tools for working with the manifest.
public final class Manifest: ObjectIdentifierProtocol, CustomStringConvertible, Codable {

    /// The standard filename for the manifest.
    public static let filename = basename + ".swift"

    /// The standard basename for the manifest.
    public static let basename = "Package"

    // FIXME: This doesn't belong here, we want the Manifest to be purely tied
    // to the repository state, it shouldn't matter where it is.
    //
    /// The path of the manifest file.
    public let path: AbsolutePath

    // FIXME: This doesn't belong here, we want the Manifest to be purely tied
    // to the repository state, it shouldn't matter where it is.
    //
    /// The repository URL the manifest was loaded from.
    public let url: String

    /// The version this package was loaded from, if known.
    public let version: Version?

    /// The version of manifest.
    public let manifestVersion: ManifestVersion

    /// The name of the package.
    public let name: String

    /// The declared platforms in the manifest.
    public let platforms: [PlatformDescription]

    /// The declared package dependencies.
    public let dependencies: [PackageDependencyDescription]

    /// The targets declared in the manifest.
    public let targets: [TargetDescription]

    /// The products declared in the manifest.
    public let products: [ProductDescription]

    /// The C language standard flag.
    public let cLanguageStandard: String?

    /// The C++ language standard flag.
    public let cxxLanguageStandard: String?

    /// The supported Swift language versions of the package.
    public let swiftLanguageVersions: [SwiftLanguageVersion]?

    /// The pkg-config name of a system package.
    public let pkgConfig: String?

    /// The system package providers of a system package.
    public let providers: [SystemPackageProviderDescription]?

    public init(
        name: String,
        platforms: [PlatformDescription],
        path: AbsolutePath,
        url: String,
        version: SPMUtility.Version? = nil,
        manifestVersion: ManifestVersion,
        pkgConfig: String? = nil,
        providers: [SystemPackageProviderDescription]? = nil,
        cLanguageStandard: String? = nil,
        cxxLanguageStandard: String? = nil,
        swiftLanguageVersions: [SwiftLanguageVersion]? = nil,
        dependencies: [PackageDependencyDescription] = [],
        products: [ProductDescription] = [],
        targets: [TargetDescription] = []
    ) {
        self.name = name
        self.platforms = platforms
        self.path = path
        self.url = url
        self.version = version
        self.manifestVersion = manifestVersion
        self.pkgConfig = pkgConfig
        self.providers = providers
        self.cLanguageStandard = cLanguageStandard
        self.cxxLanguageStandard = cxxLanguageStandard
        self.swiftLanguageVersions = swiftLanguageVersions
        self.dependencies = dependencies
        self.products = products
        self.targets = targets
    }

    public var description: String {
        return "<Manifest: \(name)>"
    }

    /// Coding user info key for dump-package command.
    ///
    /// Presence of this key will hide some keys when encoding the Manifest object.
    public static let dumpPackageKey: CodingUserInfoKey = CodingUserInfoKey(rawValue: "dumpPackage")!
}

extension Manifest {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)

        // Hide the keys that users shouldn't see when
        // we're encoding for the dump-package command.
        if encoder.userInfo[Manifest.dumpPackageKey] == nil {
            try container.encode(path, forKey: .path)
            try container.encode(url, forKey: .url)
            try container.encode(version, forKey: .version)
        }

        try container.encode(manifestVersion, forKey: .manifestVersion)
        try container.encode(pkgConfig, forKey: .pkgConfig)
        try container.encode(providers, forKey: .providers)
        try container.encode(cLanguageStandard, forKey: .cLanguageStandard)
        try container.encode(cxxLanguageStandard, forKey: .cxxLanguageStandard)
        try container.encode(swiftLanguageVersions, forKey: .swiftLanguageVersions)
        try container.encode(dependencies, forKey: .dependencies)
        try container.encode(products, forKey: .products)
        try container.encode(targets, forKey: .targets)
        try container.encode(platforms, forKey: .platforms)
    }
}

/// The description of an individual target.
public struct TargetDescription: Equatable, Codable {

    /// The target type.
    public enum TargetType: String, Equatable, Codable {
        case regular
        case test
        case system
    }

    /// Represents a target's dependency on another entity.
    public enum Dependency: Equatable, ExpressibleByStringLiteral {
        case target(name: String)
        case product(name: String, package: String?)
        case byName(name: String)

        public init(stringLiteral value: String) {
            self = .byName(name: value)
        }

        public static func product(name: String) -> Dependency {
            return .product(name: name, package: nil)
        }
    }

    /// The name of the target.
    public let name: String

    /// The custom path of the target.
    public let path: String?

    /// The custom sources of the target.
    public let sources: [String]?

    /// The exclude patterns.
    public let exclude: [String]

    // FIXME: Kill this.
    //
    /// Returns true if the target type is test.
    public var isTest: Bool {
        return type == .test
    }

    /// The declared target dependencies.
    public let dependencies: [Dependency]

    /// The custom public headers path.
    public let publicHeadersPath: String?

    /// The type of target.
    public let type: TargetType

    /// The pkg-config name of a system library target.
    public let pkgConfig: String?

    /// The providers of a system library target.
    public let providers: [SystemPackageProviderDescription]?

    /// The target-specific build settings declared in this target.
    public let settings: [TargetBuildSettingDescription.Setting]

    public init(
        name: String,
        dependencies: [Dependency] = [],
        path: String? = nil,
        exclude: [String] = [],
        sources: [String]? = nil,
        publicHeadersPath: String? = nil,
        type: TargetType = .regular,
        pkgConfig: String? = nil,
        providers: [SystemPackageProviderDescription]? = nil,
        settings: [TargetBuildSettingDescription.Setting] = []
    ) {
        switch type {
        case .regular, .test:
            precondition(pkgConfig == nil && providers == nil)
        case .system: break
        }

        self.name = name
        self.dependencies = dependencies
        self.path = path
        self.publicHeadersPath = publicHeadersPath
        self.sources = sources
        self.exclude = exclude
        self.type = type
        self.pkgConfig = pkgConfig
        self.providers = providers
        self.settings = settings
    }
}

/// The product description
public struct ProductDescription: Equatable, Codable {

    /// The name of the product.
    public let name: String

    /// The targets in the product.
    public let targets: [String]

    /// The type of product.
    public let type: ProductType

    public init(
        name: String,
        type: ProductType,
        targets: [String]
    ) {
        precondition(type != .test, "Declaring test products isn't supported: \(name):\(targets)")
        self.name = name
        self.type = type
        self.targets = targets
    }
}

/// Represents system package providers.
public enum SystemPackageProviderDescription: Equatable {
    case brew([String])
    case apt([String])
}

/// Represents a package dependency.
public struct PackageDependencyDescription: Equatable, Codable {

    /// The dependency requirement.
    public enum Requirement: Equatable, Hashable, CustomStringConvertible {
        case exact(Version)
        case range(Range<Version>)
        case revision(String)
        case branch(String)
        case localPackage

        public static func upToNextMajor(from version: SPMUtility.Version) -> Requirement {
            return .range(version..<Version(version.major + 1, 0, 0))
        }

        public static func upToNextMinor(from version: SPMUtility.Version) -> Requirement {
            return .range(version..<Version(version.major, version.minor + 1, 0))
        }

        public var description: String {
            switch self {
            case .exact(let version):
                return version.description
            case .range(let range):
                return range.description
            case .revision(let revision):
                return "revision[\(revision)]"
            case .branch(let branch):
                return "branch[\(branch)]"
            case .localPackage:
                return "local"
            }
        }
    }

    /// The url of the dependency.
    public let url: String

    /// The dependency requirement.
    public let requirement: Requirement

    /// Create a dependency.
    public init(url: String, requirement: Requirement) {
        self.url = url
        self.requirement = requirement
    }
}

public struct PlatformDescription: Codable, Equatable {
    public let platformName: String
    public let version: String

    public init(name: String, version: String) {
        self.platformName = name
        self.version = version
    }
}

/// A namespace for target-specific build settings.
public enum TargetBuildSettingDescription {

    /// Represents a build settings condition.
    public struct Condition: Codable, Equatable {

        public let platformNames: [String]
        public let config: String?

        public init(platformNames: [String] = [], config: String? = nil) {
            assert(!(platformNames.isEmpty && config == nil))
            self.platformNames = platformNames
            self.config = config
        }
    }

    /// The tool for which a build setting is declared.
    public enum Tool: String, Codable, Equatable, CaseIterable {
        case c
        case cxx
        case swift
        case linker
    }

    /// The name of the build setting.
    public enum SettingName: String, Codable, Equatable {
        case headerSearchPath
        case define
        case linkedLibrary
        case linkedFramework

        case unsafeFlags
    }

    /// An individual build setting.
    public struct Setting: Codable, Equatable {

        /// The tool associated with this setting.
        public let tool: Tool

        /// The name of the setting.
        public let name: SettingName

        /// The condition at which the setting should be applied.
        public let condition: Condition?

        /// The value of the setting.
        ///
        /// This is kind of like an "untyped" value since the length
        /// of the array will depend on the setting type.
        public let value: [String]

        public init(
            tool: Tool,
            name: SettingName,
            value: [String],
            condition: Condition? = nil
        ) {
            switch name {
            case .headerSearchPath: fallthrough
            case .define: fallthrough
            case .linkedLibrary: fallthrough
            case .linkedFramework:
                assert(value.count == 1, "\(tool) \(name) \(value)")
                break
            case .unsafeFlags:
                assert(value.count >= 1, "\(tool) \(name) \(value)")
                break
            }

            self.tool = tool
            self.name = name
            self.value = value
            self.condition = condition
        }
    }
}
