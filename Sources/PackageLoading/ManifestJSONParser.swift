/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import TSCBasic
import TSCUtility
import PackageModel
import Foundation
import SourceControl

enum ManifestJSONParser {
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
        var errors: [String] = []
    }

    static func parse(
        v4 jsonString: String,
        toolsVersion: ToolsVersion,
        packageLocation: String,
        identityResolver: IdentityResolver,
        fileSystem: FileSystem
    ) throws -> ManifestJSONParser.Result {
        let json = try JSON(string: jsonString)
        let package = try json.getJSON("package")
        var result = Self.Result(name: try package.get(String.self, forKey: "name"))
        result.defaultLocalization = try? package.get(String.self, forKey: "defaultLocalization")
        result.pkgConfig = package.get("pkgConfig")
        result.platforms = try Self.parsePlatforms(package)
        result.swiftLanguageVersions = try Self.parseSwiftLanguageVersion(package)
        result.products = try package.getArray("products").map(ProductDescription.init(v4:))
        result.providers = try? package.getArray("providers").map(SystemPackageProviderDescription.init(v4:))
        result.targets = try package.getArray("targets").map(Self.parseTarget(json:))
        result.dependencies = try package.getArray("dependencies").map({
            try PackageDependency(
                v4: $0,
                toolsVersion: toolsVersion,
                packageLocation: packageLocation,
                identityResolver: identityResolver,
                fileSystem: fileSystem
            )
        })

        result.cxxLanguageStandard = package.get("cxxLanguageStandard")
        result.cLanguageStandard = package.get("cLanguageStandard")

        result.errors = try json.get("errors")
        return result
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
            let rawRule = try json.get(String.self, forKey: "rule")
            let rule = TargetDescription.Resource.Rule(rawValue: rawRule)!
            let path = try RelativePath(validating: json.get(String.self, forKey: "path"))
            let localizationString = try? json.get(String.self, forKey: "localization")
            let localization = localizationString.map({ TargetDescription.Resource.Localization(rawValue: $0)! })
            return .init(rule: rule, path: path.pathString, localization: localization)
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
        let name = try TargetBuildSettingDescription.SettingName(rawValue: json.get("name"))!
        let condition = try (try? json.getJSON("condition")).flatMap(PackageConditionDescription.init(v4:))

        let value = try json.get([String].self, forKey: "value")

        // Diagnose invalid values.
        for item in value {
            let groups = Self.invalidValueRegex.matchGroups(in: item).flatMap{ $0 }
            if !groups.isEmpty {
                let error = "the build setting '\(name)' contains invalid component(s): \(groups.joined(separator: " "))"
                throw ManifestParseError.runtimeManifestErrors([error])
            }
        }

        return .init(
            tool: tool, name: name,
            value: value,
            condition: condition
        )
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
            guard let lowerBound = Version(string: lowerBoundString) else {
                throw InternalError("invalid version \(lowerBoundString)")
            }
            let upperBoundString = try json.get(String.self, forKey: "upperBound")
            guard let upperBound = Version(string: upperBoundString) else {
                throw InternalError("invalid version \(upperBoundString)")
            }
            self = .range(lowerBound ..< upperBound)

        case "exact":
            let versionString = try json.get(String.self, forKey: "identifier")
            guard let version = Version(string: versionString) else {
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
            guard let lowerBound = Version(string: lowerBoundString) else {
                throw InternalError("invalid version \(lowerBoundString)")
            }
            let upperBoundString = try json.get(String.self, forKey: "upperBound")
            guard let upperBound = Version(string: upperBoundString) else {
                throw InternalError("invalid version \(upperBoundString)")
            }
            self = .range(lowerBound ..< upperBound)

        case "exact":
            let versionString = try json.get(String.self, forKey: "identifier")
            guard let version = Version(string: versionString) else {
                throw InternalError("invalid version \(versionString)")
            }
            self = .exact(version)

        default:
            throw InternalError("invalid dependency requirement \(type)")
        }
    }
}

extension PackageDependency {
    private static let filePrefix = "file://"

    fileprivate init(
        v4 json: JSON,
        toolsVersion: ToolsVersion,
        packageLocation: String,
        identityResolver: IdentityResolver,
        fileSystem: TSCBasic.FileSystem
    ) throws {
        if let kindJSON = try? json.getJSON("kind") {
            // new format introduced 7/2021
            let type: String = try kindJSON.get("type")
            if type == "fileSystem" {
                let name: String? = kindJSON.get("name")
                let path: String = try kindJSON.get("path")
                self = try Self.makeFileSystemDependency(
                    packageLocation: packageLocation,
                    name: name,
                    at: path,
                    identityResolver: identityResolver,
                    fileSystem: fileSystem)
            } else if type == "sourceControl" {
                let name: String? = kindJSON.get("name")
                let location: String = try kindJSON.get("location")
                let requirementJSON: JSON = try kindJSON.get("requirement")
                let requirement = try SourceControl.Requirement(v4: requirementJSON)
                self = try Self.makeSourceControlDependency(
                    packageLocation: packageLocation,
                    name: name,
                    at: location,
                    requirement: requirement,
                    identityResolver: identityResolver,
                    fileSystem: fileSystem)
            } else if type == "registry" {
                let identity: String = try kindJSON.get("identity")
                let requirementJSON: JSON = try kindJSON.get("requirement")
                let requirement = try Registry.Requirement(v4: requirementJSON)
                self = .registry(identity: .plain(identity), requirement: requirement, productFilter: .everything)
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
                self = try Self.makeFileSystemDependency(
                    packageLocation: packageLocation,
                    name: name,
                    at: url,
                    identityResolver: identityResolver,
                    fileSystem: fileSystem)

            default:
                let requirement = try SourceControl.Requirement(v4: requirementJSON)
                self = try Self.makeSourceControlDependency(
                    packageLocation: packageLocation,
                    name: name,
                    at: url,
                    requirement: requirement,
                    identityResolver: identityResolver,
                    fileSystem: fileSystem)
            }
        }
    }

    private static func makeFileSystemDependency(
        packageLocation: String,
        name: String?,
        at location: String,
        identityResolver: IdentityResolver,
        fileSystem: TSCBasic.FileSystem
    ) throws -> PackageDependency {
        let location = try Self.fixLocation(fileSystem: fileSystem, packageLocation: packageLocation, dependencyLocation: location)
        let path: AbsolutePath
        do {
            path = try AbsolutePath(validating: location)
        } catch PathValidationError.invalidAbsolutePath(let path) {
            throw ManifestParseError.invalidManifestFormat("'\(path)' is not a valid path for path-based dependencies; use relative or absolute path instead.", diagnosticFile: nil)
        }
        let identity = identityResolver.resolveIdentity(for: path)
        return .fileSystem(identity: identity,
                           name: name,
                           path: path,
                           productFilter: .everything)
    }

    private static func makeSourceControlDependency(
        packageLocation: String,
        name: String?,
        at location: String,
        requirement: SourceControl.Requirement,
        identityResolver: IdentityResolver,
        fileSystem: TSCBasic.FileSystem
    ) throws -> PackageDependency {
        var location = try Self.fixLocation(fileSystem: fileSystem, packageLocation: packageLocation, dependencyLocation: location)
        // a remote package that specifies a location and no identity is deemed to be from source control (git)
        // a package in a git location, may be a remote URL or on disk
        // if local, validate location is in fact a git repo
        if let localPath = try? AbsolutePath(validating: location), fileSystem.exists(localPath) {
            let gitRepoProvider = GitRepositoryProvider()
            guard gitRepoProvider.isValidDirectory(location) else {
                throw StringError("Cannot clone from local directory \(localPath)\nPlease git init or use \"path:\" for \(location)")
            }
        }

        // location mapping (aka mirrors)
        location = identityResolver.resolveLocation(from: location)
        // in the future this will check with the registries for the identity of the URL
        let identity = identityResolver.resolveIdentity(for: location)
        return .sourceControl(identity: identity,
                              name: name,
                              location: location,
                              requirement: requirement,
                              productFilter: .everything)
    }

    private static func fixLocation(fileSystem: TSCBasic.FileSystem, packageLocation: String, dependencyLocation: String) throws -> String {
        // If base URL is remote (http/ssh), we can't do any "fixing".
        if URL.scheme(packageLocation) != nil {
            return dependencyLocation
        }

        if dependencyLocation.hasPrefix("~/") {
            // If the dependency URL starts with '~/', try to expand it.
            return fileSystem.homeDirectory.appending(RelativePath(String(dependencyLocation.dropFirst(2)))).pathString
        } else if dependencyLocation.hasPrefix(filePrefix) {
            // FIXME: SwiftPM can't handle file locations with file:// scheme so we need to
            // strip that. We need to design a Location data structure for SwiftPM.
            let location = String(dependencyLocation.dropFirst(filePrefix.count))
            if location.first != "/" {
                throw ManifestParseError.invalidManifestFormat("file:// URLs cannot be relative, did you mean to use `.package(path:)`?", diagnosticFile: nil)
            }
            return AbsolutePath(location).pathString
        } else if URL.scheme(dependencyLocation) == nil {
            // If the dependency URL is not remote, try to "fix" it.
            // If the URL has no scheme, we treat it as a path (either absolute or relative to the base URL).
            return AbsolutePath(dependencyLocation, relativeTo: AbsolutePath(packageLocation)).pathString
        }

        return dependencyLocation
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
            self = .product(name: name, package: json.get("package"), condition: condition)

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
