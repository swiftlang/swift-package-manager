/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility
import PackageModel

extension ManifestBuilder {
    init(v4 json: JSON, baseURL: String, fileSystem: FileSystem) throws {
        let package = try json.getJSON("package")
        self.name = try package.get("name")
        self.pkgConfig = package.get("pkgConfig")
        let slv = try? package.get([String].self, forKey: "swiftLanguageVersions")
        self.swiftLanguageVersions = slv?.compactMap(SwiftLanguageVersion.init(string:))
        self.products = try package.getArray("products").map(ProductDescription.init(v4:))
        self.providers = try? package.getArray("providers").map(SystemPackageProviderDescription.init(v4:))
        self.targets = try package.getArray("targets").map(TargetDescription.init(v4:))
        self.dependencies = try package
             .getArray("dependencies")
             .map({ try PackageDependencyDescription(v4: $0, baseURL: baseURL, fileSystem: fileSystem) })

        self.cxxLanguageStandard = package.get("cxxLanguageStandard")
        self.cLanguageStandard = package.get("cLanguageStandard")

        self.errors = try json.get("errors")
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
                return fileSystem.homeDirectory.appending(RelativePath(String(url.dropFirst(2)))).asString
            }

            // If the dependency URL is not remote, try to "fix" it.
            if URL.scheme(url) == nil {
                // If the URL has no scheme, we treat it as a path (either absolute or relative to the base URL).
                return AbsolutePath(url, relativeTo: AbsolutePath(baseURL)).asString
            }

            return url
        }

        try self.init(
            url: fixURL(json.get("url")),
            requirement: .init(v4: json.get("requirement"))
        )
    }
}

extension TargetDescription {
    fileprivate init(v4 json: JSON) throws {
        let providers = try? json
            .getArray("providers")
            .map(SystemPackageProviderDescription.init(v4:))

        let dependencies = try json
            .getArray("dependencies")
            .map(TargetDescription.Dependency.init(v4:))

        self.init(
            name: try json.get("name"),
            dependencies: dependencies,
            path: json.get("path"),
            exclude: try json.get("exclude"),
            sources: try? json.get("sources"),
            publicHeadersPath: json.get("publicHeadersPath"),
            type: try .init(v4: json.get("type")),
            pkgConfig: json.get("pkgConfig"),
            providers: providers
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
