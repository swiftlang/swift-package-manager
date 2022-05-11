//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
#if canImport(Glibc)
@_implementationOnly import Glibc
#elseif canImport(Darwin)
@_implementationOnly import Darwin.C
#elseif canImport(ucrt) && canImport(WinSDK)
@_implementationOnly import ucrt
@_implementationOnly import struct WinSDK.HANDLE
#endif

// MARK: - Package JSON serialization

extension Package: Encodable {
    private enum CodingKeys: CodingKey {
        case name
        case defaultLocalization
        case platforms
        case pkgConfig
        case providers
        case products
        case dependencies
        case targets
        case swiftLanguageVersions
        case cLanguageStandard
        case cxxLanguageStandard
    }

    /// Encodes this value into the given encoder.
    ///
    /// If the value fails to encode anything, `encoder` will encode an empty
    /// keyed container in its place.
    ///
    /// This function throws an error if any values are invalid for the given
    /// encoder's format.
    ///
    /// - Parameter encoder: The encoder to write data to.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)

        if let defaultLocalization = self.defaultLocalization {
            try container.encode(defaultLocalization.tag, forKey: .defaultLocalization)
        }
        if let platforms = self.platforms {
            try container.encode(platforms, forKey: .platforms)
        }

        try container.encode(self.pkgConfig, forKey: .pkgConfig)
        try container.encode(self.providers, forKey: .providers)
        try container.encode(self.products, forKey: .products)
        try container.encode(self.dependencies, forKey: .dependencies)
        try container.encode(self.targets, forKey: .targets)
        try container.encode(self.swiftLanguageVersions, forKey: .swiftLanguageVersions)
        try container.encode(self.cLanguageStandard, forKey: .cLanguageStandard)
        try container.encode(self.cxxLanguageStandard, forKey: .cxxLanguageStandard)
    }
}

@available(_PackageDescription, deprecated: 5.6)
extension Package.Dependency.Requirement: Encodable {
    private enum CodingKeys: CodingKey {
        case type
        case lowerBound
        case upperBound
        case identifier
    }

    private enum Kind: String, Codable {
        case range
        case exact
        case branch
        case revision
        case localPackage
    }

    /// Encodes this value into the given encoder.
    ///
    /// This function throws an error if any values are invalid for the given
    /// encoder's format.
    ///
    /// - Parameter encoder: The encoder to write data to.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .rangeItem(let range):
            try container.encode(Kind.range, forKey: .type)
            try container.encode(range.lowerBound, forKey: .lowerBound)
            try container.encode(range.upperBound, forKey: .upperBound)
        case .exactItem(let version):
            try container.encode(Kind.exact, forKey: .type)
            try container.encode(version, forKey: .identifier)
        case .branchItem(let identifier):
            try container.encode(Kind.branch, forKey: .type)
            try container.encode(identifier, forKey: .identifier)
        case .revisionItem(let identifier):
            try container.encode(Kind.revision, forKey: .type)
            try container.encode(identifier, forKey: .identifier)
        case .localPackageItem:
            try container.encode(Kind.localPackage, forKey: .type)
        }
    }
}

extension Package.Dependency.Kind: Encodable {
    private enum CodingKeys: CodingKey {
        case type
        case name
        case path
        case location
        case requirement
        case identity
    }

    private enum Kind: String, Codable {
        case fileSystem
        case sourceControl
        case registry
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fileSystem(let name, let path):
            try container.encode(Kind.fileSystem, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(path, forKey: .path)
        case .sourceControl(let name, let location, let requirement):
            try container.encode(Kind.sourceControl, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(location, forKey: .location)
            try container.encode(requirement, forKey: .requirement)
        case .registry(let identity, let requirement):
            try container.encode(Kind.registry, forKey: .type)
            try container.encode(identity, forKey: .identity)
            try container.encode(requirement, forKey: .requirement)
        }
    }
}

extension Package.Dependency.SourceControlRequirement: Encodable {
    private enum CodingKeys: CodingKey {
        case type
        case lowerBound
        case upperBound
        case identifier
    }

    private enum Kind: String, Codable {
        case range
        case exact
        case branch
        case revision
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .range(let range):
            try container.encode(Kind.range, forKey: .type)
            try container.encode(range.lowerBound, forKey: .lowerBound)
            try container.encode(range.upperBound, forKey: .upperBound)
        case .exact(let version):
            try container.encode(Kind.exact, forKey: .type)
            try container.encode(version, forKey: .identifier)
        case .branch(let identifier):
            try container.encode(Kind.branch, forKey: .type)
            try container.encode(identifier, forKey: .identifier)
        case .revision(let identifier):
            try container.encode(Kind.revision, forKey: .type)
            try container.encode(identifier, forKey: .identifier)
        }
    }
}

extension Package.Dependency.RegistryRequirement: Encodable {
    private enum CodingKeys: CodingKey {
        case type
        case lowerBound
        case upperBound
        case identifier
    }

    private enum Kind: String, Codable {
        case range
        case exact
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .range(let range):
            try container.encode(Kind.range, forKey: .type)
            try container.encode(range.lowerBound, forKey: .lowerBound)
            try container.encode(range.upperBound, forKey: .upperBound)
        case .exact(let version):
            try container.encode(Kind.exact, forKey: .type)
            try container.encode(version, forKey: .identifier)
        }
    }
}

extension SystemPackageProvider: Encodable {
    private enum CodingKeys: CodingKey {
        case name
        case values
    }

    private enum Name: String, Encodable {
        case brew
        case apt
        case yum
        case nuget
    }

    /// Encodes this value into the given encoder.
    ///
    /// If the value fails to encode anything, `encoder` will encode an empty
    /// keyed container in its place.
    ///
    /// This function throws an error if any values are invalid for the given
    /// encoder's format.
    ///
    /// - Parameter encoder: The encoder to write data to.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .brewItem(let packages):
            try container.encode(Name.brew, forKey: .name)
            try container.encode(packages, forKey: .values)
        case .aptItem(let packages):
            try container.encode(Name.apt, forKey: .name)
            try container.encode(packages, forKey: .values)
        case .yumItem(let packages):
            try container.encode(Name.yum, forKey: .name)
            try container.encode(packages, forKey: .values)
        case .nugetItem(let packages):
            try container.encode(Name.nuget, forKey: .name)
            try container.encode(packages, forKey: .values)
        }
    }
}

extension Target.PluginCapability: Encodable {
    private enum CodingKeys: CodingKey {
        case type, intent, permissions
    }

    private enum Capability: String, Encodable {
        case buildTool, command
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case ._buildTool:
            try container.encode(Capability.buildTool, forKey: .type)
        case ._command(let intent, let permissions):
            try container.encode(Capability.command, forKey: .type)
            try container.encode(intent, forKey: .intent)
            try container.encode(permissions, forKey: .permissions)
        }
    }
}

extension PluginCommandIntent: Encodable {
    private enum CodingKeys: CodingKey {
        case type, verb, description
    }

    private enum IntentType: String, Encodable {
        case documentationGeneration, sourceCodeFormatting, custom
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case ._documentationGeneration:
            try container.encode(IntentType.documentationGeneration, forKey: .type)
        case ._sourceCodeFormatting:
            try container.encode(IntentType.sourceCodeFormatting, forKey: .type)
        case ._custom(let verb, let description):
            try container.encode(IntentType.custom, forKey: .type)
            try container.encode(verb, forKey: .verb)
            try container.encode(description, forKey: .description)
        }
    }
}

/// `Encodable` conformance.
extension PluginPermission: Encodable {
    private enum CodingKeys: CodingKey {
        case type, reason
    }

    private enum PermissionType: String, Encodable {
        case writeToPackageDirectory
    }

    /// Encode the `PluginPermission` into the given encoder.
    ///
    /// - Parameter to: The encoder to write data to.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case ._writeToPackageDirectory(let reason):
            try container.encode(PermissionType.writeToPackageDirectory, forKey: .type)
            try container.encode(reason, forKey: .reason)
        }
    }
}

extension Target.Dependency: Encodable {
    private enum CodingKeys: CodingKey {
        case type
        case name
        case package
        case moduleAliases
        case condition
    }

    private enum Kind: String, Codable {
        case target
        case product
        case byName = "byname"
    }

    /// Encodes the `Target.Dependency` into the given encoder.
    ///
    /// If the value fails to encode anything, `encoder` will encode an empty
    /// keyed container in its place.
    ///
    /// This function throws an error if any values are invalid for the given
    /// encoder's format.
    ///
    /// - Parameter encoder: The encoder to write data to.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .targetItem(let name, let condition):
            try container.encode(Kind.target, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(condition, forKey: .condition)
        case .productItem(let name, let package, let moduleAliases, let condition):
            try container.encode(Kind.product, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(package, forKey: .package)
            try container.encode(moduleAliases, forKey: .moduleAliases)
            try container.encode(condition, forKey: .condition)
        case .byNameItem(let name, let condition):
            try container.encode(Kind.byName, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(condition, forKey: .condition)
        }
    }
}

extension Target: Encodable {
    private enum CodingKeys: CodingKey {
        case name
        case path
        case url
        case sources
        case resources
        case exclude
        case dependencies
        case publicHeadersPath
        case type
        case pkgConfig
        case providers
        case pluginCapability
        case cSettings
        case cxxSettings
        case swiftSettings
        case linkerSettings
        case checksum
        case pluginUsages
    }

    /// Encodes this value into the given encoder.
    ///
    /// If the value fails to encode anything, `encoder` will encode an empty
    /// keyed container in its place.
    ///
    /// This function throws an error if any values are invalid for the given
    /// encoder's format.
    ///
    /// - Parameter encoder: The encoder to write data to.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encode(url, forKey: .url)
        try container.encode(sources, forKey: .sources)
        try container.encode(resources, forKey: .resources)
        try container.encode(exclude, forKey: .exclude)
        try container.encode(dependencies, forKey: .dependencies)
        try container.encode(publicHeadersPath, forKey: .publicHeadersPath)
        try container.encode(type, forKey: .type)
        try container.encode(pkgConfig, forKey: .pkgConfig)
        try container.encode(providers, forKey: .providers)
        try container.encode(pluginCapability, forKey: .pluginCapability)
        try container.encode(checksum, forKey: .checksum)

        if let cSettings = self.cSettings {
            try container.encode(cSettings, forKey: .cSettings)
        }

        if let cxxSettings = self.cxxSettings {
            try container.encode(cxxSettings, forKey: .cxxSettings)
        }

        if let swiftSettings = self.swiftSettings {
            try container.encode(swiftSettings, forKey: .swiftSettings)
        }

        if let linkerSettings = self.linkerSettings {
            try container.encode(linkerSettings, forKey: .linkerSettings)
        }

        if let pluginUsages = self.plugins {
            try container.encode(pluginUsages, forKey: .pluginUsages)
        }
    }
}

extension Target.PluginUsage: Encodable {
    private enum CodingKeys: CodingKey {
        case type, name, package
    }

    private enum Kind: String, Codable {
        case plugin
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case ._pluginItem(let name, let package):
            try container.encode(Kind.plugin, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(package, forKey: .package)
        }
    }
}

extension SwiftVersion: Encodable {
    /// Encodes this value into the given encoder.
    ///
    /// This function throws an error if any values are invalid for the given
    /// encoder's format.
    ///
    /// - Parameter encoder: The encoder to write data to.
    public func encode(to encoder: Encoder) throws {
        let value: String

        switch self {
        case .v3:
            value = "3"
        case .v4:
            value = "4"
        case .v4_2:
            value = "4.2"
        case .v5:
            value = "5"
        case .version(let v):
            value = v
        }

        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

extension Version: Encodable {
    /// Encodes this value into the given encoder.
    ///
    /// This function throws an error if any values are invalid for the given
    /// encoder's format.
    ///
    /// - Parameter encoder: The encoder to write data to.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
