/*
 This source file is part of the Swift.org open source project
 
 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageDescription
import Basic

/// A JSON representation of an element.
protocol JSONSerializable {
    
    /// Return a JSON representation.
    func toJSON() -> JSON
}

public func jsonString(package: PackageDescription.Package) throws -> String {

    let json = package.toJSON()
    guard let string = json.toBytes().asString else {
        fatalError("Failed to serialize JSON \(json)")
    }
    return string
}

extension SystemPackageProvider: JSONSerializable {
    func toJSON() -> JSON {
        let (name, value) = nameValue
        return .dictionary([name: .string(value)])
    }
}

extension Package.Dependency: JSONSerializable {
    func toJSON() -> JSON {
        return .dictionary([
            "url": .string(url),
            "version": .dictionary([
                "lowerBound": .string(versionRange.lowerBound.description),
                "upperBound": .string(versionRange.upperBound.description)
            ])
        ])
    }
}

extension Package: JSONSerializable {
    func toJSON() -> JSON {
        var dict: [String: JSON] = [:]
        if let name = self.name {
            dict["name"] = .string(name)
        }
        if let pkgConfig = self.pkgConfig {
            dict["pkgConfig"] = .string(pkgConfig)
        }
        dict["dependencies"] = .array(dependencies.map { $0.toJSON() })
        dict["testDependencies"] = .array(testDependencies.map { $0.toJSON() })
        dict["exclude"] = .array(exclude.map { .string($0) })
        dict["package.targets"] = .array(targets.map { $0.toJSON() })
        if let providers = self.providers {
            dict["package.providers"] = .array(providers.map { $0.toJSON() })
        }
        return .dictionary(dict)
    }
}

extension Target.Dependency: JSONSerializable {
    func toJSON() -> JSON {
        switch self {
        case .Target(let name):
            return .string(name)
        }
    }
}

extension Target: JSONSerializable {
    func toJSON() -> JSON {
        return .dictionary([
            "name": .string(name),
            "dependencies": .array(dependencies.map { $0.toJSON() })
        ])
    }
}
