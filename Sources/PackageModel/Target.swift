//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import TSCBasic
import Dispatch

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
        case `macro`
    }

    /// A group a target belongs to that allows customizing access boundaries. A target is treated as
    /// a client outside of the package if `excluded`, inside the package boundary if `package`.
    public enum Group: Codable, Equatable {
        case package
        case excluded
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

        /// Fully qualified name for this product dependency: package ID + name of the product
        public var identity: String {
            if let package {
                return package.lowercased() + "_" + name
            } else {
                // this is hit only if this product is referenced `.byName(name)`
                // which assumes the name of this product, its package, and its target
                // all have the same name
                return name.lowercased() + "_" + name
            }
        }

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

    /// The group this target belongs to, where access to the target's group-specific
    /// APIs is not allowed from outside.
    public private(set) var group: Group

    /// Module aliases needed to build this target. The key is an original name of a
    /// dependent target and the value is a new unique name mapped to the name
    /// of its .swiftmodule binary.
    public private(set) var moduleAliases: [String: String]?
    /// Used to store pre-chained / pre-overriden module aliases
    public private(set) var prechainModuleAliases: [String: String]?
    /// Used to store aliases that should be referenced directly in source code
    public private(set) var directRefAliases: [String: [String]]?

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
    }

    public func removeModuleAlias(for name: String) {
        moduleAliases?.removeValue(forKey: name)
        if moduleAliases?.isEmpty ?? false {
            moduleAliases = nil
        }
    }

    public func addPrechainModuleAlias(for name: String, as alias: String) {
        if prechainModuleAliases == nil {
            prechainModuleAliases = [name: alias]
        } else {
            prechainModuleAliases?[name] = alias
        }
    }
    public func addDirectRefAliases(for name: String, as aliases: [String]) {
        if directRefAliases == nil {
            directRefAliases = [name: aliases]
        } else {
            directRefAliases?[name] = aliases
        }
    }

    @discardableResult
    public func applyAlias() -> Bool {
        // If there's an alias for this target, rename
        if let alias = moduleAliases?[name] {
            self.name = alias
            self.c99name = alias.spm_mangledToC99ExtendedIdentifier()
            return true
        }
        return false
    }

    /// The dependencies of this target.
    public let dependencies: [Dependency]

    /// The language-level target name.
    public private(set) var c99name: String

    /// The bundle name, if one is being generated.
    public var bundleName: String? {
        return resources.isEmpty ? nil : potentialBundleName
    }
    public let potentialBundleName: String?

    /// Suffix that's expected for test targets.
    public static let testModuleNameSuffix = "Tests"

    /// The kind of target.
    public let type: Kind

    /// The path of the target.
    public let path: AbsolutePath

    /// The sources for the target.
    public let sources: Sources

    /// The resource files in the target.
    public let resources: [Resource]

    /// Files in the target that were marked as ignored.
    public let ignored: [AbsolutePath]

    /// Other kinds of files in the target.
    public let others: [AbsolutePath]

    /// The build settings assignments of this target.
    public let buildSettings: BuildSettings.AssignmentTable

    /// The usages of package plugins by this target.
    public let pluginUsages: [PluginUsage]

    /// Whether or not this target uses any custom unsafe flags.
    public let usesUnsafeFlags: Bool

    fileprivate init(
        name: String,
        potentialBundleName: String? = nil,
        group: Group,
        type: Kind,
        path: AbsolutePath,
        sources: Sources,
        resources: [Resource] = [],
        ignored: [AbsolutePath] = [],
        others: [AbsolutePath] = [],
        dependencies: [Target.Dependency],
        buildSettings: BuildSettings.AssignmentTable,
        pluginUsages: [PluginUsage],
        usesUnsafeFlags: Bool
    ) {
        self.name = name
        self.potentialBundleName = potentialBundleName
        self.group = group
        self.type = type
        self.path = path
        self.sources = sources
        self.resources = resources
        self.ignored = ignored
        self.others = others
        self.dependencies = dependencies
        self.c99name = self.name.spm_mangledToC99ExtendedIdentifier()
        self.buildSettings = buildSettings
        self.pluginUsages = pluginUsages
        self.usesUnsafeFlags = usesUnsafeFlags
    }

    private enum CodingKeys: String, CodingKey {
        case name, potentialBundleName, group, defaultLocalization, platforms, type, path, sources, resources, ignored, others, buildSettings, pluginUsages, usesUnsafeFlags
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // FIXME: dependencies property is skipped on purpose as it points to
        // the actual target dependency object.
        try container.encode(name, forKey: .name)
        try container.encode(potentialBundleName, forKey: .potentialBundleName)
        try container.encode(group, forKey: .group)
        try container.encode(type, forKey: .type)
        try container.encode(path, forKey: .path)
        try container.encode(sources, forKey: .sources)
        try container.encode(resources, forKey: .resources)
        try container.encode(ignored, forKey: .ignored)
        try container.encode(others, forKey: .others)
        try container.encode(buildSettings, forKey: .buildSettings)
        // FIXME: pluginUsages property is skipped on purpose as it points to
        // the actual target dependency object.
        try container.encode(usesUnsafeFlags, forKey: .usesUnsafeFlags)
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.potentialBundleName = try container.decodeIfPresent(String.self, forKey: .potentialBundleName)
        self.group = try container.decode(Group.self, forKey: .group)
        self.type = try container.decode(Kind.self, forKey: .type)
        self.path = try container.decode(AbsolutePath.self, forKey: .path)
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
        self.usesUnsafeFlags = try container.decode(Bool.self, forKey: .usesUnsafeFlags)
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

extension Target.Group {
    public init(_ group: TargetDescription.TargetGroup) {
        switch group {
        case .package: self = .package
        case .excluded: self = .excluded
        }
    }
}
public final class SwiftTarget: Target {

    /// The default name for the test entry point file located in a package.
    public static let defaultTestEntryPointName = "XCTMain.swift"

    /// The list of all supported names for the test entry point file located in a package.
    public static var testEntryPointNames: [String] {
        [defaultTestEntryPointName, "LinuxMain.swift"]
    }

    public init(name: String, group: Target.Group, dependencies: [Target.Dependency], testDiscoverySrc: Sources) {
        self.swiftVersion = .v5

        super.init(
            name: name,
            group: group,
            type: .library,
            path: .root,
            sources: testDiscoverySrc,
            dependencies: dependencies,
            buildSettings: .init(),
            pluginUsages: [],
            usesUnsafeFlags: false
        )
    }

    /// The swift version of this target.
    public let swiftVersion: SwiftLanguageVersion

    public init(
        name: String,
        potentialBundleName: String? = nil,
        group: Target.Group,
        type: Kind,
        path: AbsolutePath,
        sources: Sources,
        resources: [Resource] = [],
        ignored: [AbsolutePath] = [],
        others: [AbsolutePath] = [],
        dependencies: [Target.Dependency] = [],
        swiftVersion: SwiftLanguageVersion,
        buildSettings: BuildSettings.AssignmentTable = .init(),
        pluginUsages: [PluginUsage] = [],
        usesUnsafeFlags: Bool
    ) {
        self.swiftVersion = swiftVersion
        super.init(
            name: name,
            potentialBundleName: potentialBundleName,
            group: group,
            type: type,
            path: path,
            sources: sources,
            resources: resources,
            ignored: ignored,
            others: others,
            dependencies: dependencies,
            buildSettings: buildSettings,
            pluginUsages: pluginUsages,
            usesUnsafeFlags: usesUnsafeFlags
        )
    }

    /// Create an executable Swift target from test entry point file.
    public init(name: String, group: Target.Group, dependencies: [Target.Dependency], testEntryPointPath: AbsolutePath) {
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
        self.swiftVersion = swiftTestTarget?.swiftVersion ?? SwiftLanguageVersion(string: String(SwiftVersion.current.major)) ?? .v4
        let sources = Sources(paths: [testEntryPointPath], root: testEntryPointPath.parentDirectory)

        super.init(
            name: name,
            group: group,
            type: .executable,
            path: .root,
            sources: sources,
            dependencies: dependencies,
            buildSettings: .init(),
            pluginUsages: [],
            usesUnsafeFlags: false
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

    public var supportsTestableExecutablesFeature: Bool {
        // Exclude macros from testable executables if they are built as dylibs.
        #if BUILD_MACROS_AS_DYLIBS
        return type == .executable || type == .snippet
        #else
        return type == .executable || type == .macro || type == .snippet
        #endif
    }
}

public final class SystemLibraryTarget: Target {

    /// The name of pkgConfig file, if any.
    public let pkgConfig: String?

    /// List of system package providers, if any.
    public let providers: [SystemPackageProviderDescription]?

    /// True if this system library should become implicit target
    /// dependency of its dependent packages.
    public let isImplicit: Bool

    public init(
        name: String,
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
            group: .excluded, // access to only public APIs is allowed for system libs
            type: .systemModule,
            path: sources.root,
            sources: sources,
            dependencies: [],
            buildSettings: .init(),
            pluginUsages: [],
            usesUnsafeFlags: false
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
        potentialBundleName: String? = nil,
        cLanguageStandard: String?,
        cxxLanguageStandard: String?,
        includeDir: AbsolutePath,
        moduleMapType: ModuleMapType,
        headers: [AbsolutePath] = [],
        type: Kind,
        path: AbsolutePath,
        sources: Sources,
        resources: [Resource] = [],
        ignored: [AbsolutePath] = [],
        others: [AbsolutePath] = [],
        dependencies: [Target.Dependency] = [],
        buildSettings: BuildSettings.AssignmentTable = .init(),
        usesUnsafeFlags: Bool
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
            potentialBundleName: potentialBundleName,
            group: .excluded, // group is no-op for non-Swift modules
            type: type,
            path: path,
            sources: sources,
            resources: resources,
            ignored: ignored,
            others: others,
            dependencies: dependencies,
            buildSettings: buildSettings,
            pluginUsages: [],
            usesUnsafeFlags: usesUnsafeFlags
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
        path: AbsolutePath,
        origin: Origin
    ) {
        self.origin = origin
        self.kind = kind
        let sources = Sources(paths: [], root: path)
        super.init(
            name: name,
            group: .excluded, // access to only public APIs is allowed for binary targets
            type: .binary,
            path: .root,
            sources: sources,
            dependencies: [],
            buildSettings: .init(),
            pluginUsages: [],
            usesUnsafeFlags: false
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
    }

    public var containsExecutable: Bool {
        // FIXME: needs to be revisited once libraries are supported in artifact bundles
        return self.kind == .artifactsArchive
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
        group: Target.Group,
        sources: Sources,
        apiVersion: ToolsVersion,
        pluginCapability: PluginCapability,
        dependencies: [Target.Dependency] = []
    ) {
        self.capability = pluginCapability
        self.apiVersion = apiVersion
        super.init(
            name: name,
            group: group,
            type: .plugin,
            path: .root,
            sources: sources,
            dependencies: dependencies,
            buildSettings: .init(),
            pluginUsages: [],
            usesUnsafeFlags: false
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

public enum PluginNetworkPermissionScope: Hashable, Codable {
    case none
    case local(ports: [UInt8])
    case all(ports: [UInt8])
    case docker
    case unixDomainSocket

    init(_ scope: TargetDescription.PluginNetworkPermissionScope) {
        switch scope {
        case .none: self = .none
        case .local(let ports): self = .local(ports: ports)
        case .all(let ports): self = .all(ports: ports)
        case .docker: self = .docker
        case .unixDomainSocket: self = .unixDomainSocket
        }
    }

    public var label: String {
        switch self {
        case .all: return "all"
        case .local: return "local"
        case .none: return "none"
        case .docker: return "docker unix domain socket"
        case .unixDomainSocket: return "unix domain socket"
        }
    }

    public var ports: [UInt8] {
        switch self {
        case .all(let ports): return ports
        case .local(let ports): return ports
        case .none, .docker, .unixDomainSocket: return []
        }
    }
}

public enum PluginPermission: Hashable, Codable {
    case allowNetworkConnections(scope: PluginNetworkPermissionScope, reason: String)
    case writeToPackageDirectory(reason: String)

    public init(from desc: TargetDescription.PluginPermission) {
        switch desc {
        case .allowNetworkConnections(let scope, let reason):
            self = .allowNetworkConnections(scope: .init(scope), reason: reason)
        case .writeToPackageDirectory(let reason):
            self = .writeToPackageDirectory(reason: reason)
        }
    }
}

public extension Sequence where Iterator.Element == Target {
    var executables: [Target] {
        return filter {
            switch $0.type {
            case .binary:
                return ($0 as? BinaryTarget)?.containsExecutable == true
            case .executable, .snippet, .macro:
                return true
            default:
                return false
            }
        }
    }
}
