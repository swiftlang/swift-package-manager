/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility
import PackageDescription4

/// Load PackageDescription4 models from the given JSON. The JSON is expected to be completely valid.
/// The base url is used to resolve any relative paths in the dependency declarations.
func loadPackageDescription4(
   _ json: JSON,
   baseURL: String
) throws -> PackageDescription4.Package {
    // Construct objects from JSON.
    let package = PackageDescription4.Package.fromJSON(json, baseURL: baseURL)
    let errors = parseErrors(json)
    guard errors.isEmpty else {
        throw ManifestParseError.runtimeManifestErrors(errors)
    }
    return package
}

// All of these methods are file private and are unit tested using manifest loader.
extension PackageDescription4.Package {
    fileprivate static func fromJSON(_ json: JSON, baseURL: String? = nil) -> PackageDescription4.Package {
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
        var targets: [PackageDescription4.Target] = []
        if case .array(let array)? = package["targets"] {
            targets = array.map(PackageDescription4.Target.fromJSON)
        }

        var providers: [PackageDescription4.SystemPackageProvider]? = nil
        if case .array(let array)? = package["providers"] {
            providers = array.map(PackageDescription4.SystemPackageProvider.fromJSON)
        }

        // Parse the dependencies.
        var dependencies: [PackageDescription4.Package.Dependency] = []
        if case .array(let array)? = package["dependencies"] {
            dependencies = array.map { PackageDescription4.Package.Dependency.fromJSON($0, baseURL: baseURL) }
        }

        // Parse the exclude folders.
        var exclude: [String] = []
        if case .array(let array)? = package["exclude"] {
            exclude = array.map { element in
                guard case .string(let excludeString) = element else { fatalError("exclude contains non string element") }
                return excludeString
            }
        }

        return PackageDescription4.Package(name: name, pkgConfig: pkgConfig, providers: providers, targets: targets, dependencies: dependencies, exclude: exclude)
    }
}

extension PackageDescription4.Package.Dependency {
    fileprivate static func fromJSON(_ json: JSON, baseURL: String?) -> PackageDescription4.Package.Dependency {
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

        return PackageDescription4.Package.Dependency.Package(url: fixURL(), versions: v1..<v2)
    }
}

extension PackageDescription4.SystemPackageProvider {
    fileprivate static func fromJSON(_ json: JSON) -> PackageDescription4.SystemPackageProvider {
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

extension PackageDescription4.Target {
    fileprivate static func fromJSON(_ json: JSON) -> PackageDescription4.Target {
        guard case .dictionary(let dict) = json else { fatalError("unexpected item") }
        guard case .string(let name)? = dict["name"] else { fatalError("missing name") }

        var dependencies: [PackageDescription4.Target.Dependency] = []
        if case .array(let array)? = dict["dependencies"] {
            dependencies = array.map(PackageDescription4.Target.Dependency.fromJSON)
        }

        return PackageDescription4.Target(name: name, dependencies: dependencies)
    }
}

extension PackageDescription4.Target.Dependency {
    fileprivate static func fromJSON(_ item: JSON) -> PackageDescription4.Target.Dependency {
        guard case .string(let name) = item else { fatalError("unexpected item") }
        return .Target(name: name)
    }
}

fileprivate func parseErrors(_ json: JSON) -> [String] {
    guard case .dictionary(let topLevelDict) = json else { fatalError("unexpected item") }
    guard case .array(let errors)? = topLevelDict["errors"] else { fatalError("missing errors") }
    return errors.map { error in
        guard case .string(let string) = error else { fatalError("unexpected item") }
        return string
    }
}
