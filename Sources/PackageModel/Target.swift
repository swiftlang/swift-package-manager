/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic

import protocol TSCUtility.PolymorphicCodableProtocol
import Basics

public class Target: PolymorphicCodableProtocol {
    public static var implementations: [PolymorphicCodableProtocol.Type] = [
        SwiftTarget.self,
        ClangTarget.self,
        SystemLibraryTarget.self,
        BinaryTarget.self,
        PluginTarget.self,
    ]

    /// The target kind.
    public enum Kind: String, Codable {
        case executable
        case library
        case systemModule = "system-target"
        case test
        case binary
        case plugin
        case snippet
    }

    /// A reference to a product from a target dependency.
    public struct ProductReference: Codable {

        /// The name of the product dependency.
        public let name: String

        /// The name of the package containing the product.
        public let package: String?

        /// Module aliases for targets of this product dependency. The key is an
        /// original target name and the value is a new unique name that also
        /// becomes the name of its .swiftmodule binary.
        public let moduleAliases: [String: String]?

        /// Creates a product reference instance.
        public init(name: String, package: String?, moduleAliases: [String: String]? = nil) {
            self.name = name
            self.package = package
            self.moduleAliases = moduleAliases
        }
    }

    /// A target dependency to a target or product.
    public enum Dependency {
        /// A dependency referencing another target, with conditions.
        case target(_ target: Target, conditions: [PackageConditionProtocol])

        /// A dependency referencing a product, with conditions.
        case product(_ product: ProductReference, conditions: [PackageConditionProtocol])

        /// The target if the dependency is a target dependency.
        public var target: Target? {
            if case .target(let target, _) = self {
                return target
            } else {
                return nil
            }
        }

        /// The product reference if the dependency is a product dependency.
        public var product: ProductReference? {
            if case .product(let product, _) = self {
                return product
            } else {
                return nil
            }
        }

        /// The dependency conditions.
        public var conditions: [PackageConditionProtocol] {
            switch self {
            case .target(_, let conditions):
                return conditions
            case .product(_, let conditions):
                return conditions
            }
        }

        /// The name of the target or product of the dependency.
        public var name: String {
            switch self {
            case .target(let target, _):
                return target.name
            case .product(let product, _):
                return product.name
            }
        }
    }

    /// A usage of a plugin target or product. Implemented as a dependency
    /// for now and added to the `dependencies` array, since they currently
    /// have exactly the same characteristics and to avoid duplicating the
    /// implementation for now.
    public typealias PluginUsage = Dependency

    /// The name of the target.
    ///
    /// NOTE: This name is not the language-level target (i.e., the importable
    /// name) name in many cases, instead use c99name if you need uniqueness.
    public private(set) var name: String

    /// Module aliases needed to build this target. The key is an original name of a
    /// dependent target and the value is a new unique name mapped to the name
    /// of its .swiftmodule binary.
    public private(set) var moduleAliases: [String: String]?

    /// Add module aliases (if applicable) for dependencies of this target.
    ///
    /// For example, adding an alias `Bar` for a target name `Foo` will result in
    /// compiling references to `Foo` in source code of this target as `Bar.swiftmodule`.
    /// If the name argument `Foo` is the same as this target's name, this target will be
    /// renamed as `Bar` and the resulting binary will be `Bar.swiftmodule`.
    ///
    /// - Parameters:
    ///   - name: The original name of a dependent target or this target
    ///   - alias: A new unique name mapped to the resulting binary name
    public func addModuleAlias(for name: String, as alias: String) {
        if moduleAliases == nil {
            moduleAliases = [name: alias]
        } else {
            moduleAliases?[name] = alias
        }

        // If the argument name is same as this target's name, this
        // target should be renamed as the argument alias.
        if name == self.name {
            self.name = alias
            self.c99name = alias.spm_mangledToC99ExtendedIdentifier()
        }
    }
  
    /// The default localization for resources.
    public let defaultLocalization: String?

    /// The dependencies of this target.
    public let dependencies: [Dependency]

    /// The language-level target name.
    public private(set) var c99name: String

    /// The bundle name, if one is being generated.
    public let bundleName: String?

    /// Suffix that's expected for test targets.
    public static let testModuleNameSuffix = "Tests"

    /// The kind of target.
    public let type: Kind

    /// The sources for the target.
    public let sources: Sources

    /// The resource files in the target.
    public let resources: [Resource]

    /// Files in the target that were marked as ignored.
    public let ignored: [AbsolutePath]

    /// Other kinds of files in the target.
    public let others: [AbsolutePath]

    /// The list of platforms that are supported by this target.
    public let platforms: [SupportedPlatform]

    /// Returns the supported platform instance for the given platform.
    public func getSupportedPlatform(for platform: Platform) -> SupportedPlatform? {
        return self.platforms.first(where: { $0.platform == platform })
    }

    /// The build settings assignments of this target.
    public let buildSettings: BuildSettings.AssignmentTable

    /// The usages of package plugins by this target.
    public let pluginUsages: [PluginUsage]

    fileprivate init(
        name: String,
        bundleName: String? = nil,
        defaultLocalization: String?,
        platforms: [SupportedPlatform],
        type: Kind,
        sources: Sources,
        resources: [Resource] = [],
        ignored: [AbsolutePath] = [],
        others: [AbsolutePath] = [],
        dependencies: [Target.Dependency],
        buildSettings: BuildSettings.AssignmentTable,
        pluginUsages: [PluginUsage]
    ) {
        self.name = name
        self.bundleName = bundleName
        self.defaultLocalization = defaultLocalization
        self.platforms = platforms
        self.type = type
        self.sources = sources
        self.resources = resources
        self.ignored = ignored
        self.others = others
        self.dependencies = dependencies
        self.c99name = self.name.spm_mangledToC99ExtendedIdentifier()
        self.buildSettings = buildSettings
        self.pluginUsages = pluginUsages
    }

    private enum CodingKeys: String, CodingKey {
        case name, bundleName, defaultLocalization, platforms, type, sources, resources, ignored, others, buildSettings, pluginUsages
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // FIXME: dependencies property is skipped on purpose as it points to
        // the actual target dependency object.
        try container.encode(name, forKey: .name)
        try container.encode(bundleName, forKey: .bundleName)
        try container.encode(defaultLocalization, forKey: .defaultLocalization)
        try container.encode(platforms, forKey: .platforms)
        try container.encode(type, forKey: .type)
        try container.encode(sources, forKey: .sources)
        try container.encode(resources, forKey: .resources)
        try container.encode(ignored, forKey: .ignored)
        try container.encode(others, forKey: .others)
        try container.encode(buildSettings, forKey: .buildSettings)
        // FIXME: pluginUsages property is skipped on purpose as it points to
        // the actual target dependency object.
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.bundleName = try container.decodeIfPresent(String.self, forKey: .bundleName)
        self.defaultLocalization = try container.decodeIfPresent(String.self, forKey: .defaultLocalization)
        self.platforms = try container.decode([SupportedPlatform].self, forKey: .platforms)
        self.type = try container.decode(Kind.self, forKey: .type)
        self.sources = try container.decode(Sources.self, forKey: .sources)
        self.resources = try container.decode([Resource].self, forKey: .resources)
        self.ignored = try container.decode([AbsolutePath].self, forKey: .ignored)
        self.others = try container.decode([AbsolutePath].self, forKey: .others)
        // FIXME: dependencies property is skipped on purpose as it points to
        // the actual target dependency object.
        self.dependencies = []
        self.c99name = self.name.spm_mangledToC99ExtendedIdentifier()
        self.buildSettings = try container.decode(BuildSettings.AssignmentTable.self, forKey: .buildSettings)
        // FIXME: pluginUsages property is skipped on purpose as it points to
        // the actual target dependency object.
        self.pluginUsages = []
    }
}

extension Target: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    public static func == (lhs: Target, rhs: Target) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}

extension Target: CustomStringConvertible {
    public var description: String {
        return "<\(Swift.type(of: self)): \(name)>"
    }
}

public final class SwiftTarget: Target {

    /// The file name of test manifest.
    public static let testManifestNames = ["XCTMain.swift", "LinuxMain.swift"]

    public init(testDiscoverySrc: Sources, name: String, dependencies: [Target.Dependency]) {
        self.swiftVersion = .v5

        super.init(
            name: name,
            defaultLocalization: nil,
            platforms: [],
            type: .executable,
            sources: testDiscoverySrc,
            dependencies: dependencies,
            buildSettings: .init(),
            pluginUsages: []
        )
    }

    /// The swift version of this target.
    public let swiftVersion: SwiftLanguageVersion

    public init(
        name: String,
        bundleName: String? = nil,
        defaultLocalization: String? = nil,
        platforms: [SupportedPlatform] = [],
        type: Kind,
        sources: Sources,
        resources: [Resource] = [],
        ignored: [AbsolutePath] = [],
        others: [AbsolutePath] = [],
        dependencies: [Target.Dependency] = [],
        swiftVersion: SwiftLanguageVersion,
        buildSettings: BuildSettings.AssignmentTable = .init(),
        pluginUsages: [PluginUsage] = []
    ) {
        self.swiftVersion = swiftVersion
        super.init(
            name: name,
            bundleName: bundleName,
            defaultLocalization: defaultLocalization,
            platforms: platforms,
            type: type,
            sources: sources,
            resources: resources,
            ignored: ignored,
            others: others,
            dependencies: dependencies,
            buildSettings: buildSettings,
            pluginUsages: pluginUsages
        )
    }

    /// Create an executable Swift target from test manifest file.
    public init(testManifest: AbsolutePath, name: String, dependencies: [Target.Dependency]) {
        // Look for the first swift test target and use the same swift version
        // for linux main target. This will need to change if we move to a model
        // where we allow per target swift language version build settings.
        let swiftTestTarget = dependencies.first {
            guard case .target(let target as SwiftTarget, _) = $0 else { return false }
            return target.type == .test
        }.flatMap { $0.target as? SwiftTarget }

        // FIXME: This is not very correct but doesn't matter much in practice.
        // We need to select the latest Swift language version that can
        // satisfy the current tools version but there is not a good way to
        // do that currently.
        self.swiftVersion = swiftTestTarget?.swiftVersion ?? SwiftLanguageVersion(string: String(ToolsVersion.currentToolsVersion.major)) ?? .v4
        let sources = Sources(paths: [testManifest], root: testManifest.parentDirectory)

        let platforms: [SupportedPlatform] = swiftTestTarget?.platforms ?? []

        super.init(
            name: name,
            defaultLocalization: nil,
            platforms: platforms,
            type: .executable,
            sources: sources,
            dependencies: dependencies,
            buildSettings: .init(),
            pluginUsages: []
        )
    }

    private enum CodingKeys: String, CodingKey {
        case swiftVersion
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(swiftVersion, forKey: .swiftVersion)
        try super.encode(to: encoder)
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.swiftVersion = try container.decode(SwiftLanguageVersion.self, forKey: .swiftVersion)
        try super.init(from: decoder)
    }
}

public final class SystemLibraryTarget: Target {

    /// The name of pkgConfig file, if any.
    public let pkgConfig: String?

    /// List of system package providers, if any.
    public let providers: [SystemPackageProviderDescription]?

    /// The package path.
    public var path: AbsolutePath {
        return sources.root
    }

    /// True if this system library should become implicit target
    /// dependency of its dependent packages.
    public let isImplicit: Bool

    public init(
        name: String,
        platforms: [SupportedPlatform] = [],
        path: AbsolutePath,
        isImplicit: Bool = true,
        pkgConfig: String? = nil,
        providers: [SystemPackageProviderDescription]? = nil
    ) {
        let sources = Sources(paths: [], root: path)
        self.pkgConfig = pkgConfig
        self.providers = providers
        self.isImplicit = isImplicit
        super.init(
            name: name,
            defaultLocalization: nil,
            platforms: platforms,
            type: .systemModule,
            sources: sources,
            dependencies: [],
            buildSettings: .init(),
            pluginUsages: []
        )
    }

    private enum CodingKeys: String, CodingKey {
        case pkgConfig, providers, isImplicit
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pkgConfig, forKey: .pkgConfig)
        try container.encode(providers, forKey: .providers)
        try container.encode(isImplicit, forKey: .isImplicit)
        try super.encode(to: encoder)
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.pkgConfig = try container.decodeIfPresent(String.self, forKey: .pkgConfig)
        self.providers = try container.decodeIfPresent([SystemPackageProviderDescription].self, forKey: .providers)
        self.isImplicit = try container.decode(Bool.self, forKey: .isImplicit)
        try super.init(from: decoder)
    }
}

public final class ClangTarget: Target {

    /// The default public include directory component.
    public static let defaultPublicHeadersComponent = "include"

    /// The path to include directory.
    public let includeDir: AbsolutePath

    /// The target's module map type, which determines whether this target vends a custom module map, a generated module map, or no module map at all.
    public let moduleMapType: ModuleMapType

    /// The headers present in the target.
    ///
    /// Note that this contains both public and non-public headers.
    public let headers: [AbsolutePath]

    /// True if this is a C++ target.
    public let isCXX: Bool

    /// The C language standard flag.
    public let cLanguageStandard: String?

    /// The C++ language standard flag.
    public let cxxLanguageStandard: String?

    public init(
        name: String,
        bundleName: String? = nil,
        defaultLocalization: String? = nil,
        platforms: [SupportedPlatform] = [],
        cLanguageStandard: String?,
        cxxLanguageStandard: String?,
        includeDir: AbsolutePath,
        moduleMapType: ModuleMapType,
        headers: [AbsolutePath] = [],
        type: Kind,
        sources: Sources,
        resources: [Resource] = [],
        ignored: [AbsolutePath] = [],
        others: [AbsolutePath] = [],
        dependencies: [Target.Dependency] = [],
        buildSettings: BuildSettings.AssignmentTable = .init()
    ) throws {
        guard includeDir.isDescendantOfOrEqual(to: sources.root) else {
            throw StringError("\(includeDir) should be contained in the source root \(sources.root)")
        }
        self.isCXX = sources.containsCXXFiles
        self.cLanguageStandard = cLanguageStandard
        self.cxxLanguageStandard = cxxLanguageStandard
        self.includeDir = includeDir
        self.moduleMapType = moduleMapType
        self.headers = headers
        super.init(
            name: name,
            bundleName: bundleName,
            defaultLocalization: defaultLocalization,
            platforms: platforms,
            type: type,
            sources: sources,
            resources: resources,
            ignored: ignored,
            others: others,
            dependencies: dependencies,
            buildSettings: buildSettings,
            pluginUsages: []
        )
    }

    private enum CodingKeys: String, CodingKey {
        case includeDir, moduleMapType, headers, isCXX, cLanguageStandard, cxxLanguageStandard
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(includeDir, forKey: .includeDir)
        try container.encode(moduleMapType, forKey: .moduleMapType)
        try container.encode(headers, forKey: .headers)
        try container.encode(isCXX, forKey: .isCXX)
        try container.encode(cLanguageStandard, forKey: .cLanguageStandard)
        try container.encode(cxxLanguageStandard, forKey: .cxxLanguageStandard)
        try super.encode(to: encoder)
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.includeDir = try container.decode(AbsolutePath.self, forKey: .includeDir)
        self.moduleMapType = try container.decode(ModuleMapType.self, forKey: .moduleMapType)
        self.headers = try container.decode([AbsolutePath].self, forKey: .headers)
        self.isCXX = try container.decode(Bool.self, forKey: .isCXX)
        self.cLanguageStandard = try container.decodeIfPresent(String.self, forKey: .cLanguageStandard)
        self.cxxLanguageStandard = try container.decodeIfPresent(String.self, forKey: .cxxLanguageStandard)
        try super.init(from: decoder)
    }
}

public final class BinaryTarget: Target {
    /// The kind of binary artifact.
    public let kind: Kind

    /// The original source of the binary artifact.
    public let origin: Origin

    /// The binary artifact path.
    public var artifactPath: AbsolutePath {
        return self.sources.root
    }

    public init(
        name: String,
        kind: Kind,
        platforms: [SupportedPlatform] = [],
        path: AbsolutePath,
        origin: Origin
    ) {
        self.origin = origin
        self.kind = kind
        let sources = Sources(paths: [], root: path)
        super.init(
            name: name,
            defaultLocalization: nil,
            platforms: platforms,
            type: .binary,
            sources: sources,
            dependencies: [],
            buildSettings: .init(),
            pluginUsages: []
        )
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case origin
        case artifactSource // backwards compatibility 2/2021
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.origin, forKey: .origin)
        try container.encode(self.kind, forKey: .kind)
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // backwards compatibility 2/2021
        if !container.contains(.kind) {
            self.kind = .xcframework
        } else {
            self.kind = try container.decode(Kind.self, forKey: .kind)
        }
        // backwards compatibility 2/2021
        if container.contains(.artifactSource)  {
            self.origin = try container.decode(Origin.self, forKey: .artifactSource)
        } else {
            self.origin = try container.decode(Origin.self, forKey: .origin)
        }
        try super.init(from: decoder)
    }

    public enum Kind: String, RawRepresentable, Codable, CaseIterable {
        case xcframework
        case artifactsArchive
        case unknown // for non-downloaded artifacts

        public var fileExtension: String {
            switch self {
            case .xcframework:
                return "xcframework"
            case .artifactsArchive:
                return "artifactbundle"
            case .unknown:
                return "unknown"
            }
        }

        public static func forFileExtension(_ fileExtension: String) throws -> Kind {
            guard let kind = Kind.allCases.first(where: { $0.fileExtension == fileExtension }) else {
                throw StringError("unknown binary artifact file extension '\(fileExtension)'")
            }
            return kind
        }
    }

    public enum Origin: Equatable, Codable {

        /// Represents an artifact that was downloaded from a remote URL.
        case remote(url: String)

        /// Represents an artifact that was available locally.
        case local

        private enum CodingKeys: String, CodingKey {
            case remote, local
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .remote(let a1):
                var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .remote)
                try unkeyedContainer.encode(a1)
            case .local:
                try container.encodeNil(forKey: .local)
            }
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            guard let key = values.allKeys.first(where: values.contains) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
            }
            switch key {
            case .remote:
                var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
                let a1 = try unkeyedValues.decode(String.self)
                self = .remote(url: a1)
            case .local:
                self = .local
            }
        }
    }
}

public final class PluginTarget: Target {

    /// Declared capability of the plugin.
    public let capability: PluginCapability
    
    /// API version to use for PackagePlugin API availability.
    public let apiVersion: ToolsVersion

    public init(
        name: String,
        platforms: [SupportedPlatform] = [],
        sources: Sources,
        apiVersion: ToolsVersion,
        pluginCapability: PluginCapability,
        dependencies: [Target.Dependency] = []
    ) {
        self.capability = pluginCapability
        self.apiVersion = apiVersion
        super.init(
            name: name,
            defaultLocalization: nil,
            platforms: platforms,
            type: .plugin,
            sources: sources,
            dependencies: dependencies,
            buildSettings: .init(),
            pluginUsages: []
        )
    }

    private enum CodingKeys: String, CodingKey {
        case capability
        case apiVersion
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.capability, forKey: .capability)
        try container.encode(self.apiVersion, forKey: .apiVersion)
        try super.encode(to: encoder)
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.capability = try container.decode(PluginCapability.self, forKey: .capability)
        self.apiVersion = try container.decode(ToolsVersion.self, forKey: .apiVersion)
        try super.init(from: decoder)
    }
}

public enum PluginCapability: Hashable, Codable {
    case buildTool
    case command(intent: PluginCommandIntent, permissions: [PluginPermission])

    private enum CodingKeys: String, CodingKey {
        case buildTool, command
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .buildTool:
            try container.encodeNil(forKey: .buildTool)
        case .command(let a1, let a2):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .command)
            try unkeyedContainer.encode(a1)
            try unkeyedContainer.encode(a2)
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = values.allKeys.first(where: values.contains) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
        }
        switch key {
        case .buildTool:
            self = .buildTool
        case .command:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let a1 = try unkeyedValues.decode(PluginCommandIntent.self)
            let a2 = try unkeyedValues.decode([PluginPermission].self)
            self = .command(intent: a1, permissions: a2)
        }
    }

    public init(from desc: TargetDescription.PluginCapability) {
        switch desc {
        case .buildTool:
            self = .buildTool
        case .command(let intent, let permissions):
            self = .command(intent: .init(from: intent), permissions: permissions.map{ .init(from: $0) })
        }
    }
}

public enum PluginCommandIntent: Hashable, Codable {
    case documentationGeneration
    case sourceCodeFormatting
    case custom(verb: String, description: String)

    public init(from desc: TargetDescription.PluginCommandIntent) {
        switch desc {
        case .documentationGeneration:
            self = .documentationGeneration
        case .sourceCodeFormatting:
            self = .sourceCodeFormatting
        case .custom(let verb, let description):
            self = .custom(verb: verb, description: description)
        }
    }
}

public enum PluginPermission: Hashable, Codable {
    case writeToPackageDirectory(reason: String)

    public init(from desc: TargetDescription.PluginPermission) {
        switch desc {
        case .writeToPackageDirectory(let reason):
            self = .writeToPackageDirectory(reason: reason)
        }
    }
}
