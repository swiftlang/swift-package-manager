/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility
import PackageDescription

/// Load PackageDescription models from the given JSON. The JSON is expected to be completely valid.
/// The base url is used to resolve any relative paths in the dependency declarations.
func loadPackageDescription(_ json: JSON, baseURL: String) throws
    -> (package: PackageDescription.Package, products: [PackageDescription.Product]) {
    // Construct objects from JSON.
    let package = PackageDescription.Package.fromJSON(json, baseURL: baseURL)
    let products = PackageDescription.Product.fromJSON(json)
    let errors = parseErrors(json)
    guard errors.isEmpty else {
        throw ManifestParseError.runtimeManifestErrors(errors)
    }
    return (package, products)
}

// All of these methods are file private and are unit tested using manifest loader.
extension PackageDescription.Package {
    fileprivate static func fromJSON(_ json: JSON, baseURL: String? = nil) -> PackageDescription.Package {
        // This is a private API, currently, so we do not currently try and
        // validate the input.
        guard case .dictionary(let topLevelDict) = json else { fatalError("unexpected item") }
        guard case .dictionary(let package)? = topLevelDict["package"] else { fatalError("missing package") }

        guard case .string(let name)? = package["name"] else { fatalError("missing 'name'") }

        var pkgConfig: String? = nil
        if case .string(let value)? = package["pkgConfig"] {
            pkgConfig = value
        }

        // Parse the targets.
        var targets: [PackageDescription.Target] = []
        if case .array(let array)? = package["targets"] {
            targets = array.map(PackageDescription.Target.fromJSON)
        }

        var providers: [PackageDescription.SystemPackageProvider]? = nil
        if case .array(let array)? = package["providers"] {
            providers = array.map(PackageDescription.SystemPackageProvider.fromJSON)
        }

        // Parse the dependencies.
        var dependencies: [PackageDescription.Package.Dependency] = []
        if case .array(let array)? = package["dependencies"] {
            dependencies = array.map({ PackageDescription.Package.Dependency.fromJSON($0, baseURL: baseURL) })
        }

        // Parse the compatible swift versions.
        var swiftLanguageVersions: [Int]? = nil
        if case .array(let array)? = package["swiftLanguageVersions"] {
            swiftLanguageVersions = array.map({
                guard case .int(let value) = $0 else { fatalError("swiftLanguageVersions contains non int element") }
                return value
            })
        }

        // Parse the exclude folders.
        var exclude: [String] = []
        if case .array(let array)? = package["exclude"] {
            exclude = array.map({ element in
                guard case .string(let excludeString) = element else {
                    fatalError("exclude contains non string element")
                }
                return excludeString
            })
        }

        return PackageDescription.Package(
            name: name,
            pkgConfig: pkgConfig,
            providers: providers,
            targets: targets,
            dependencies: dependencies,
            swiftLanguageVersions: swiftLanguageVersions,
            exclude: exclude)
    }
}

extension PackageDescription.Package.Dependency {
    fileprivate static func fromJSON(_ json: JSON, baseURL: String?) -> PackageDescription.Package.Dependency {
        guard case .dictionary(let dict) = json else { fatalError("Unexpected item") }

        guard case .string(let url)? = dict["url"],
              case .dictionary(let versionDict)? = dict["version"],
              case .string(let vv1)? = versionDict["lowerBound"],
              case .string(let vv2)? = versionDict["upperBound"],
              let v1 = Version(vv1), let v2 = Version(vv2)
        else {
            fatalError("Unexpected item")
        }

        func fixURL() -> String {
            if let baseURL = baseURL, URL.scheme(url) == nil {
                // If the URL has no scheme, we treat it as a path (either absolute or relative to the base URL).
                return AbsolutePath(url, relativeTo: AbsolutePath(baseURL)).asString
            } else {
                return url
            }
        }

        return PackageDescription.Package.Dependency.Package(url: fixURL(), versions: v1..<v2)
    }
}

extension PackageDescription.SystemPackageProvider {
    fileprivate static func fromJSON(_ json: JSON) -> PackageDescription.SystemPackageProvider {
        guard case .dictionary(let dict) = json else { fatalError("unexpected item") }
        guard case .string(let name)? = dict["name"] else { fatalError("missing name") }
        guard case .string(let value)? = dict["value"] else { fatalError("missing value") }
        switch name {
        case "Brew":
            return .Brew(value)
        case "Apt":
            return .Apt(value)
        default:
            fatalError("unexpected string")
        }
    }
}

extension PackageDescription.Target {
    fileprivate static func fromJSON(_ json: JSON) -> PackageDescription.Target {
        guard case .dictionary(let dict) = json else { fatalError("unexpected item") }
        guard case .string(let name)? = dict["name"] else { fatalError("missing name") }

        var dependencies: [PackageDescription.Target.Dependency] = []
        if case .array(let array)? = dict["dependencies"] {
            dependencies = array.map(PackageDescription.Target.Dependency.fromJSON)
        }

        return PackageDescription.Target(name: name, dependencies: dependencies)
    }
}

extension PackageDescription.Target.Dependency {
    fileprivate static func fromJSON(_ item: JSON) -> PackageDescription.Target.Dependency {
        guard case .string(let name) = item else { fatalError("unexpected item") }
        return .Target(name: name)
    }
}

extension PackageDescription.Product {

    fileprivate static func fromJSON(_ json: JSON) -> [PackageDescription.Product] {
        guard case .dictionary(let topLevelDict) = json else { fatalError("unexpected item") }
        guard case .array(let array)? = topLevelDict["products"] else { fatalError("unexpected item") }
        return array.map(Product.init)
    }

    private init(_ json: JSON) {
        guard case .dictionary(let dict) = json else { fatalError("unexpected item") }
        guard case .string(let name)? = dict["name"] else { fatalError("missing item") }
        guard case .string(let productType)? = dict["type"] else { fatalError("missing item") }
        guard case .array(let targetsJSON)? = dict["modules"] else { fatalError("missing item") }

        let modules: [String] = targetsJSON.map({
            guard case JSON.string(let string) = $0 else { fatalError("invalid item") }
            return string
        })
        self.init(name: name, type: ProductType(productType), modules: modules)
    }
}

extension PackageDescription.ProductType {
    fileprivate init(_ string: String) {
        switch string {
        case "exe":
            self = .Executable
        case "a":
            self = .Library(.Static)
        case "dylib":
            self = .Library(.Dynamic)
        case "test":
            self = .Test
        default:
            fatalError("invalid string \(string)")
        }
    }
}

fileprivate func parseErrors(_ json: JSON) -> [String] {
    guard case .dictionary(let topLevelDict) = json else { fatalError("unexpected item") }
    guard case .array(let errors)? = topLevelDict["errors"] else { fatalError("missing errors") }
    return errors.map({ error in
        guard case .string(let string) = error else { fatalError("unexpected item") }
        return string
    })
}
