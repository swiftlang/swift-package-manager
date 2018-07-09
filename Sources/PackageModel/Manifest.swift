/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility

/// The supported manifest versions.
public enum ManifestVersion: String, Codable {
    case v3 = "3"
    case v4 = "4"
    case v4_2 = "4_2"

    /// The Swift language version to use when parsing the manifest file.
    public var swiftLanguageVersion: SwiftLanguageVersion {
        switch self {
        case .v3: return .v3
        case .v4: return .v4
        case .v4_2: return .v4_2
        }
    }
}

/// This contains the declarative specification loaded from package manifest
/// files, and the tools for working with the manifest.
public final class Manifest: ObjectIdentifierProtocol, CustomStringConvertible, Codable {

    /// The standard filename for the manifest.
    public static var filename = basename + ".swift"

    /// Returns the manifest at the given package path.
    ///
    /// Version specific manifest is chosen if present, otherwise path to regular
    /// manfiest is returned.
    public static func path(
        atPackagePath packagePath: AbsolutePath,
        fileSystem: FileSystem
    ) -> AbsolutePath {
        for versionSpecificKey in Versioning.currentVersionSpecificKeys {
            let versionSpecificPath = packagePath.appending(component: Manifest.basename + versionSpecificKey + ".swift")
            if fileSystem.isFile(versionSpecificPath) {
                return versionSpecificPath
            }
        }
        return packagePath.appending(component: filename)
    }

    /// The standard basename for the manifest.
    public static let basename = "Package"

    /// The path of the manifest file.
    //
    // FIXME: This doesn't belong here, we want the Manifest to be purely tied
    // to the repository state, it shouldn't matter where it is.
    public let path: AbsolutePath

    /// The repository URL the manifest was loaded from.
    //
    // FIXME: This doesn't belong here, we want the Manifest to be purely tied
    // to the repository state, it shouldn't matter where it is.
    public let url: String

    /// The version this package was loaded from, if known.
    public let version: Version?

    /// The version of manifest.
    public let manifestVersion: ManifestVersion

    /// The name of the package.
    public let name: String

    /// The declared package dependencies.
    public let dependencies: [PackageDependencyDescription]

    /// The targets declared in the manifest.
    public let targets: [TargetDescription]

    /// The products declared in the manifest.
    public let products: [ProductDescription]

    /// The flags that were used to interprete the manifest.
    public let interpreterFlags: [String]

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

    /// The legacy style products that can be declared in the v3 manifests.
    public let legacyProducts: [ProductDescription]

    /// The legacy style excludes that can be declared in the v3 manifests.
    public let legacyExclude: [String]

    public init(
        name: String,
        path: AbsolutePath,
        url: String,
        legacyProducts: [ProductDescription] = [],
        legacyExclude: [String] = [],
        version: Utility.Version? = nil,
        interpreterFlags: [String] = [],
        manifestVersion: ManifestVersion,
        pkgConfig: String? = nil,
        providers: [SystemPackageProviderDescription]? = nil,
        cLanguageStandard: String? = nil,
        cxxLanguageStandard: String? = nil,
        swiftLanguageVersions: [SwiftLanguageVersion]? = nil,
        dependencies: [PackageDependencyDescription] = [],
        products: [ProductDescription] = [],
        targets: [TargetDescription] = []
    ) {
        if manifestVersion != .v3 {
            precondition(legacyProducts.isEmpty, "Legacy products are not supported in v4 manifest.")
        }
        self.name = name
        self.path = path
        self.url = url
        self.legacyProducts = legacyProducts
        self.version = version
        self.interpreterFlags = interpreterFlags
        self.manifestVersion = manifestVersion
        self.legacyExclude = legacyExclude
        self.pkgConfig = pkgConfig
        self.providers = providers
        self.cLanguageStandard = cLanguageStandard
        self.cxxLanguageStandard = cxxLanguageStandard
        self.swiftLanguageVersions = swiftLanguageVersions
        self.dependencies = dependencies
        self.products = products
        self.targets = targets
    }

    public var description: String {
        return "<Manifest: \(name)>"
    }
}

extension Manifest {
    /// Returns JSON representation of this manifest.
    public func jsonString() throws -> String {
        fatalError("unsupported for now")
    }
}

/// The description of an individual target.
public struct TargetDescription: Equatable, Codable {

    /// The target type.
    public enum TargetType: String, Equatable, Codable {
        case regular
        case test
        case system
    }

    /// Represents a target's dependency on another entity.
    public enum Dependency: Equatable, ExpressibleByStringLiteral {
        case target(name: String)
        case product(name: String, package: String?)
        case byName(name: String)

        public init(stringLiteral value: String) {
            self = .byName(name: value)
        }

        public static func product(name: String) -> Dependency {
            return .product(name: name, package: nil)
        }
    }

    /// The name of the target.
    public let name: String

    /// The custom path of the target.
    public let path: String?

    /// The custom sources of the target.
    public let sources: [String]?

    /// The exclude patterns.
    public let exclude: [String]

    /// Returns true if the target type is test.
    // FIXME: Kill this.
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

    public init(
        name: String,
        dependencies: [Dependency] = [],
        path: String? = nil,
        exclude: [String] = [],
        sources: [String]? = nil,
        publicHeadersPath: String? = nil,
        type: TargetType = .regular,
        pkgConfig: String? = nil,
        providers: [SystemPackageProviderDescription]? = nil
    ) {
        switch type {
        case .regular, .test:
            precondition(pkgConfig == nil && providers == nil)
        case .system: break
        }

        self.name = name
        self.dependencies = dependencies
        self.path = path
        self.publicHeadersPath = publicHeadersPath
        self.sources = sources
        self.exclude = exclude
        self.type = type
        self.pkgConfig = pkgConfig
        self.providers = providers
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
}

/// Represents a package dependency.
public struct PackageDependencyDescription: Equatable, Codable {

    /// The dependency requirement.
    public enum Requirement: Equatable {
        case exact(Version)
        case range(Range<Version>)
        case revision(String)
        case branch(String)
        case localPackage

        public static func upToNextMajor(from version: Utility.Version) -> Requirement {
            return .range(version..<Version(version.major + 1, 0, 0))
        }

        public static func upToNextMinor(from version: Utility.Version) -> Requirement {
            return .range(version..<Version(version.major, version.minor + 1, 0))
        }
    }

    /// The url of the dependency.
    public let url: String

    /// The dependency requirement.
    public let requirement: Requirement

    /// Create a dependency.
    public init(url: String, requirement: Requirement) {
        self.url = url
        self.requirement = requirement
    }
}
