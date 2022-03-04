/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Foundation
import PackageModel
import TSCBasic

enum ManifestJSONParser {
    private static let filePrefix = "file://"

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
        v4 jsonString: String,
        toolsVersion: ToolsVersion,
        packageKind: PackageReference.Kind,
        identityResolver: IdentityResolver,
        fileSystem: FileSystem
    ) throws -> ManifestJSONParser.Result {
        let json = try JSON(string: jsonString)

        let errors: [String] = try json.get("errors")
        guard errors.isEmpty else {
            throw ManifestParseError.runtimeManifestErrors(errors)
        }

        let package = try json.getJSON("package")
        var manifest = Self.Result(name: try package.get(String.self, forKey: "name"))
        manifest.defaultLocalization = try? package.get(String.self, forKey: "defaultLocalization")
        manifest.pkgConfig = package.get("pkgConfig")
        manifest.platforms = try Self.parsePlatforms(package)
        manifest.swiftLanguageVersions = try Self.parseSwiftLanguageVersion(package)
        manifest.products = try package.getArray("products").map(ProductDescription.init(v4:))
        manifest.providers = try? package.getArray("providers").map(SystemPackageProviderDescription.init(v4:))
        manifest.targets = try package.getArray("targets").map(Self.parseTarget(json:))
        manifest.dependencies = try package.getArray("dependencies").map{
            try Self.parseDependency(
                json: $0,
                toolsVersion: toolsVersion,
                packageKind: packageKind,
                identityResolver: identityResolver,
                fileSystem: fileSystem
            )
        }
        manifest.cxxLanguageStandard = package.get("cxxLanguageStandard")
        manifest.cLanguageStandard = package.get("cLanguageStandard")

        return manifest
    }

    private static func parseSwiftLanguageVersion(_ package: JSON) throws -> [SwiftLanguageVersion]?  {
        guard let versionJSON = try? package.getArray("swiftLanguageVersions") else {
            return nil
        }

        return try versionJSON.map {
            let languageVersionString = try String(json: $0)
            guard let languageVersion = SwiftLanguageVersion(string: languageVersionString) else {
                throw ManifestParseError.runtimeManifestErrors(["invalid Swift language version: \(languageVersionString)"])
            }
            return languageVersion
        }
    }

    private static func parseDependency(
        json: JSON,
        toolsVersion: ToolsVersion,
        packageKind: PackageReference.Kind,
        identityResolver: IdentityResolver,
        fileSystem: TSCBasic.FileSystem
    ) throws -> PackageDependency {
        if let kindJSON = try? json.getJSON("kind") {
            // new format introduced 7/2021
            let type: String = try kindJSON.get("type")
            if type == "fileSystem" {
                let name: String? = kindJSON.get("name")
                let path: String = try kindJSON.get("path")
                return try Self.makeFileSystemDependency(
                    packageKind: packageKind,
                    at: path,
                    name: name,
                    identityResolver: identityResolver,
                    fileSystem: fileSystem)
            } else if type == "sourceControl" {
                let name: String? = kindJSON.get("name")
                let location: String = try kindJSON.get("location")
                let requirementJSON: JSON = try kindJSON.get("requirement")
                let requirement = try PackageDependency.SourceControl.Requirement(v4: requirementJSON)
                return try Self.makeSourceControlDependency(
                    packageKind: packageKind,
                    at: location,
                    name: name,
                    requirement: requirement,
                    identityResolver: identityResolver,
                    fileSystem: fileSystem)
            } else if type == "registry" {
                let identity: String = try kindJSON.get("identity")
                let requirementJSON: JSON = try kindJSON.get("requirement")
                let requirement = try PackageDependency.Registry.Requirement(v4: requirementJSON)
                return .registry(identity: .plain(identity), requirement: requirement, productFilter: .everything)
            } else {
                throw InternalError("Unknown dependency type \(kindJSON)")
            }
        } else {
            // old format, deprecated 7/2021 but may be stored in caches, etc
            let name: String? = json.get("name")
            let url: String = try json.get("url")

            // backwards compatibility 2/2021
            let requirementJSON: JSON = try json.get("requirement")
            let requirementType: String = try requirementJSON.get(String.self, forKey: "type")
            switch requirementType {
            case "localPackage":
                return try Self.makeFileSystemDependency(
                    packageKind: packageKind,
                    at: url,
                    name: name,
                    identityResolver: identityResolver,
                    fileSystem: fileSystem)

            default:
                let requirement = try PackageDependency.SourceControl.Requirement(v4: requirementJSON)
                return try Self.makeSourceControlDependency(
                    packageKind: packageKind,
                    at: url,
                    name: name,
                    requirement: requirement,
                    identityResolver: identityResolver,
                    fileSystem: fileSystem)
            }
        }
    }

    private static func makeFileSystemDependency(
        packageKind: PackageReference.Kind,
        at location: String,
        name: String?,
        identityResolver: IdentityResolver,
        fileSystem: TSCBasic.FileSystem
    ) throws -> PackageDependency {
        let location = try sanitizeDependencyLocation(fileSystem: fileSystem, packageKind: packageKind, dependencyLocation: location)
        let path: AbsolutePath
        do {
            path = try AbsolutePath(validating: location)
        } catch PathValidationError.invalidAbsolutePath(let path) {
            throw ManifestParseError.invalidManifestFormat("'\(path)' is not a valid path for path-based dependencies; use relative or absolute path instead.", diagnosticFile: nil)
        }
        let identity = try identityResolver.resolveIdentity(for: path)
        return .fileSystem(identity: identity,
                           nameForTargetDependencyResolutionOnly: name,
                           path: path,
                           productFilter: .everything)
    }

    private static func makeSourceControlDependency(
        packageKind: PackageReference.Kind,
        at location: String,
        name: String?,
        requirement: PackageDependency.SourceControl.Requirement,
        identityResolver: IdentityResolver,
        fileSystem: TSCBasic.FileSystem
    ) throws -> PackageDependency {
        // cleans up variants of path based location
        var location = try sanitizeDependencyLocation(fileSystem: fileSystem, packageKind: packageKind, dependencyLocation: location)
        // location mapping (aka mirrors) if any
        location = identityResolver.mappedLocation(for: location)
        // a package in a git location, may be a remote URL or on disk
        if let localPath = try? AbsolutePath(validating: location) {
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

    private static func sanitizeDependencyLocation(fileSystem: TSCBasic.FileSystem, packageKind: PackageReference.Kind, dependencyLocation: String) throws -> String {
        if dependencyLocation.hasPrefix("~/") {
            // If the dependency URL starts with '~/', try to expand it.
            return fileSystem.homeDirectory.appending(RelativePath(String(dependencyLocation.dropFirst(2)))).pathString
        } else if dependencyLocation.hasPrefix(filePrefix) {
            // FIXME: SwiftPM can't handle file locations with file:// scheme so we need to
            // strip that. We need to design a Location data structure for SwiftPM.
            let location = String(dependencyLocation.dropFirst(filePrefix.count))
            let hostnameComponent = location.prefix(while: { $0 != "/" })
            guard hostnameComponent.isEmpty else {
              if hostnameComponent == ".." {
                throw ManifestParseError.invalidManifestFormat(
                  "file:// URLs cannot be relative, did you mean to use '.package(path:)'?", diagnosticFile: nil
                )
              }
              throw ManifestParseError.invalidManifestFormat(
                "file:// URLs with hostnames are not supported, are you missing a '/'?", diagnosticFile: nil
              )
            }
            return AbsolutePath(location).pathString
        } else if parseScheme(dependencyLocation) == nil {
            // If the URL has no scheme, we treat it as a path (either absolute or relative to the base URL).
            switch packageKind {
            case .root(let packagePath), .fileSystem(let packagePath), .localSourceControl(let packagePath):
                return AbsolutePath(dependencyLocation, relativeTo: packagePath).pathString
            case .remoteSourceControl, .registry:
                // nothing to "fix"
                return dependencyLocation
            }
        } else {
            // nothing to "fix"
            return dependencyLocation
        }
    }

    private static func parsePlatforms(_ package: JSON) throws -> [PlatformDescription] {
        guard let platformsJSON = try? package.getJSON("platforms") else {
            return []
        }

        // Get the declared platform list.
        let declaredPlatforms = try platformsJSON.getArray()

        // Empty list is not supported.
        if declaredPlatforms.isEmpty {
            throw ManifestParseError.runtimeManifestErrors(["supported platforms can't be empty"])
        }

        // Start parsing platforms.
        var platforms: [PlatformDescription] = []

        for platformJSON in declaredPlatforms {
            // Parse the version and validate that it can be used in the current
            // manifest version.
            let versionString: String = try platformJSON.get("version")

            // Get the platform name.
            let platformName: String = try platformJSON.getJSON("platform").get("name")

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

            let description = PlatformDescription(
                name: platformName,
                version: version.joined(separator: "."),
                options: options.map{ String($0) }
            )

            // Check for duplicates.
            if platforms.map({ $0.platformName }).contains(platformName) {
                // FIXME: We need to emit the API name and not the internal platform name.
                throw ManifestParseError.runtimeManifestErrors(["found multiple declaration for the platform: \(platformName)"])
            }

            platforms.append(description)
        }

        return platforms
    }

    private static func parseTarget(json: JSON) throws -> TargetDescription {
        let providers = try? json
            .getArray("providers")
            .map(SystemPackageProviderDescription.init(v4:))

        let pluginCapability = try? TargetDescription.PluginCapability(v4: json.getJSON("pluginCapability"))

        let dependencies = try json
            .getArray("dependencies")
            .map(TargetDescription.Dependency.init(v4:))

        let sources: [String]? = try? json.get("sources")
        try sources?.forEach{ _ = try RelativePath(validating: $0) }

        let exclude: [String] = try json.get("exclude")
        try exclude.forEach{ _ = try RelativePath(validating: $0) }

        let pluginUsages = try? json
            .getArray("pluginUsages")
            .map(TargetDescription.PluginUsage.init(v4:))

        return try TargetDescription(
            name: try json.get("name"),
            dependencies: dependencies,
            path: json.get("path"),
            url: json.get("url"),
            exclude: exclude,
            sources: sources,
            resources: try Self.parseResources(json),
            publicHeadersPath: json.get("publicHeadersPath"),
            type: try .init(v4: json.get("type")),
            pkgConfig: json.get("pkgConfig"),
            providers: providers,
            pluginCapability: pluginCapability,
            settings: try Self.parseBuildSettings(json),
            checksum: json.get("checksum"),
            pluginUsages: pluginUsages
        )
    }

    private static func parseResources(_ json: JSON) throws -> [TargetDescription.Resource] {
        guard let resourcesJSON = try? json.getArray("resources") else { return [] }
        return try resourcesJSON.map { json in
            let rule = try json.get(String.self, forKey: "rule")
            let path = try RelativePath(validating: json.get(String.self, forKey: "path"))
            switch rule {
            case "process":
                let localizationString = try? json.get(String.self, forKey: "localization")
                let localization = localizationString.map({ TargetDescription.Resource.Localization(rawValue: $0)! })
                return .init(rule: .process(localization: localization), path: path.pathString)
            case "copy":
                return .init(rule: .copy, path: path.pathString)
            default:
                throw InternalError("invalid resource rule \(rule)")
            }
        }
    }

    private static func parseBuildSettings(_ json: JSON) throws -> [TargetBuildSettingDescription.Setting] {
        var settings: [TargetBuildSettingDescription.Setting] = []
        for tool in TargetBuildSettingDescription.Tool.allCases {
            let key = tool.rawValue + "Settings"
            if let settingsJSON = try? json.getJSON(key) {
                settings += try Self.parseBuildSettings(settingsJSON, tool: tool, settingName: key)
            }
        }
        return settings
    }

    private static func parseBuildSettings(_ json: JSON, tool: TargetBuildSettingDescription.Tool, settingName: String) throws -> [TargetBuildSettingDescription.Setting] {
        let declaredSettings = try json.getArray()
        return try declaredSettings.map({
            try Self.parseBuildSetting($0, tool: tool)
        })
    }
    
    private static func parseBuildSetting(_ json: JSON, tool: TargetBuildSettingDescription.Tool) throws -> TargetBuildSettingDescription.Setting {
        let json = try json.getJSON("data")
        let name = try json.get(String.self, forKey: "name")
        let values = try json.get([String].self, forKey: "value")
        let condition = try (try? json.getJSON("condition")).flatMap(PackageConditionDescription.init(v4:))
        
        // Diagnose invalid values.
        for item in values {
            let groups = Self.invalidValueRegex.matchGroups(in: item).flatMap{ $0 }
            if !groups.isEmpty {
                let error = "the build setting '\(name)' contains invalid component(s): \(groups.joined(separator: " "))"
                throw ManifestParseError.runtimeManifestErrors([error])
            }
        }
        
        let kind: TargetBuildSettingDescription.Kind
        switch name {
        case "headerSearchPath":
            guard let value = values.first else {
                throw InternalError("invalid (empty) build settings value")
            }
            kind = .headerSearchPath(value)
        case "define":
            guard let value = values.first else {
                throw InternalError("invalid (empty) build settings value")
            }
            kind = .define(value)
        case "linkedLibrary":
            guard let value = values.first else {
                throw InternalError("invalid (empty) build settings value")
            }
            kind = .linkedLibrary(value)
        case "linkedFramework":
            guard let value = values.first else {
                throw InternalError("invalid (empty) build settings value")
            }
            kind = .linkedFramework(value)
        case "unsafeFlags":
            kind = .unsafeFlags(values)
        default:
            throw InternalError("invalid build setting \(name)")
        }
        
        return .init(
            tool: tool,
            kind: kind,
            condition: condition
        )
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
    private static let invalidValueRegex = try! RegEx(pattern: #"(\$\(.*?\))"#)
}

extension SystemPackageProviderDescription {
    fileprivate init(v4 json: JSON) throws {
        let name = try json.get(String.self, forKey: "name")
        let value = try json.get([String].self, forKey: "values")
        switch name {
        case "brew":
            self = .brew(value)
        case "apt":
            self = .apt(value)
        default:
            throw InternalError("invalid provider \(name)")
        }
    }
}

extension PackageModel.ProductType {
    fileprivate init(v4 json: JSON) throws {
        let productType = try json.get(String.self, forKey: "product_type")

        switch productType {
        case "executable":
            self = .executable

        case "library":
            let libraryType: ProductType.LibraryType

            let libraryTypeString: String? = json.get("type")
            switch libraryTypeString {
            case "static"?:
                libraryType = .static
            case "dynamic"?:
                libraryType = .dynamic
            case nil:
                libraryType = .automatic
            default:
                throw InternalError("invalid product type \(productType)")
            }

            self = .library(libraryType)

        case "plugin":
            self = .plugin

        default:
            throw InternalError("unexpected product type: \(json)")
        }
    }
}

extension ProductDescription {
    fileprivate init(v4 json: JSON) throws {
        try self.init(
            name: json.get("name"),
            type: .init(v4: json),
            targets: json.get("targets")
        )
    }
}

extension PackageDependency.SourceControl.Requirement {
    fileprivate init(v4 json: JSON) throws {
        let type = try json.get(String.self, forKey: "type")
        switch type {
        case "branch":
            self = try .branch(json.get("identifier"))

        case "revision":
            self = try .revision(json.get("identifier"))

        case "range":
            let lowerBoundString = try json.get(String.self, forKey: "lowerBound")
            guard let lowerBound = Version(lowerBoundString) else {
                throw InternalError("invalid version \(lowerBoundString)")
            }
            let upperBoundString = try json.get(String.self, forKey: "upperBound")
            guard let upperBound = Version(upperBoundString) else {
                throw InternalError("invalid version \(upperBoundString)")
            }
            self = .range(lowerBound ..< upperBound)

        case "exact":
            let versionString = try json.get(String.self, forKey: "identifier")
            guard let version = Version(versionString) else {
                throw InternalError("invalid version \(versionString)")
            }
            self = .exact(version)

        default:
            throw InternalError("invalid dependency requirement \(type)")
        }
    }
}

extension PackageDependency.Registry.Requirement {
    fileprivate init(v4 json: JSON) throws {
        let type = try json.get(String.self, forKey: "type")
        switch type {
        case "range":
            let lowerBoundString = try json.get(String.self, forKey: "lowerBound")
            guard let lowerBound = Version(lowerBoundString) else {
                throw InternalError("invalid version \(lowerBoundString)")
            }
            let upperBoundString = try json.get(String.self, forKey: "upperBound")
            guard let upperBound = Version(upperBoundString) else {
                throw InternalError("invalid version \(upperBoundString)")
            }
            self = .range(lowerBound ..< upperBound)

        case "exact":
            let versionString = try json.get(String.self, forKey: "identifier")
            guard let version = Version(versionString) else {
                throw InternalError("invalid version \(versionString)")
            }
            self = .exact(version)

        default:
            throw InternalError("invalid dependency requirement \(type)")
        }
    }
}

extension TargetDescription.TargetType {
    fileprivate init(v4 string: String) throws {
        switch string {
        case "regular":
            self = .regular
        case "executable":
            self = .executable
        case "test":
            self = .test
        case "system":
            self = .system
        case "binary":
            self = .binary
        case "plugin":
            self = .plugin
        default:
            throw InternalError("invalid target \(string)")
        }
    }
}

extension TargetDescription.Dependency {
    fileprivate init(v4 json: JSON) throws {
        let type = try json.get(String.self, forKey: "type")
        let condition = try (try? json.getJSON("condition")).flatMap(PackageConditionDescription.init(v4:))

        switch type {
        case "target":
            self = try .target(name: json.get("name"), condition: condition)

        case "product":
            let name = try json.get(String.self, forKey: "name")
            let moduleAliases: [String: String]? = try? json.get("moduleAliases")
            self = .product(name: name, package: json.get("package"), moduleAliases: moduleAliases, condition: condition)

        case "byname":
            self = try .byName(name: json.get("name"), condition: condition)

        default:
            throw InternalError("invalid type \(type)")
        }
    }
}

extension TargetDescription.PluginCapability {
    fileprivate init(v4 json: JSON) throws {
        let type = try json.get(String.self, forKey: "type")
        switch type {
        case "buildTool":
            self = .buildTool
        case "command":
            let intent = try TargetDescription.PluginCommandIntent(v4: json.getJSON("intent"))
            let permissions = try json.getArray("permissions").map(TargetDescription.PluginPermission.init(v4:))
            self = .command(intent: intent, permissions: permissions)
        default:
            throw InternalError("invalid type \(type)")
        }
    }
}

extension TargetDescription.PluginCommandIntent {
    fileprivate init(v4 json: JSON) throws {
        let type = try json.get(String.self, forKey: "type")
        switch type {
        case "documentationGeneration":
            self = .documentationGeneration
        case "sourceCodeFormatting":
            self = .sourceCodeFormatting
        case "custom":
            let verb = try json.get(String.self, forKey: "verb")
            let description = try json.get(String.self, forKey: "description")
            self = .custom(verb: verb, description: description)
        default:
            throw InternalError("invalid type \(type)")
        }
    }
}

extension TargetDescription.PluginPermission {
    fileprivate init(v4 json: JSON) throws {
        let type = try json.get(String.self, forKey: "type")
        switch type {
        case "writeToPackageDirectory":
            let reason = try json.get(String.self, forKey: "reason")
            self = .writeToPackageDirectory(reason: reason)
        default:
            throw InternalError("invalid type \(type)")
        }
    }
}

extension TargetDescription.PluginUsage {
    fileprivate init(v4 json: JSON) throws {
        let type = try json.get(String.self, forKey: "type")
        switch type {
        case "plugin":
            let name = try json.get(String.self, forKey: "name")
            let package = try? json.get(String.self, forKey: "package")
            self = .plugin(name: name, package: package)
        default:
            throw InternalError("invalid type \(type)")
        }
    }
}

extension PackageConditionDescription {
    fileprivate init?(v4 json: JSON) throws {
        if case .null = json { return nil }
        let platformNames: [String]? = try? json.getArray("platforms").map { try $0.get("name") }
        self.init(
            platformNames: platformNames ?? [],
            config: try? json.get("config").get("config")
        )
    }
}
