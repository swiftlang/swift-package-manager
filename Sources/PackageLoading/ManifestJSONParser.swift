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

@_implementationOnly import Foundation
import PackageManifestModel
import PackageModel

import struct Basics.AbsolutePath
import protocol Basics.FileSystem
import struct Basics.InternalError
import struct Basics.RelativePath

import enum TSCBasic.PathValidationError
import struct TSCBasic.RegEx
import struct TSCBasic.StringError

import struct TSCUtility.Version

enum ManifestJSONParser {
    struct VersionedInput: Codable {
        let version: Int
    }
    
    struct Result {
        var name: String
        var defaultLocalization: String?
        var platforms: [PlatformDescription] = []
        var targets: [TargetDescription] = []
        var pkgConfig: String?
        var swiftLanguageVersions: [SwiftLanguageVersion]?
        var dependencies: [PackageDependency] = []
        var providers: [SystemPackageProviderDescription]?
        var products: [ProductDescription] = []
        var cxxLanguageStandard: String?
        var cLanguageStandard: String?
    }
    
    static func parse(
        _ jsonString: String,
        toolsVersion: ToolsVersion,
        packageKind: PackageReference.Kind,
        identityResolver: IdentityResolver,
        fileSystem: FileSystem
    ) throws -> ManifestJSONParser.Result {
        let decoder = JSONDecoder.makeWithDefaults()
        
        // Validate the version first to detect use of a mismatched PD library.
        let versionedInput: VersionedInput
        do {
            versionedInput = try decoder.decode(VersionedInput.self, from: jsonString)
        } catch {
            // If we cannot even decode the version, assume that a pre-5.9 PD library is being used which emits an incompatible JSON format.
            throw ManifestParseError.unsupportedVersion(version: 1, underlyingError: "\(error.interpolationDescription)")
        }
        
        switch versionedInput.version {
        case 2:
            return try self.parse(v2: jsonString, toolsVersion: toolsVersion, packageKind: packageKind, identityResolver: identityResolver, fileSystem: fileSystem)
        case 3:
            return try self.parse(v3: jsonString, toolsVersion: toolsVersion, packageKind: packageKind, identityResolver: identityResolver, fileSystem: fileSystem)
        default:
            throw ManifestParseError.unsupportedVersion(version: versionedInput.version)
        }
    }
}

// MARK: - Manifest 2.0

extension ManifestJSONParser {
    struct V3Input: Codable {
        let package: PackageManifestModel.Package
    }

    static func parse(
        v3 jsonString: String,
        toolsVersion: ToolsVersion,
        packageKind: PackageReference.Kind,
        identityResolver: IdentityResolver,
        fileSystem: FileSystem
    ) throws -> ManifestJSONParser.Result {
        let decoder = JSONDecoder.makeWithDefaults()
        let input = try decoder.decode(V3Input.self, from: jsonString)

        var products: [ProductDescription] = []
        var targets: [TargetDescription] = []

        try input.package.modules.forEach { module in
            let type: TargetDescription.TargetType

            var url: String? = .none
            var sources: [String]? = .none
            var resources: [String]? = .none
            var exclude: [String]? = .none
            var dependencies: [TargetDescription.Dependency] = []
            var pluginCapability: TargetDescription.PluginCapability? = .none

            switch module.kind {
            case .binary(let settings):
                type = .binary

                switch settings.location {
                case .fileSystem(let path): break
                case .remote(let _url): url = _url
                }

                // TODO: Handle `checksum`
            case .executable(let settings):
                type = .executable

                sources = settings.sources
                resources = settings.resources
                exclude = settings.exclude
                dependencies = settings.dependencies.map { .init($0) }

                /* TODO:
                 public var languageSettings: LanguageSettings?
                 public var linkerSettings: [String]?
                 public var isPublic: Bool = false
                 */
            case .library(let settings):
                type = .regular
                /* TODO:
                 public var sources: [String]?
                 public var resources: [String]?
                 public var exclude: [String]?
                 public var languageSettings: LanguageSettings?
                 public var linkerSettings: [String]?
                 public var isPublic: Bool = false
                 public var linkage: Linkage = .auto // TBD if needed, or we want to change the model
                 public var dependencies: [ModuleDependency] = [] // non-optional to make programmatic API nicer
                 */
            case .plugin(let settings):
                type = .plugin
                pluginCapability = .buildTool

                /* TODO:
                 public var capability: Capability
                 public var isPublic: Bool = false
                 */
            case .system(let settings):
                type = .system
                /* TODO:
                 var providers: [Provider]
                 */
            case .test(let settings):
                type = .test
                /* TODO:
                 public var sources: [String]?
                 public var resources: [String]?
                 public var exclude: [String]?
                 public var languageSettings: LanguageSettings?
                 public var linkerSettings: [String]?
                 public var modules: [String] = []
                 */
            }

            let target = try TargetDescription(
                name: module.name,
                dependencies: dependencies,
                path: module.customPath,
                url: url,
                exclude: exclude,
                sources: sources,
                resources: .none, // FIXME
                publicHeadersPath: .none, // FIXME
                type: type,
                pkgConfig: .none,
                providers: .none,
                pluginCapability: pluginCapability,
                settings: [], // FIXME
                checksum: .none,
                pluginUsages: .none // FIXME
            )
            targets.append(target)
        }

        return Result(
            name: "", // FIXME: name
            defaultLocalization: nil,
            platforms: try input.package.minimumDeploymentTargets.map { try .init($0) },
            targets: targets,
            pkgConfig: nil,
            swiftLanguageVersions: nil,
            dependencies: try input.package.dependencies.map { try .init($0, packageKind: packageKind, identityResolver: identityResolver, fileSystem: fileSystem) },
            providers: nil,
            products: products,
            cxxLanguageStandard: nil,
            cLanguageStandard: nil
        )
    }
}

extension Version {
    init(_ version: PackageManifestModel.Dependency.Version) {
        self.init(version.major, version.minor, version.patch)
    }
}

extension PackageDependency.Registry.Requirement {
    init(_ requirement: PackageManifestModel.Dependency.RegistrySettings.Requirement) {
        switch requirement {
        case .exact(let version): self = .exact(.init(version))
        case .range(let range):
            let upper = TSCUtility.Version(range.upperBound)
            let lower = TSCUtility.Version(range.lowerBound)
            self = .range(lower..<upper)
        }
    }
}

extension PackageDependency.SourceControl.Requirement {
    init(_ requirement: PackageManifestModel.Dependency.SourceControlSettings.Requirement) {
        switch requirement {
        case .exact(let version): self = .exact(.init(version))
        case .range(let range):
            let upper = TSCUtility.Version(range.upperBound)
            let lower = TSCUtility.Version(range.lowerBound)
            self = .range(lower..<upper)
        case .branch(let branch): self = .branch(branch)
        case .revision(let revision): self = .revision(revision)
        }
    }
}

extension PackageDependency {
    init(_ dependency: PackageManifestModel.Dependency, packageKind: PackageReference.Kind, identityResolver: IdentityResolver, fileSystem: Basics.FileSystem) throws {
        switch dependency.kind {
        case .fileSystem(let settings):
            let path = try AbsolutePath(validating: settings.path)
            self = .fileSystem(identity: .init(path: path), nameForTargetDependencyResolutionOnly: nil, path: path, productFilter: .everything)
        case .registry(let settings):
            self = .registry(identity: .plain(settings.identity), requirement: .init(settings.requirement), productFilter: .everything)
        case .sourceControl(let settings):
            self = try ManifestJSONParser.parseSourceControlDependency(packageKind: packageKind, at: settings.location, name: nil, requirement: .init(settings.requirement), identityResolver: identityResolver, fileSystem: fileSystem)
        }
    }
}

extension TargetDescription.Dependency {
    init(_ dependency: PackageManifestModel.ModuleDependency) {
        switch dependency.kind {
        case .external(let settings): self = .product(name: settings.name, package: settings.packageIdentity)
        case .internal(let settings): self = .target(name: settings.name)
        }
    }
}

extension PackageModel.Platform {
    init(_ platform: PackageManifestModel.Platform) throws {
        switch platform {
        case .android: self = .android
        case .driverKit: self = .driverKit
        case .iOS: self = .iOS
        case .linux: self = .linux
        case .macCatalyst: self = .macCatalyst
        case .macOS: self = .macOS
        case .openbsd: self = .openbsd
        case .tvOS: self = .tvOS
        case .wasi: self = .wasi
        case .watchOS: self = .watchOS
        case .windows: self = .windows
        default: throw InternalError("unhandled platform '\(platform.name)'")
        }
    }
}

extension PlatformDescription {
    init(_ deploymentTarget: PackageManifestModel.DeploymentTarget) throws {
        let platform = try PackageModel.Platform(deploymentTarget.platform)
        self.init(
            name: platform.name,
            version: deploymentTarget.version ?? platform.oldestSupportedVersion.versionString,
            options: []
        )
    }
}

// MARK: - Legacy manifest

extension ManifestJSONParser {
    private static let filePrefix = "file://"

    struct V2Input: Codable {
        let package: Serialization.Package
        let errors: [String]
    }

    static func parse(
        v2 jsonString: String,
        toolsVersion: ToolsVersion,
        packageKind: PackageReference.Kind,
        identityResolver: IdentityResolver,
        fileSystem: FileSystem
    ) throws -> ManifestJSONParser.Result {
        let decoder = JSONDecoder.makeWithDefaults()
        let input = try decoder.decode(V2Input.self, from: jsonString)

        guard input.errors.isEmpty else {
            throw ManifestParseError.runtimeManifestErrors(input.errors)
        }

        let dependencies = try input.package.dependencies.map {
            try Self.parseDependency(
                dependency: $0,
                toolsVersion: toolsVersion,
                packageKind: packageKind,
                identityResolver: identityResolver,
                fileSystem: fileSystem
            )
        }

        return Result(
            name: input.package.name,
            defaultLocalization: input.package.defaultLocalization?.tag,
            platforms: try input.package.platforms.map { try Self.parsePlatforms($0) } ?? [],
            targets: try input.package.targets.map { try Self.parseTarget(target: $0, identityResolver: identityResolver) },
            pkgConfig: input.package.pkgConfig,
            swiftLanguageVersions: try input.package.swiftLanguageVersions.map { try Self.parseSwiftLanguageVersions($0) },
            dependencies: dependencies,
            providers: input.package.providers?.map { .init($0) },
            products: try input.package.products.map { try .init($0) },
            cxxLanguageStandard: input.package.cxxLanguageStandard?.rawValue,
            cLanguageStandard: input.package.cLanguageStandard?.rawValue
        )
    }

    private static func parsePlatforms(_ declaredPlatforms: [Serialization.SupportedPlatform]) throws -> [PlatformDescription] {
        // Empty list is not supported.
        if declaredPlatforms.isEmpty {
            throw ManifestParseError.runtimeManifestErrors(["supported platforms can't be empty"])
        }

        var platforms: [PlatformDescription] = []

        for platform in declaredPlatforms {
            let description = PlatformDescription(platform)

            // Check for duplicates.
            if platforms.map({ $0.platformName }).contains(description.platformName) {
                // FIXME: We need to emit the API name and not the internal platform name.
                throw ManifestParseError.runtimeManifestErrors(["found multiple declaration for the platform: \(description.platformName)"])
            }

            platforms.append(description)
        }

        return platforms
    }

    private static func parseSwiftLanguageVersions(_ versions: [Serialization.SwiftVersion]) throws -> [SwiftLanguageVersion] {
        return try versions.map {
            let languageVersionString: String
            switch $0 {
            case .v3: languageVersionString = "3"
            case .v4: languageVersionString = "4"
            case .v4_2: languageVersionString = "4.2"
            case .v5: languageVersionString = "5"
            case .version(let version): languageVersionString = version
            }
            guard let languageVersion = SwiftLanguageVersion(string: languageVersionString) else {
                throw ManifestParseError.runtimeManifestErrors(["invalid Swift language version: \(languageVersionString)"])
            }
            return languageVersion
        }
    }

    private static func parseDependency(
        dependency: Serialization.PackageDependency,
        toolsVersion: ToolsVersion,
        packageKind: PackageReference.Kind,
        identityResolver: IdentityResolver,
        fileSystem: FileSystem
    ) throws -> PackageDependency {
        switch dependency.kind {
        case .registry(let identity, let requirement):
            return try Self.parseRegistryDependency(
                identity: .plain(identity),
                requirement: .init(requirement),
                identityResolver: identityResolver
            )
        case .sourceControl(let name, let location, let requirement):
            return try Self.parseSourceControlDependency(
                packageKind: packageKind,
                at: location,
                name: name,
                requirement: .init(requirement),
                identityResolver: identityResolver,
                fileSystem: fileSystem
            )
        case .fileSystem(let name, let path):
            return try Self.parseFileSystemDependency(
                packageKind: packageKind,
                at: path,
                name: name,
                identityResolver: identityResolver,
                fileSystem: fileSystem
            )
        }
    }

    private static func parseFileSystemDependency(
        packageKind: PackageReference.Kind,
        at location: String,
        name: String?,
        identityResolver: IdentityResolver,
        fileSystem: FileSystem
    ) throws -> PackageDependency {
        let location = try sanitizeDependencyLocation(fileSystem: fileSystem, packageKind: packageKind, dependencyLocation: location)
        let path: AbsolutePath
        do {
            path = try AbsolutePath(validating: location)
        } catch PathValidationError.invalidAbsolutePath(let path) {
            throw ManifestParseError.invalidManifestFormat("'\(path)' is not a valid path for path-based dependencies; use relative or absolute path instead.", diagnosticFile: nil, compilerCommandLine: nil)
        }
        let identity = try identityResolver.resolveIdentity(for: path)
        return .fileSystem(identity: identity,
                           nameForTargetDependencyResolutionOnly: name,
                           path: path,
                           productFilter: .everything)
    }

    static func parseSourceControlDependency(
        packageKind: PackageReference.Kind,
        at location: String,
        name: String?,
        requirement: PackageDependency.SourceControl.Requirement,
        identityResolver: IdentityResolver,
        fileSystem: FileSystem
    ) throws -> PackageDependency {
        // cleans up variants of path based location
        var location = try sanitizeDependencyLocation(fileSystem: fileSystem, packageKind: packageKind, dependencyLocation: location)
        // location mapping (aka mirrors) if any
        location = identityResolver.mappedLocation(for: location)
        if PackageIdentity.plain(location).isRegistry {
            // re-mapped to registry
            let identity = PackageIdentity.plain(location)
            let registryRequirement: PackageDependency.Registry.Requirement
            switch requirement {
            case .branch, .revision:
                throw StringError("invalid mapping of source control to registry, requirement information mismatch: cannot map branch or revision based dependencies to registry.")
            case .exact(let value):
                registryRequirement = .exact(value)
            case .range(let value):
                registryRequirement = .range(value)
            }
            return .registry(
                identity: identity,
                requirement: registryRequirement,
                productFilter: .everything
            )
        } else if let localPath = try? AbsolutePath(validating: location) {
            // a package in a git location, may be a remote URL or on disk
            // in the future this will check with the registries for the identity of the URL
            let identity = try identityResolver.resolveIdentity(for: localPath)
            return .localSourceControl(
                identity: identity,
                nameForTargetDependencyResolutionOnly: name,
                path: localPath,
                requirement: requirement,
                productFilter: .everything
            )
        } else if let url = URL(string: location){
            // in the future this will check with the registries for the identity of the URL
            let identity = try identityResolver.resolveIdentity(for: url)
            return .remoteSourceControl(
                identity: identity,
                nameForTargetDependencyResolutionOnly: name,
                url: url,
                requirement: requirement,
                productFilter: .everything
            )
        } else {
            throw StringError("invalid location: \(location)")
        }
    }

    private static func parseRegistryDependency(
        identity: PackageIdentity,
        requirement: PackageDependency.Registry.Requirement,
        identityResolver: IdentityResolver
    ) throws -> PackageDependency {
        // location mapping (aka mirrors) if any
        let location = identityResolver.mappedLocation(for: identity.description)
        if PackageIdentity.plain(location).isRegistry {
            // re-mapped to registry
            let identity = PackageIdentity.plain(location)
            return .registry(
                identity: identity,
                requirement: requirement,
                productFilter: .everything
            )
        } else if let url = URL(string: location){
            // in the future this will check with the registries for the identity of the URL
            let identity = try identityResolver.resolveIdentity(for: url)
            let sourceControlRequirement: PackageDependency.SourceControl.Requirement
            switch requirement {
            case .exact(let value):
                sourceControlRequirement = .exact(value)
            case .range(let value):
                sourceControlRequirement = .range(value)
            }
            return .remoteSourceControl(
                identity: identity,
                nameForTargetDependencyResolutionOnly: identity.description,
                url: url,
                requirement: sourceControlRequirement,
                productFilter: .everything
            )
        } else {
            throw StringError("invalid location: \(location)")
        }
    }

    private static func sanitizeDependencyLocation(fileSystem: FileSystem, packageKind: PackageReference.Kind, dependencyLocation: String) throws -> String {
        if dependencyLocation.hasPrefix("~/") {
            // If the dependency URL starts with '~/', try to expand it.
            return try AbsolutePath(validating: String(dependencyLocation.dropFirst(2)), relativeTo: fileSystem.homeDirectory).pathString
        } else if dependencyLocation.hasPrefix(filePrefix) {
            // FIXME: SwiftPM can't handle file locations with file:// scheme so we need to
            // strip that. We need to design a Location data structure for SwiftPM.
            let location = String(dependencyLocation.dropFirst(filePrefix.count))
            let hostnameComponent = location.prefix(while: { $0 != "/" })
            guard hostnameComponent.isEmpty else {
              if hostnameComponent == ".." {
                throw ManifestParseError.invalidManifestFormat(
                  "file:// URLs cannot be relative, did you mean to use '.package(path:)'?", diagnosticFile: nil, compilerCommandLine: nil
                )
              }
              throw ManifestParseError.invalidManifestFormat(
                "file:// URLs with hostnames are not supported, are you missing a '/'?", diagnosticFile: nil, compilerCommandLine: nil
              )
            }
            return try AbsolutePath(validating: location).pathString
        } else if parseScheme(dependencyLocation) == nil {
            // If the URL has no scheme, we treat it as a path (either absolute or relative to the base URL).
            switch packageKind {
            case .root(let packagePath), .fileSystem(let packagePath), .localSourceControl(let packagePath):
                return try AbsolutePath(validating: dependencyLocation, relativeTo: packagePath).pathString
            case .remoteSourceControl, .registry:
                // nothing to "fix"
                return dependencyLocation
            }
        } else {
            // nothing to "fix"
            return dependencyLocation
        }
    }

    private static func parseTarget(
        target: Serialization.Target,
        identityResolver: IdentityResolver
    ) throws -> TargetDescription {
        let providers = target.providers?.map { SystemPackageProviderDescription($0) }
        let pluginCapability = target.pluginCapability.map { TargetDescription.PluginCapability($0) }
        let dependencies = try target.dependencies.map { try TargetDescription.Dependency($0, identityResolver: identityResolver) }

        try target.sources?.forEach{ _ = try RelativePath(validating: $0) }
        try target.exclude.forEach{ _ = try RelativePath(validating: $0) }

        let pluginUsages = target.pluginUsages?.map { TargetDescription.PluginUsage.init($0) }

        return try TargetDescription(
            name: target.name,
            dependencies: dependencies,
            path: target.path,
            url: target.url,
            exclude: target.exclude,
            sources: target.sources,
            resources: try Self.parseResources(target.resources),
            publicHeadersPath: target.publicHeadersPath,
            type: .init(target.type),
            packageAccess: target.packageAccess,
            pkgConfig: target.pkgConfig,
            providers: providers,
            pluginCapability: pluginCapability,
            settings: try Self.parseBuildSettings(target),
            checksum: target.checksum,
            pluginUsages: pluginUsages
        )
    }

    private static func parseResources(_ resources: [Serialization.Resource]?) throws -> [TargetDescription.Resource] {
        return try resources?.map {
            let path = try RelativePath(validating: $0.path)
            switch $0.rule {
            case "process":
                let localization = $0.localization.map({ TargetDescription.Resource.Localization(rawValue: $0.rawValue)! })
                return .init(rule: .process(localization: localization), path: path.pathString)
            case "copy":
                return .init(rule: .copy, path: path.pathString)
            case "embedInCode":
                return .init(rule: .embedInCode, path: path.pathString)
            default:
                throw InternalError("invalid resource rule \($0.rule)")
            }
        } ?? []
    }

    private static func parseBuildSettings(_ target: Serialization.Target) throws -> [TargetBuildSettingDescription.Setting] {
        var settings: [TargetBuildSettingDescription.Setting] = []
        try target.cSettings?.forEach {
            settings.append(try .init($0))
        }
        try target.cxxSettings?.forEach {
            settings.append(try .init($0))
        }
        try target.swiftSettings?.forEach {
            settings.append(try .init($0))
        }
        try target.linkerSettings?.forEach {
            settings.append(try .init($0))
        }
        return settings
    }

    /// Parses the URL type of a git repository
    /// e.g. https://github.com/apple/swift returns "https"
    /// e.g. git@github.com:apple/swift returns "git"
    ///
    /// This is *not* a generic URI scheme parser!
    private static func parseScheme(_ location: String) -> String? {
        func prefixOfSplitBy(_ delimiter: String) -> String? {
            let (head, tail) = location.spm_split(around: delimiter)
            if tail == nil {
                //not found
                return nil
            } else {
                //found, return head
                //lowercase the "scheme", as specified by the URI RFC (just in case)
                return head.lowercased()
            }
        }

        for delim in ["://", "@"] {
            if let found = prefixOfSplitBy(delim), !found.contains("/") {
                return found
            }
        }

        return nil
    }

    /// Looks for Xcode-style build setting macros "$()".
    fileprivate static let invalidValueRegex = try! RegEx(pattern: #"(\$\(.*?\))"#)
}

extension SystemPackageProviderDescription {
    init(_ provider: Serialization.SystemPackageProvider) {
        switch provider {
        case .brew(let values):
            self = .brew(values)
        case .apt(let values):
            self = .apt(values)
        case .yum(let values):
            self = .yum(values)
        case .nuget(let values):
            self = .nuget(values)
        }
    }
}

extension PackageDependency.SourceControl.Requirement {
    init(_ requirement: Serialization.PackageDependency.SourceControlRequirement) {
        switch requirement {
        case .exact(let version):
            self = .exact(.init(version))
        case .range(let lowerBound, let upperBound):
            let lower: TSCUtility.Version = .init(lowerBound)
            let upper: TSCUtility.Version = .init(upperBound)
            self = .range(lower..<upper)
        case .revision(let revision):
            self = .revision(revision)
        case .branch(let branch):
            self = .branch(branch)
        }
    }
}

extension PackageDependency.Registry.Requirement {
    init(_ requirement: Serialization.PackageDependency.RegistryRequirement) {
        switch requirement {
        case .exact(let version):
            self = .exact(.init(version))
        case .range(let lowerBound, let upperBound):
            let lower: TSCUtility.Version = .init(lowerBound)
            let upper: TSCUtility.Version = .init(upperBound)
            self = .range(lower..<upper)
        }
    }
}

extension ProductDescription {
    init(_ product: Serialization.Product) throws {
        let productType: ProductType
        switch product.productType {
        case .executable:
            productType = .executable
        case .plugin:
            productType = .plugin
        case .library(let type):
            productType = .library(.init(type))
        }
        try self.init(name: product.name, type: productType, targets: product.targets)
    }
}

extension ProductType.LibraryType {
    init(_ libraryType: Serialization.Product.ProductType.LibraryType) {
        switch libraryType {
        case .dynamic:
            self = .dynamic
        case .static:
            self = .static
        case .automatic:
            self = .automatic
        }
    }
}

extension TargetDescription.Dependency {
    init(_ dependency: Serialization.TargetDependency, identityResolver: IdentityResolver) throws {
        switch dependency {
        case .target(let name, let condition):
            self = .target(name: name, condition: condition.map { .init($0) })
        case .product(let name, let package, let moduleAliases, let condition):
            var package: String? = package
            if let packageName = package {
                package = try identityResolver.mappedIdentity(for: .plain(packageName)).description
            }
            self = .product(name: name, package: package, moduleAliases: moduleAliases, condition: condition.map { .init($0) })
        case .byName(let name, let condition):
            self = .byName(name: name, condition: condition.map { .init($0) })
        }
    }
}

extension PackageConditionDescription {
    init(_ condition: Serialization.TargetDependency.Condition) {
        self.init(platformNames: condition.platforms?.map { $0.name } ?? [])
    }
}

extension TargetDescription.TargetType {
    init(_ type: Serialization.TargetType) {
        switch type {
        case .regular:
            self = .regular
        case .executable:
            self = .executable
        case .test:
            self = .test
        case .system:
            self = .system
        case .binary:
            self = .binary
        case .plugin:
            self = .plugin
        case .macro:
            self = .macro
        }
    }
}

extension TargetDescription.PluginCapability {
    init(_ capability: Serialization.PluginCapability) {
        switch capability {
        case .buildTool:
            self = .buildTool
        case .command(let intent, let permissions):
            self = .command(intent: .init(intent), permissions: permissions.map { .init($0) })
        }
    }
}

extension TargetDescription.PluginCommandIntent {
    init(_ intent: Serialization.PluginCommandIntent) {
        switch intent {
        case .documentationGeneration:
            self = .documentationGeneration
        case .sourceCodeFormatting:
            self = .sourceCodeFormatting
        case .custom(let verb, let description):
            self = .custom(verb: verb, description: description)
        }
    }
}

extension TargetDescription.PluginPermission {
    init(_ permission: Serialization.PluginPermission) {
        switch permission {
        case .allowNetworkConnections(let scope, let reason):
            self = .allowNetworkConnections(scope: .init(scope), reason: reason)
        case .writeToPackageDirectory(let reason):
            self = .writeToPackageDirectory(reason: reason)
        }
    }
}

extension TargetDescription.PluginNetworkPermissionScope {
    init(_ scope: Serialization.PluginNetworkPermissionScope) {
        switch scope {
        case .none:
            self = .none
        case .local(let ports):
            self = .local(ports: ports)
        case .all(ports: let ports):
            self = .all(ports: ports)
        case .docker:
            self = .docker
        case .unixDomainSocket:
            self = .unixDomainSocket
        }
    }
}

extension TargetDescription.PluginUsage {
    init(_ usage: Serialization.PluginUsage) {
        switch usage {
        case .plugin(let name, let package):
            self = .plugin(name: name, package: package)
        }
    }
}

extension TSCUtility.Version {
    init(_ version: Serialization.Version) {
        self.init(
            version.major,
            version.minor,
            version.patch,
            prereleaseIdentifiers: version.prereleaseIdentifiers,
            buildMetadataIdentifiers: version.buildMetadataIdentifiers
        )
    }
}

extension PlatformDescription {
    init(_ platform: Serialization.SupportedPlatform) {
        let platformName = platform.platform.name
        let versionString = platform.version ?? ""

        let versionComponents = versionString.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        var version: [String.SubSequence] = []
        var options: [String.SubSequence] = []

        for (idx, component) in versionComponents.enumerated() {
            if idx < 2 {
                version.append(component)
                continue
            }

            if idx == 2, UInt(component) != nil {
                version.append(component)
                continue
            }

            options.append(component)
        }

        self.init(
            name: platformName,
            version: version.joined(separator: "."),
            options: options.map{ String($0) }
        )
    }
}

extension TargetBuildSettingDescription.Kind {
    static func from(_ name: String, values: [String]) throws -> Self {
        // Diagnose invalid values.
        for item in values {
            let groups = ManifestJSONParser.invalidValueRegex.matchGroups(in: item).flatMap{ $0 }
            if !groups.isEmpty {
                let error = "the build setting '\(name)' contains invalid component(s): \(groups.joined(separator: " "))"
                throw ManifestParseError.runtimeManifestErrors([error])
            }
        }

        switch name {
        case "headerSearchPath":
            guard let value = values.first else {
                throw InternalError("invalid (empty) build settings value")
            }
            return .headerSearchPath(value)
        case "define":
            guard let value = values.first else {
                throw InternalError("invalid (empty) build settings value")
            }
            return .define(value)
        case "linkedLibrary":
            guard let value = values.first else {
                throw InternalError("invalid (empty) build settings value")
            }
            return .linkedLibrary(value)
        case "linkedFramework":
            guard let value = values.first else {
                throw InternalError("invalid (empty) build settings value")
            }
            return .linkedFramework(value)
        case "interoperabilityMode":
            guard let rawLang = values.first else {
                throw InternalError("invalid (empty) build settings value")
            }
            guard let lang = TargetBuildSettingDescription.InteroperabilityMode(rawValue: rawLang) else {
                throw InternalError("unknown interoperability mode: \(rawLang)")
            }
            if values.count > 1 {
                throw InternalError("invalid build settings value")
            }
            return .interoperabilityMode(lang)
        case "enableUpcomingFeature":
            guard let value = values.first else {
                throw InternalError("invalid (empty) build settings value")
            }
            return .enableUpcomingFeature(value)
        case "enableExperimentalFeature":
            guard let value = values.first else {
                throw InternalError("invalid (empty) build settings value")
            }
            return .enableExperimentalFeature(value)
        case "unsafeFlags":
            return .unsafeFlags(values)
        default:
            throw InternalError("invalid build setting \(name)")
        }
    }
}

extension PackageConditionDescription {
    init(_ condition: Serialization.BuildSettingCondition) {
        self.init(platformNames: condition.platforms?.map { $0.name } ?? [], config: condition.config?.config)
    }
}

extension TargetBuildSettingDescription.Setting {
    init(_ setting: Serialization.CSetting) throws {
        self.init(
            tool: .c,
            kind: try .from(setting.data.name, values: setting.data.value),
            condition: setting.data.condition.map { .init($0) }
        )
    }

    init(_ setting: Serialization.CXXSetting) throws {
        self.init(
            tool: .cxx,
            kind: try .from(setting.data.name, values: setting.data.value),
            condition: setting.data.condition.map { .init($0) }
        )
    }

    init(_ setting: Serialization.LinkerSetting) throws {
        self.init(
            tool: .linker,
            kind: try .from(setting.data.name, values: setting.data.value),
            condition: setting.data.condition.map { .init($0) }
        )
    }

    init(_ setting: Serialization.SwiftSetting) throws {
        self.init(
            tool: .swift,
            kind: try .from(setting.data.name, values: setting.data.value),
            condition: setting.data.condition.map { .init($0) }
        )
    }
}
