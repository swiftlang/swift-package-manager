/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageDescription
import PackageDescription4
import Utility

/// The supported manifest versions.
public enum ManifestVersion: Int {
    case three = 3
    case four
}

/**
 This contains the declarative specification loaded from package manifest
 files, and the tools for working with the manifest.
*/
public final class Manifest: ObjectIdentifierProtocol, CustomStringConvertible {

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
    public static var basename = "Package"

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

    /// The raw package description representation from manifest API targets.
    /// We support v3 and v4 right now.
    public enum RawPackage {
        case v3(PackageDescription.Package)
        case v4(PackageDescription4.Package)
    }

    /// The raw package description.
    public let package: RawPackage

    /// The legacy product descriptions.
    public let legacyProducts: [PackageDescription.Product]

    /// The version this package was loaded from, if known.
    public let version: Version?

    /// The name of the package.
    public var name: String {
        return package.name
    }

    /// The manifest version.
    public var manifestVersion: ManifestVersion {
        switch package {
        case .v3: return .three
        case .v4: return .four
        }
    }

    /// The flags that were used to interprete the manifest.
    public let interpreterFlags: [String]

    public init(
        path: AbsolutePath,
        url: String,
        package: RawPackage,
        legacyProducts: [PackageDescription.Product] = [],
        version: Version?,
        interpreterFlags: [String] = []
    ) {
        if case .v4 = package {
            precondition(legacyProducts.isEmpty, "Legacy products are not supported in v4 manifest.")
        }
        self.path = path
        self.url = url
        self.package = package
        self.legacyProducts = legacyProducts
        self.version = version
        self.interpreterFlags = interpreterFlags
    }

    public var description: String {
        return "<Manifest: \(name)>"
    }
}

extension Manifest {
    /// Returns JSON representation of this manifest.
    // Note: Right now we just return the JSON representation of the package,
    // but this can be expanded to include the details about manifest too.
    public func jsonString() throws -> String {
        // FIXME: It is unfortunate to re-parse the JSON string.
        return try JSON(string:  package.jsonString).toString(prettyPrint: true)
    }
}

// Common Raw Package properties exposed in terms of PackageDescription4 models.
// This way the high level code doesn't need to concern itself with conversion.
extension Manifest.RawPackage {

    var jsonString: String {
        switch self {
            case .v3(let package): return PackageDescription.jsonString(package: package)
            case .v4(let package): return PackageDescription4.jsonString(package: package)
        }
    }

    public var name: String {
        switch self {
            case .v3(let package): return package.name
            case .v4(let package): return package.name
        }
    }

    public var exclude: [String] {
        switch self {
            case .v3(let package): return package.exclude
            case .v4: return []
        }
    }

    public var pkgConfig: String? {
        switch self {
            case .v3(let package): return package.pkgConfig
            case .v4(let package): return package.pkgConfig
        }
    }

    public var targets: [PackageDescription4.Target] {
        switch self {
        case .v3(let package):
            return package.targets.map({ target in
                let dependencies: [PackageDescription4.Target.Dependency]
                dependencies = target.dependencies.map({ dependency in
                    switch dependency {
                    case .Target(let name):
                        return .target(name: name)
                    }
                })
                return .target(name: target.name, dependencies: dependencies)
            })

            case .v4(let package):
                return package.targets
        }
    }

    public var dependencies: [PackageDescription4.Package.Dependency] {
        switch self {
        case .v3(let package):
            return package.dependencies.map({
                .package(url: $0.url, $0.versionRange.asPD4Version)
            })

        case .v4(let package):
            return package.dependencies
        }
    }

    public var providers: [PackageDescription4.SystemPackageProvider]? {
        switch self {
        case .v3(let package):
            return package.providers?.map({
                switch $0 {
                case .Brew(let name): return .brew([name])
                case .Apt(let name): return .apt([name])
                }
            })

        case .v4(let package):
            return package.providers
        }
    }

    public var swiftLanguageVersions: [Int]? {
        switch self {
        case .v3(let package): return package.swiftLanguageVersions
        case .v4(let package): return package.swiftLanguageVersions
        }
    }
}

// MARK: - Version shim for PackageDescription4 -> PackageDescription.

extension PackageDescription4.Version {
    fileprivate init(pdVersion version: PackageDescription.Version) {
        let buildMetadata = version.buildMetadataIdentifier?.characters.split(separator: ".").map(String.init)
        self.init(
            version.major,
            version.minor,
            version.patch,
            prereleaseIdentifiers: version.prereleaseIdentifiers,
            buildMetadataIdentifiers: buildMetadata ?? [])
    }
}

extension Range where Bound == PackageDescription.Version {
    fileprivate var asPD4Version: Range<PackageDescription4.Version> {
        return PackageDescription4.Version(pdVersion: lowerBound) ..< PackageDescription4.Version(pdVersion: upperBound)
    }
}
