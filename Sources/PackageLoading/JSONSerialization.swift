/*
 This source file is part of the Swift.org open source project
 
 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import PackageDescription

public func jsonString(package: PackageDescription.Package) throws -> String {

    let json = package.json
    let string = json.toString()
    return string
}

extension SystemPackageProvider: JSONConvertible {
    public var json: JSON {
        let (name, value) = nameValue
        return JSON([name: value])
    }
}

extension Package.Dependency: JSONConvertible {
    public var json: JSON {
        return JSON([
            "url": url,
            "version": JSON([
                "lowerBound": versionRange.lowerBound.description,
                "upperBound": versionRange.upperBound.description
            ])
        ])
    }
}

extension Package: JSONConvertible {
    public var json: JSON {
        var dict: [String: JSONConvertible] = [:]
        if let name = self.name {
            dict["name"] = name
        }
        if let pkgConfig = self.pkgConfig {
            dict["pkgConfig"] = pkgConfig
        }
        
        dict["dependencies"] = JSON(dependencies.map { $0.json })
        dict["testDependencies"] = JSON(testDependencies.map { $0.json })
        dict["exclude"] = JSON(exclude.map { $0.json })
        dict["package.targets"] = JSON(targets.map { $0.json })
        if let providers = self.providers {
            dict["package.providers"] = JSON(providers.map { $0.json })
        }
        return JSON(dict)
    }
}

extension Target.Dependency: JSONConvertible {
    public var json: JSON {
        switch self {
        case .Target(let name):
            return name.json
        }
    }
}

extension Target: JSONConvertible {
    public var json: JSON {
        return JSON([
            "name": name,
            "dependencies": JSON(dependencies.map { $0.json })
        ])
    }
}
