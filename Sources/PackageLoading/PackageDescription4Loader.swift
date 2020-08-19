/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import TSCUtility
import PackageModel
import Foundation

extension ManifestBuilder {
    mutating func build(v4 json: JSON, toolsVersion: ToolsVersion) throws {
        let package = try json.getJSON("package")
        self.name = try package.get(String.self, forKey: "name")
        self.defaultLocalization = try? package.get(String.self, forKey: "defaultLocalization")
        self.pkgConfig = package.get("pkgConfig")
        self.platforms = try parsePlatforms(package)
        self.swiftLanguageVersions = try parseSwiftLanguageVersion(package)
        self.products = try package.getArray("products").map(ProductDescription.init(v4:))
        self.providers = try? package.getArray("providers").map(SystemPackageProviderDescription.init(v4:))
        self.targets = try package.getArray("targets").map(parseTarget(json:))
        self.dependencies = try package.getArray("dependencies").map({
            try PackageDependencyDescription(
                v4: $0,
                toolsVersion: toolsVersion,
                baseURL: self.baseURL,
                fileSystem: self.fs
            )
        })

        self.cxxLanguageStandard = package.get("cxxLanguageStandard")
        self.cLanguageStandard = package.get("cLanguageStandard")

        self.errors = try json.get("errors")
    }

    func parseSwiftLanguageVersion(_ package: JSON) throws -> [SwiftLanguageVersion]?  {
        guard let versionJSON = try? package.getArray("swiftLanguageVersions") else {
            return nil
        }

        return try versionJSON.map {
            try SwiftLanguageVersion(string: String(json: $0))!
        }
    }

    func parsePlatforms(_ package: JSON) throws -> [PlatformDescription] {
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

    private func parseTarget(json: JSON) throws -> TargetDescription {
        let providers = try? json
            .getArray("providers")
            .map(SystemPackageProviderDescription.init(v4:))

        let dependencies = try json
            .getArray("dependencies")
            .map(TargetDescription.Dependency.init(v4:))

        let sources: [String]? = try? json.get("sources")
        try sources?.forEach{ _ = try RelativePath(validating: $0) }

        let exclude: [String] = try json.get("exclude")
        try exclude.forEach{ _ = try RelativePath(validating: $0) }

        return TargetDescription(
            name: try json.get("name"),
            dependencies: dependencies,
            path: json.get("path"),
            url: json.get("url"),
            exclude: exclude,
            sources: sources,
            resources: try parseResources(json),
            publicHeadersPath: json.get("publicHeadersPath"),
            type: try .init(v4: json.get("type")),
            pkgConfig: json.get("pkgConfig"),
            providers: providers,
            settings: try parseBuildSettings(json),
            checksum: json.get("checksum")
        )
    }

    func parseResources(_ json: JSON) throws -> [TargetDescription.Resource] {
        guard let resourcesJSON = try? json.getArray("resources") else { return [] }
        if resourcesJSON.isEmpty {
            throw ManifestParseError.runtimeManifestErrors(["resources cannot be an empty array; provide at least one value or remove it"])
        }

        return try resourcesJSON.map { json in
            let rawRule = try json.get(String.self, forKey: "rule")
            let rule = TargetDescription.Resource.Rule(rawValue: rawRule)!
            let path = try RelativePath(validating: json.get(String.self, forKey: "path"))
            let localizationString = try? json.get(String.self, forKey: "localization")
            let localization = localizationString.map({ TargetDescription.Resource.Localization(rawValue: $0)! })
            return .init(rule: rule, path: path.pathString, localization: localization)
        }
    }

    func parseBuildSettings(_ json: JSON) throws -> [TargetBuildSettingDescription.Setting] {
        var settings: [TargetBuildSettingDescription.Setting] = []
        for tool in TargetBuildSettingDescription.Tool.allCases {
            let key = tool.rawValue + "Settings"
            if let settingsJSON = try? json.getJSON(key) {
                settings += try parseBuildSettings(settingsJSON, tool: tool, settingName: key)
            }
        }
        return settings
    }

    func parseBuildSettings(_ json: JSON, tool: TargetBuildSettingDescription.Tool, settingName: String) throws -> [TargetBuildSettingDescription.Setting] {
        let declaredSettings = try json.getArray()
        return try declaredSettings.map({
            try parseBuildSetting($0, tool: tool)
        })
    }

    func parseBuildSetting(_ json: JSON, tool: TargetBuildSettingDescription.Tool) throws -> TargetBuildSettingDescription.Setting {
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
            fatalError()
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
                fatalError()
            }

            self = .library(libraryType)

        default:
            fatalError("unexpected product type: \(json)")
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

extension PackageDependencyDescription.Requirement {
    fileprivate init(v4 json: JSON) throws {
        let type = try json.get(String.self, forKey: "type")
        switch type {
        case "branch":
            self = try .branch(json.get("identifier"))

        case "revision":
            self = try .revision(json.get("identifier"))

        case "range":
            let lowerBound = try json.get(String.self, forKey: "lowerBound")
            let upperBound = try json.get(String.self, forKey: "upperBound")
            self = .range(Version(string: lowerBound)! ..< Version(string: upperBound)!)

        case "exact":
            let identifier = try json.get(String.self, forKey: "identifier")
            self = .exact(Version(string: identifier)!)

        case "localPackage":
            self = .localPackage

        default:
            fatalError()
        }
    }
}

extension PackageDependencyDescription {
    fileprivate init(v4 json: JSON, toolsVersion: ToolsVersion, baseURL: String, fileSystem: FileSystem) throws {
        let isBaseURLRemote = URL.scheme(baseURL) != nil

        func fixURL(_ url: String, requirement: Requirement) throws -> String {
            // If base URL is remote (http/ssh), we can't do any "fixing".
            if isBaseURLRemote {
                return url
            }

            // If the dependency URL starts with '~/', try to expand it.
            if url.hasPrefix("~/") {
                return fileSystem.homeDirectory.appending(RelativePath(String(url.dropFirst(2)))).pathString
            }

            // If the dependency URL is not remote, try to "fix" it.
            if URL.scheme(url) == nil {
                // If the URL has no scheme, we treat it as a path (either absolute or relative to the base URL).
                return AbsolutePath(url, relativeTo: AbsolutePath(baseURL)).pathString
            }

            if case .localPackage = requirement {
                do {
                    return try AbsolutePath(validating: url).pathString
                } catch PathValidationError.invalidAbsolutePath(let path) {
                    throw ManifestParseError.invalidManifestFormat("'\(path)' is not a valid path for path-based dependencies; use relative or absolute path instead.", diagnosticFile: nil)
                }
            }

            return url
        }

        let requirement = try Requirement(v4: json.get("requirement"))
        let url = try fixURL(json.get("url"), requirement: requirement)
        let name: String? = json.get("name")
        self.init(name: name, url: url, requirement: requirement)
    }
}

extension TargetDescription.TargetType {
    fileprivate init(v4 string: String) throws {
        switch string {
        case "regular":
            self = .regular
        case "test":
            self = .test
        case "system":
            self = .system
        case "binary":
            self = .binary
        default:
            fatalError()
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
            fatalError()
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
