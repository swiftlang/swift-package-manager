/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import TSCUtility
import Foundation

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

    /// The revision this package was loaded from, if known.
    public let revision: String?

    /// The tools version declared in the manifest.
    public let toolsVersion: ToolsVersion

    /// The name of the package.
    public let name: String

    /// The default localization for resources.
    public let defaultLocalization: String?

    /// Whether kind of package this manifest is from.
    public let packageKind: PackageReference.Kind

    /// The declared platforms in the manifest.
    public let platforms: [PlatformDescription]

    /// The declared package dependencies.
    public let dependencies: [PackageDependencyDescription]

    /// The targets declared in the manifest.
    public let targets: [TargetDescription]

    /// The targets declared in the manifest, keyed by their name.
    public let targetMap: [String: TargetDescription]

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

    /// Targets required for building particular product filters.
    private var _requiredTargets: [ProductFilter: [TargetDescription]]

    /// Dependencies required for building particular product filters.
    private var _requiredDependencies: [ProductFilter: [FilteredDependencyDescription]]

    public init(
        name: String,
        defaultLocalization: String? = nil,
        platforms: [PlatformDescription],
        path: AbsolutePath,
        url: String,
        version: TSCUtility.Version? = nil,
        revision: String? = nil,
        toolsVersion: ToolsVersion,
        packageKind: PackageReference.Kind,
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
        self.defaultLocalization = defaultLocalization
        self.platforms = platforms
        self.path = path
        self.url = url
        self.version = version
        self.revision = revision
        self.toolsVersion = toolsVersion
        self.packageKind = packageKind
        self.pkgConfig = pkgConfig
        self.providers = providers
        self.cLanguageStandard = cLanguageStandard
        self.cxxLanguageStandard = cxxLanguageStandard
        self.swiftLanguageVersions = swiftLanguageVersions
        self.dependencies = dependencies
        self.products = products
        self.targets = targets
        self.targetMap = Dictionary(targets.lazy.map({ ($0.name, $0) }), uniquingKeysWith: { $1 })
        self._requiredTargets = [:]
        self._requiredDependencies = [:]
    }

    public var description: String {
        return "<Manifest: \(name)>"
    }

    /// Coding user info key for dump-package command.
    ///
    /// Presence of this key will hide some keys when encoding the Manifest object.
    public static let dumpPackageKey: CodingUserInfoKey = CodingUserInfoKey(rawValue: "dumpPackage")!
}

extension ToolsVersion {
    /// The subpath to the PackageDescription runtime library.
    public var runtimeSubpath: RelativePath {
        if self < .v4_2 {
            return RelativePath("4")
        }
        return RelativePath("4_2")
    }

    /// The swift language version based on this tools version.
    public var swiftLanguageVersion: SwiftLanguageVersion {
        switch major {
        case 4:
            // If the tools version is less than 4.2, use language version 4.
            if minor < 2 {
                return .v4
            }

            // Otherwise, use 4.2
            return .v4_2

        default:
            // Anything above 4 major version uses version 5.
            return .v5
        }
    }
}

extension Manifest {
    /// Returns the targets required for a particular product filter.
    public func targetsRequired(for productFilter: ProductFilter) -> [TargetDescription] {
        // If we have already calcualted it, returned the cached value.
        if let targets = _requiredTargets[productFilter] {
            return targets
        } else {
            let targets: [TargetDescription]
            switch productFilter {
            case .everything:
                return self.targets
            case .specific(let productFilter):
                let products = self.products.filter { productFilter.contains($0.name) }
                targets = targetsRequired(for: products)
            }

            _requiredTargets[productFilter] = targets
            return targets
        }
    }

    /// Returns the package dependencies required for a particular products filter.
    public func dependenciesRequired(for productFilter: ProductFilter) -> [FilteredDependencyDescription] {
        // If we have already calcualted it, returned the cached value.
        if let dependencies = _requiredDependencies[productFilter] {
            return dependencies
        } else {
            let targets = targetsRequired(for: productFilter)
            let dependencies = dependenciesRequired(for: targets, keepUnused: productFilter == .everything)
            _requiredDependencies[productFilter] = dependencies
            return dependencies
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)

        // Hide the keys that users shouldn't see when
        // we're encoding for the dump-package command.
        if encoder.userInfo[Manifest.dumpPackageKey] == nil {
            try container.encode(path, forKey: .path)
            try container.encode(url, forKey: .url)
            try container.encode(version, forKey: .version)
            try container.encode(targetMap, forKey: .targetMap)
        }

        try container.encode(toolsVersion, forKey: .toolsVersion)
        try container.encode(pkgConfig, forKey: .pkgConfig)
        try container.encode(providers, forKey: .providers)
        try container.encode(cLanguageStandard, forKey: .cLanguageStandard)
        try container.encode(cxxLanguageStandard, forKey: .cxxLanguageStandard)
        try container.encode(swiftLanguageVersions, forKey: .swiftLanguageVersions)
        try container.encode(dependencies, forKey: .dependencies)
        try container.encode(products, forKey: .products)
        try container.encode(targets, forKey: .targets)
        try container.encode(platforms, forKey: .platforms)
        try container.encode(packageKind, forKey: .packageKind)
    }

    /// Returns the targets required for building the provided products.
    public func targetsRequired(for products: [ProductDescription]) -> [TargetDescription] {
        let targetsByName = Dictionary(targets.map({ ($0.name, $0) }), uniquingKeysWith: { $1 })
        let productTargetNames = products.flatMap({ $0.targets })

        let dependentTargetNames = transitiveClosure(productTargetNames, successors: { targetName in
            targetsByName[targetName]?.dependencies.compactMap({ dependency in
                switch dependency {
                case .target(let name, _),
                     .byName(let name, _):
                    return targetsByName.keys.contains(name) ? name : nil
                default:
                    return nil
                }
            }) ?? []
        })

        let requiredTargetNames = Set(productTargetNames).union(dependentTargetNames)
        let requiredTargets = requiredTargetNames.compactMap({ targetsByName[$0] })
        return requiredTargets
    }

    /// Returns the package dependencies required for building the provided targets.
    ///
    /// The returned dependencies have their particular product filters registered. (To determine product filters without removing any dependencies from the list, specify `keepUnused: true`.)
    public func dependenciesRequired(
        for targets: [TargetDescription],
        keepUnused: Bool = false
    ) -> [FilteredDependencyDescription] {

        var registry: (known: [String: ProductFilter], unknown: Set<String>) = ([:], [])
        let availablePackages = Set(dependencies.lazy.map({ $0.name }))

        for target in targets {
            for targetDependency in target.dependencies {
                register(targetDependency: targetDependency, registry: &registry, availablePackages: availablePackages)
            }
        }

        // Products whose package could not be determined are marked as needed on every dependency.
        // (This way none of them filters such a product out.)
        var associations = registry.known
        let unknown = registry.unknown
        if !registry.unknown.isEmpty {
            for package in availablePackages {
                associations[package, default: .specific([])].formUnion(.specific(unknown))
            }
        }

        return dependencies.compactMap { dependency in
            if let filter = associations[dependency.name] {
                return FilteredDependencyDescription(declaration: dependency, productFilter: filter)
            } else if keepUnused {
                // Register that while the dependency was kept, no products are needed.
                return FilteredDependencyDescription(declaration: dependency, productFilter: .specific([]))
            } else {
                // Dependencies known to not have any relevant products are discarded.
                return nil
            }
        }
    }

    /// Finds the package dependency referenced by the specified target dependency.
    /// - Returns: Returns `nil` if the dependency is a target dependency, if it is a product dependency but has no
    /// package name (for tools versions less than 5.2), or if there were no dependencies with the provided name.
    public func packageDependency(
        referencedBy targetDependency: TargetDescription.Dependency
    ) -> PackageDependencyDescription? {
        let packageName: String

        switch targetDependency {
        case .product(_, package: let name?, _),
             .byName(name: let name, _):
            packageName = name
        default:
            return nil
        }

        return dependencies.first(where: { $0.name == packageName })
    }

    /// Registers a required product with a particular dependency if possible, or registers it as unknown.
    ///
    /// - Parameters:
    ///   - targetDependency: The target dependency to register.
    ///   - registry: The registry in which to record the assocation.
    ///   - availablePackages: The set of available packages.
    private func register(
        targetDependency: TargetDescription.Dependency,
        registry: inout (known: [String: ProductFilter], unknown: Set<String>),
        availablePackages: Set<String>
    ) {
        switch targetDependency {
        case .target:
            break
        case .product(let product, let package, _):
            if let package = package { // ≥ 5.2
                if !register(
                    product: product,
                    inPackage: package,
                    registry: &registry.known,
                    availablePackages: availablePackages) {
                        // This is an invalid manifest condition diagnosed later. (No such package.)
                        // Treating it as unknown gracefully allows resolution to continue for now.
                    registry.unknown.insert(product)
                }
            } else { // < 5.2
                registry.unknown.insert(product)
            }
        case .byName(let product, _):
            if toolsVersion < .v5_2 {
                // A by‐name entry might be a product from anywhere.
                if targets.contains(where: { $0.name == product }) {
                    // Save the resolver some effort if it is known to only be a target anyway.
                    break
                } else {
                    registry.unknown.insert(product)
                }
            } else { // ≥ 5.2
                // If a by‐name entry is a product, it must be in a package of the same name.
                if !register(
                    product: product,
                    inPackage: product,
                    registry: &registry.known,
                    availablePackages: availablePackages) {
                        // If it doesn’t match a package, it should be a target, not a product.
                        if targets.contains(where: { $0.name == product }) {
                            break
                        } else {
                            // But in case the user is trying to reference a product,
                            // we still need to pass on the invalid reference
                            // so that the resolver fetches all dependencies
                            // in order to provide the diagnostic pass with the information it needs.
                            registry.unknown.insert(product)
                        }
                }
            }
        }
    }

    /// Registers a required product with a particular dependency if possible.
    ///
    /// - Parameters:
    ///   - product: The product to try registering.
    ///   - package: The package to try associating it with.
    ///   - registry: The registry in which to record the assocation.
    ///   - availablePackages: The set of available packages.
    ///
    /// - Returns: `true` if the particular dependency was found and the product was registered; `false` if no matching dependency was found and the product has not yet been handled.
    private func register(
        product: String,
        inPackage package: String,
        registry: inout [String: ProductFilter],
        availablePackages: Set<String>
    ) -> Bool {
        if let existing = registry[package] {
            registry[package] = existing.union(.specific([product]))
            return true
        } else if availablePackages.contains(package) {
            registry[package] = .specific([product])
            return true
        } else {
            return false
        }
    }
}

/// The description of an individual target.
public struct TargetDescription: Equatable, Codable {

    /// The target type.
    public enum TargetType: String, Equatable, Codable {
        case regular
        case test
        case system
        case binary
    }

    /// Represents a target's dependency on another entity.
    public enum Dependency: Equatable, ExpressibleByStringLiteral {
        case target(name: String, condition: PackageConditionDescription?)
        case product(name: String, package: String?, condition: PackageConditionDescription?)
        case byName(name: String, condition: PackageConditionDescription?)

        public init(stringLiteral value: String) {
            self = .byName(name: value, condition: nil)
        }

        public static func target(name: String) -> Dependency {
            return .target(name: name, condition: nil)
        }

        public static func product(name: String, package: String? = nil) -> Dependency {
            return .product(name: name, package: package, condition: nil)
        }
    }

    public struct Resource: Codable, Equatable {
        public enum Rule: String, Codable, Equatable {
            case process
            case copy
        }

        public enum Localization: String, Codable, Equatable {
            case `default`
            case base
        }

        /// The rule for the resource.
        public let rule: Rule

        /// The path of the resource.
        public let path: String

        /// The explicit localization of the resource.
        public let localization: Localization?

        public init(rule: Rule, path: String, localization: Localization? = nil) {
            precondition(rule == .process || localization == nil)
            self.rule = rule
            self.path = path
            self.localization = localization
        }
    }

    /// The name of the target.
    public let name: String

    /// The custom path of the target.
    public let path: String?

    /// The url of the binary target artifact.
    public let url: String?

    /// The custom sources of the target.
    public let sources: [String]?

    /// The explicitly declared resources of the target.
    public let resources: [Resource]

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

    /// The binary target checksum.
    public let checksum: String?

    public init(
        name: String,
        dependencies: [Dependency] = [],
        path: String? = nil,
        url: String? = nil,
        exclude: [String] = [],
        sources: [String]? = nil,
        resources: [Resource] = [],
        publicHeadersPath: String? = nil,
        type: TargetType = .regular,
        pkgConfig: String? = nil,
        providers: [SystemPackageProviderDescription]? = nil,
        settings: [TargetBuildSettingDescription.Setting] = [],
        checksum: String? = nil
    ) {
        switch type {
        case .regular, .test:
            precondition(
                url == nil &&
                pkgConfig == nil &&
                providers == nil &&
                checksum == nil
            )
        case .system:
            precondition(
                dependencies.isEmpty &&
                exclude.isEmpty &&
                sources == nil &&
                resources.isEmpty &&
                publicHeadersPath == nil &&
                settings.isEmpty &&
                checksum == nil
            )
        case .binary:
            precondition(path != nil || url != nil)
            precondition(
                dependencies.isEmpty &&
                exclude.isEmpty &&
                sources == nil &&
                resources.isEmpty &&
                publicHeadersPath == nil &&
                pkgConfig == nil &&
                providers == nil &&
                settings.isEmpty
            )
        }

        self.name = name
        self.dependencies = dependencies
        self.path = path
        self.url = url
        self.publicHeadersPath = publicHeadersPath
        self.sources = sources
        self.exclude = exclude
        self.resources = resources
        self.type = type
        self.pkgConfig = pkgConfig
        self.providers = providers
        self.settings = settings
        self.checksum = checksum
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
    case yum([String])
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

        public static func upToNextMajor(from version: TSCUtility.Version) -> Requirement {
            return .range(version..<Version(version.major + 1, 0, 0))
        }

        public static func upToNextMinor(from version: TSCUtility.Version) -> Requirement {
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

    /// The name of the dependency explicitly defined in the manifest.
    public let explicitName: String?

    /// The name of the dependency, either explicitly defined in the manifest, or deduced from the URL.
    public let name: String

    /// The url of the dependency.
    public let url: String

    /// The dependency requirement.
    public let requirement: Requirement

    /// Create a dependency.
    public init(name: String?, url: String, requirement: Requirement) {
        self.explicitName = name
        self.name = name ?? PackageReference.computeDefaultName(fromURL: url)
        self.url = url
        self.requirement = requirement
    }
}

/// The products requested of a package.
///
/// Any product which matches the filter will be used for dependency resolution, whereas unrequested products will be ingored.
///
/// Requested products need not actually exist in the package. Under certain circumstances, the resolver may request names whose package of origin are unknown. The intended package will recognize and fullfill the request; packages that do not know what it is will simply ignore it.
public enum ProductFilter: Equatable, Hashable, Codable, JSONMappable, JSONSerializable, CustomStringConvertible {

    /// All products, targets, and tests are requested.
    ///
    /// This is used for root packages.
    case everything

    /// A set of specific products requested by one or more client packages.
    case specific(Set<String>)

    public func union(_ other: ProductFilter) -> ProductFilter {
        switch self {
        case .everything:
            return .everything
        case .specific(let set):
            switch other {
            case .everything:
                return .everything
            case .specific(let otherSet):
                return .specific(set.union(otherSet))
            }
        }
    }
    public mutating func formUnion(_ other: ProductFilter) {
        self = self.union(other)
    }

    public func contains(_ product: String) -> Bool {
        switch self {
        case .everything:
            return true
        case .specific(let set):
            return set.contains(product)
        }
    }

    public func encode(to encoder: Encoder) throws {
        let optionalSet: Set<String>?
        switch self {
        case .everything:
            optionalSet = nil
        case .specific(let set):
            optionalSet = set
        }
        var container = encoder.singleValueContainer()
        try container.encode(optionalSet?.sorted())
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let optionalSet: Set<String>? = try container.decode([String]?.self).map { Set($0) }
        if let set = optionalSet {
            self = .specific(set)
        } else {
            self = .everything
        }
    }

    public func toJSON() -> JSON {
        switch self {
        case .everything:
            return "all".toJSON()
        case .specific(let products):
            return products.sorted().toJSON()
        }
    }
    public init(json: JSON) throws {
        if let products = try? [String](json: json) {
            self = .specific(Set(products))
        } else {
            self = .everything
        }
    }

    public var description: String {
        switch self {
        case .everything:
            return "[everything]"
        case .specific(let set):
            return "[\(set.sorted().joined(separator: ", "))]"
        }
    }
}

/// A dependency description along with its associated product filter.
public struct FilteredDependencyDescription: Codable {

    /// Creates a filtered dependency.
    ///
    /// - Parameters:
    ///   - declaration: The raw dependency.
    ///   - productFilter: The product filter to apply.
    public init(declaration: PackageDependencyDescription, productFilter: ProductFilter) {
        self.declaration = declaration
        self.productFilter = productFilter
    }

    /// The loaded dependency declaration.
    public let declaration: PackageDependencyDescription

    /// The resolved product filter.
    public let productFilter: ProductFilter
}

public struct PlatformDescription: Codable, Equatable {
    public let platformName: String
    public let version: String
    public let options: [String]

    public init(name: String, version: String, options: [String] = []) {
        self.platformName = name
        self.version = version
        self.options = options
    }
}

/// Represents a manifest condition.
public struct PackageConditionDescription: Codable, Equatable {
    public let platformNames: [String]
    public let config: String?

    public init(platformNames: [String] = [], config: String? = nil) {
        assert(!(platformNames.isEmpty && config == nil))
        self.platformNames = platformNames
        self.config = config
    }
}

/// A namespace for target-specific build settings.
public enum TargetBuildSettingDescription {

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
        public let condition: PackageConditionDescription?

        /// The value of the setting.
        ///
        /// This is kind of like an "untyped" value since the length
        /// of the array will depend on the setting type.
        public let value: [String]

        public init(
            tool: Tool,
            name: SettingName,
            value: [String],
            condition: PackageConditionDescription? = nil
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

/// The configuration of the build environment.
public enum BuildConfiguration: String, CaseIterable, Codable {
    case debug
    case release

    public var dirname: String {
        switch self {
            case .debug: return "debug"
            case .release: return "release"
        }
    }
}

/// A build environment with which to evaluation conditions.
public struct BuildEnvironment: Codable {
    public let platform: Platform
    public let configuration: BuildConfiguration

    public init(platform: Platform, configuration: BuildConfiguration) {
        self.platform = platform
        self.configuration = configuration
    }
}

/// A manifest condition.
public protocol PackageConditionProtocol: Codable {
    func satisfies(_ environment: BuildEnvironment) -> Bool
}

/// Platforms condition implies that an assignment is valid on these platforms.
public struct PlatformsCondition: PackageConditionProtocol {
    public let platforms: [Platform]

    public init(platforms: [Platform]) {
        assert(!platforms.isEmpty, "List of platforms should not be empty")
        self.platforms = platforms
    }

    public func satisfies(_ environment: BuildEnvironment) -> Bool {
        platforms.contains(environment.platform)
    }
}

/// A configuration condition implies that an assignment is valid on
/// a particular build configuration.
public struct ConfigurationCondition: PackageConditionProtocol {
    public let configuration: BuildConfiguration

    public init(configuration: BuildConfiguration) {
        self.configuration = configuration
    }

    public func satisfies(_ environment: BuildEnvironment) -> Bool {
        configuration == environment.configuration
    }
}
