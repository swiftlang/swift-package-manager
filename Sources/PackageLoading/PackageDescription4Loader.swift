/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import SPMUtility
import PackageModel

extension ManifestBuilder {
    mutating func build(v4 json: JSON) throws {
        let package = try json.getJSON("package")
        self.name = try package.get(String.self, forKey: "name")
        self.pkgConfig = package.get("pkgConfig")
        self.platforms = try parsePlatforms(package)
        self.swiftLanguageVersions = try parseSwiftLanguageVersion(package)
        self.products = try package.getArray("products").map(ProductDescription.init(v4:))
        self.providers = try? package.getArray("providers").map(SystemPackageProviderDescription.init(v4:))
        self.targets = try package.getArray("targets").map(parseTarget(json:))
        self.dependencies = try package
             .getArray("dependencies")
             .map({ try PackageDependencyDescription(v4: $0, baseURL: self.baseURL, fileSystem: self.fs) })

        self.cxxLanguageStandard = package.get("cxxLanguageStandard")
        self.cLanguageStandard = package.get("cLanguageStandard")

        self.errors = try json.get("errors")
    }

    func parseSwiftLanguageVersion(_ package: JSON) throws -> [SwiftLanguageVersion]?  {
        guard let versionJSON = try? package.getArray("swiftLanguageVersions") else {
            return nil
        }

        /// Parse the versioned value.
        let versionedValues = try versionJSON.map({ try VersionedValue(json: $0) })

        return try versionedValues.map { versionedValue in
            // Validate that this versioned value is supported by the current
            // manifest version.
            try versionedValue.validate(for: self.manifestVersion)

            return try SwiftLanguageVersion(string: String(json: versionedValue.value))!
        }
    }

    func parsePlatforms(_ package: JSON) throws -> [PlatformDescription] {
        guard let platformsJSON = try? package.getJSON("platforms") else {
            return []
        }

        /// Ensure that platforms API is used in the right manifest version.
        let versionedPlatforms = try VersionedValue(json: platformsJSON)
        try versionedPlatforms.validate(for: self.manifestVersion)

        // Get the declared platform list.
        let declaredPlatforms = try versionedPlatforms.value.getArray()

        // Empty list is not supported.
        if declaredPlatforms.isEmpty {
            throw ManifestParseError.runtimeManifestErrors(["supported platforms can't be empty"])
        }

        // Start parsing platforms.
        var platforms: [PlatformDescription] = []

        for platformJSON in declaredPlatforms {
            // Parse the version and validate that it can be used in the current
            // manifest version.
            let versionJSON = try platformJSON.getJSON("version")
            let versionedVersion = try VersionedValue(json: versionJSON)
            try versionedVersion.validate(for: self.manifestVersion)

            // Get the actual value of the version.
            let version = try String(json: versionedVersion.value)

            // Get the platform name.
            let platformName: String = try platformJSON.getJSON("platform").get("name")

            let description = PlatformDescription(name: platformName, version: version)

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

        return TargetDescription(
            name: try json.get("name"),
            dependencies: dependencies,
            path: json.get("path"),
            exclude: try json.get("exclude"),
            sources: try? json.get("sources"),
            publicHeadersPath: json.get("publicHeadersPath"),
            type: try .init(v4: json.get("type")),
            pkgConfig: json.get("pkgConfig"),
            providers: providers,
            settings: try parseBuildSettings(json)
        )
    }

    func parseBuildSettings(_ json: JSON) throws -> [TargetBuildSettingDescription.Setting] {
        var settings: [TargetBuildSettingDescription.Setting] = []
        for tool in TargetBuildSettingDescription.Tool.allCases {
            let key = tool.rawValue + "Settings"
            if let settingsJSON = try? json.getJSON(key) {
                settings += try parseBuildSettings(settingsJSON, tool: tool)
            }
        }
        return settings
    }

    func parseBuildSettings(_ json: JSON, tool: TargetBuildSettingDescription.Tool) throws -> [TargetBuildSettingDescription.Setting] {
        let versionedValue = try VersionedValue(json: json)
        try versionedValue.validate(for: self.manifestVersion)

        let declaredSettings = try versionedValue.value.getArray()
        if declaredSettings.isEmpty {
            throw ManifestParseError.runtimeManifestErrors(["empty list not supported"])
        }

        return try declaredSettings.map({
            try parseBuildSetting($0, tool: tool)
        })
    }

    func parseBuildSetting(_ json: JSON, tool: TargetBuildSettingDescription.Tool) throws -> TargetBuildSettingDescription.Setting {
        let json = try json.getJSON("data")
        let name = try TargetBuildSettingDescription.SettingName(rawValue: json.get("name"))!

        var condition: TargetBuildSettingDescription.Condition?
        if let conditionJSON = try? json.getJSON("condition") {
            condition = try parseCondition(conditionJSON)
        }

        return .init(
            tool: tool, name: name,
            value: try json.get("value"),
            condition: condition
        )
    }

    func parseCondition(_ json: JSON) throws -> TargetBuildSettingDescription.Condition {
        let platformNames: [String]? = try? json.getArray("platforms").map({ try $0.get("name") })
        return .init(
            platformNames: platformNames ?? [],
            config: try? json.get("config").get("config")
        )
    }
}

struct VersionedValue: JSONMappable {
    let supportedVersions: [ManifestVersion]
    let value: JSON
    let api: String

    init(json: JSON) throws {
        self.api = try json.get(String.self, forKey: "api")
        self.value = try json.getJSON("value")

        let supportedVersionsJSON = try json.get([String].self, forKey: "supportedVersions")
        self.supportedVersions = supportedVersionsJSON.map({ ManifestVersion(rawValue: $0)! })
    }

    func validate(for manifestVersion: ManifestVersion) throws {
        if !supportedVersions.contains(manifestVersion) {
            throw ManifestParseError.unsupportedAPI(
                api: api,
                supportedVersions: supportedVersions
            )
        }
    }
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
    fileprivate init(v4 json: JSON, baseURL: String, fileSystem: FileSystem) throws {
        let isBaseURLRemote = URL.scheme(baseURL) != nil

        func fixURL(_ url: String) -> String {
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

            return url
        }

        try self.init(
            url: fixURL(json.get("url")),
            requirement: .init(v4: json.get("requirement"))
        )
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
        default:
            fatalError()
        }
    }
}

extension TargetDescription.Dependency {
    fileprivate init(v4 json: JSON) throws {
        let type = try json.get(String.self, forKey: "type")

        switch type {
        case "target":
            self = try .target(name: json.get("name"))

        case "product":
            let name = try json.get(String.self, forKey: "name")
            self = .product(name: name, package: json.get("package"))

        case "byname":
            self = try .byName(name: json.get("name"))

        default:
            fatalError()
        }
    }
}
