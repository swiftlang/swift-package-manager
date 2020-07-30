/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import TSCUtility

public class Target: ObjectIdentifierProtocol, PolymorphicCodableProtocol {
    public static var implementations: [PolymorphicCodableProtocol.Type] = [
        SwiftTarget.self,
        ClangTarget.self,
        SystemLibraryTarget.self,
        BinaryTarget.self,
    ]

    /// The target kind.
    public enum Kind: String, Codable {
        case executable
        case library
        case systemModule = "system-target"
        case test
        case binary
    }

    /// A reference to a product from a target dependency.
    public struct ProductReference: Codable {

        /// The name of the product dependency.
        public let name: String

        /// The name of the package containing the product.
        public let package: String?

        /// Creates a product reference instance.
        public init(name: String, package: String?) {
            self.name = name
            self.package = package
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

    /// The name of the target.
    ///
    /// NOTE: This name is not the language-level target (i.e., the importable
    /// name) name in many cases, instead use c99name if you need uniqueness.
    public let name: String

    /// The default localization for resources.
    public let defaultLocalization: String?

    /// The dependencies of this target.
    public let dependencies: [Dependency]

    /// The language-level target name.
    public let c99name: String

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

    /// The list of platforms that are supported by this target.
    public let platforms: [SupportedPlatform]

    /// Returns the supported platform instance for the given platform.
    public func getSupportedPlatform(for platform: Platform) -> SupportedPlatform? {
        return self.platforms.first(where: { $0.platform == platform })
    }

    /// The build settings assignments of this target.
    public let buildSettings: BuildSettings.AssignmentTable

    fileprivate init(
        name: String,
        bundleName: String? = nil,
        defaultLocalization: String?,
        platforms: [SupportedPlatform],
        type: Kind,
        sources: Sources,
        resources: [Resource] = [],
        dependencies: [Target.Dependency],
        buildSettings: BuildSettings.AssignmentTable
    ) {
        self.name = name
        self.bundleName = bundleName
        self.defaultLocalization = defaultLocalization
        self.platforms = platforms
        self.type = type
        self.sources = sources
        self.resources = resources
        self.dependencies = dependencies
        self.c99name = self.name.spm_mangledToC99ExtendedIdentifier()
        self.buildSettings = buildSettings
    }

    private enum CodingKeys: String, CodingKey {
        case name, bundleName, defaultLocalization, platforms, type, sources, resources, buildSettings
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
        try container.encode(buildSettings, forKey: .buildSettings)
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
        // FIXME: dependencies property is skipped on purpose as it points to
        // the actual target dependency object.
        self.dependencies = []
        self.c99name = self.name.spm_mangledToC99ExtendedIdentifier()
        self.buildSettings = try container.decode(BuildSettings.AssignmentTable.self, forKey: .buildSettings)
    }
}

public class SwiftTarget: Target {

    /// The file name of linux main file.
    public static let linuxMainBasename = "LinuxMain.swift"

    public init(testDiscoverySrc: Sources, name: String, dependencies: [Target.Dependency]) {
        self.swiftVersion = .v5

        super.init(
            name: name,
            defaultLocalization: nil,
            platforms: [],
            type: .executable,
            sources: testDiscoverySrc,
            dependencies: dependencies,
            buildSettings: .init()
        )
    }

    /// Create an executable Swift target from linux main test manifest file.
    init(linuxMain: AbsolutePath, name: String, dependencies: [Target.Dependency]) {
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
        let sources = Sources(paths: [linuxMain], root: linuxMain.parentDirectory)

        let platforms: [SupportedPlatform] = swiftTestTarget?.platforms ?? []

        super.init(
            name: name,
            defaultLocalization: nil,
            platforms: platforms,
            type: .executable,
            sources: sources,
            dependencies: dependencies,
            buildSettings: .init()
        )
    }

    /// The swift version of this target.
    public let swiftVersion: SwiftLanguageVersion

    public init(
        name: String,
        bundleName: String? = nil,
        defaultLocalization: String? = nil,
        platforms: [SupportedPlatform] = [],
        isTest: Bool = false,
        sources: Sources,
        resources: [Resource] = [],
        dependencies: [Target.Dependency] = [],
        swiftVersion: SwiftLanguageVersion,
        buildSettings: BuildSettings.AssignmentTable = .init()
    ) {
        let type: Kind = isTest ? .test : sources.computeTargetType()
        self.swiftVersion = swiftVersion
        super.init(
            name: name,
            bundleName: bundleName,
            defaultLocalization: defaultLocalization,
            platforms: platforms,
            type: type,
            sources: sources,
            resources: resources,
            dependencies: dependencies,
            buildSettings: buildSettings
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

public class SystemLibraryTarget: Target {

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
            buildSettings: .init()
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

public class ClangTarget: Target {

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
        isTest: Bool = false,
        sources: Sources,
        resources: [Resource] = [],
        dependencies: [Target.Dependency] = [],
        buildSettings: BuildSettings.AssignmentTable = .init()
    ) {
        assert(includeDir.contains(sources.root), "\(includeDir) should be contained in the source root \(sources.root)")
        let type: Kind = isTest ? .test : sources.computeTargetType()
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
            dependencies: dependencies,
            buildSettings: buildSettings
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

public class BinaryTarget: Target {

    /// The original source of the binary artifact.
    public enum ArtifactSource: Equatable {

        /// Represents an artifact that was downloaded from a remote URL.
        case remote(url: String)

        /// Represents an artifact that was available locally.
        case local
    }

    /// The binary artifact's source.
    public let artifactSource: ArtifactSource

    /// The binary artifact path.
    public var artifactPath: AbsolutePath {
        return sources.root
    }

    public init(
        name: String,
        platforms: [SupportedPlatform] = [],
        path: AbsolutePath,
        artifactSource: ArtifactSource
    ) {
        self.artifactSource = artifactSource
        let sources = Sources(paths: [], root: path)
        super.init(
            name: name,
            defaultLocalization: nil,
            platforms: platforms,
            type: .binary,
            sources: sources,
            dependencies: [],
            buildSettings: .init()
        )
    }

    private enum CodingKeys: String, CodingKey {
        case artifactSource
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(artifactSource, forKey: .artifactSource)
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.artifactSource = try container.decode(ArtifactSource.self, forKey: .artifactSource)
        try super.init(from: decoder)
    }
}

/// A type of module map layout.  Contains all the information needed to generate or use a module map for a target that can have C-style headers.
public enum ModuleMapType: Equatable, Codable {
    /// No module map file.
    case none
    /// A custom module map file.
    case custom(AbsolutePath)
    /// An umbrella header included by a generated module map file.
    case umbrellaHeader(AbsolutePath)
    /// An umbrella directory included by a generated module map file.
    case umbrellaDirectory(AbsolutePath)

    private enum CodingKeys: String, CodingKey {
        case none, custom, umbrellaHeader, umbrellaDirectory
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let path = try container.decodeIfPresent(AbsolutePath.self, forKey: .custom) {
            self = .custom(path)
        }
        else if let path = try container.decodeIfPresent(AbsolutePath.self, forKey: .umbrellaHeader) {
            self = .umbrellaHeader(path)
        }
        else if let path = try container.decodeIfPresent(AbsolutePath.self, forKey: .umbrellaDirectory) {
            self = .umbrellaDirectory(path)
        }
        else {
            self = .none
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            break
        case .custom(let path):
            try container.encode(path, forKey: .custom)
        case .umbrellaHeader(let path):
            try container.encode(path, forKey: .umbrellaHeader)
        case .umbrellaDirectory(let path):
            try container.encode(path, forKey: .umbrellaDirectory)
        }
    }
}

extension Target: CustomStringConvertible {
    public var description: String {
        return "<\(Swift.type(of: self)): \(name)>"
    }
}

extension Sources {
    /// Determine target type based on the sources.
    fileprivate func computeTargetType() -> Target.Kind {
        let isLibrary = !relativePaths.contains { path in
            let file = path.basename.lowercased()
            // Look for a main.xxx file avoiding cases like main.xxx.xxx
            return file.hasPrefix("main.") && String(file.filter({$0 == "."})).count == 1
        }
        return isLibrary ? .library : .executable
    }
}
