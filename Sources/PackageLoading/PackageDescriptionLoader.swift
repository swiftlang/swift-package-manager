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
    init(v3 json: JSON, baseURL: String) throws {
        let package = try json.getJSON("package")
        self.name = try package.get("name")
        self.exclude = try package.get("exclude")
        self.targets = try package.getArray("targets").map(TargetDescription.init(v3:))
        self.pkgConfig = package.get("pkgConfig")
        self.providers = try? package.getArray("providers").map(SystemPackageProviderDescription.init(v3:))
        self.dependencies = try package
            .getArray("dependencies")
            .map({ try PackageDependencyDescription(v3: $0, baseURL: baseURL) })

        let slv = try? package.get([Int].self, forKey: "swiftLanguageVersions")
        self.swiftLanguageVersions = slv?.map(String.init).compactMap(SwiftLanguageVersion.init(string:))

        self.errors = try json.get("errors")
        self.products = try json.getArray("products").map(ProductDescription.init(v3:))
    }
}

extension TargetDescription {
    fileprivate init(v3 json: JSON) throws {
        let deps = try json.get([String].self, forKey: "dependencies")
        try self.init(
            name: json.get("name"),
            dependencies: deps.map({ .target(name: $0) }),
            type: .regular
        )
    }
}

extension PackageDependencyDescription.Requirement {
    fileprivate init(v3 json: JSON) throws {
        let lowerBound = try json.get(String.self, forKey: "lowerBound")
        let upperBound = try json.get(String.self, forKey: "upperBound")
        self = .range(Version(string: lowerBound)! ..< Version(string: upperBound)!)
    }
}

extension PackageDependencyDescription {
    fileprivate init(v3 json: JSON, baseURL: String) throws {
        func fixURL(_ url: String) -> String {
            if URL.scheme(url) == nil {
                // If the URL has no scheme, we treat it as a path (either absolute or relative to the base URL).
                return AbsolutePath(url, relativeTo: AbsolutePath(baseURL)).asString
            }
            return url
        }
        try self.init(
            url: fixURL(json.get("url")),
            requirement: .init(v3: json.get("version"))
        )
    }
}

extension SystemPackageProviderDescription {
    fileprivate init(v3 json: JSON) throws {
        let name = try json.get(String.self, forKey: "name")
        let value = try json.get(String.self, forKey: "value")
        switch name {
        case "Brew":
            self = .brew([value])
        case "Apt":
            self = .apt([value])
        default:
            fatalError()
        }
    }
}

extension PackageModel.ProductType {
    fileprivate init(v3 description: String) throws {
        switch description {
        case "test":
            self = .test
        case "exe":
            self = .executable
        case "a":
            self = .library(.static)
        case "dylib":
            self = .library(.dynamic)
        default:
            fatalError("unexpected product type: \(description)")
        }
    }
}

extension ProductDescription {
    fileprivate init(v3 json: JSON) throws {
        try self.init(
            name: json.get("name"),
            type: .init(v3: json.get("type")),
            targets: json.get("modules")
        )
    }
}
