/*
 This source file is part of the Swift.org open source project
 
 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import PackageDescription

/// A JSON representation of an element.
public protocol JSONSerializable {
    
    /// Return a JSON representation.
    func toJSON() -> AnyObject
}

public func jsonString(package: PackageDescription.Package) throws -> String {
    
    let json: AnyObject = package.toJSON()
    let data = try NSJSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
    guard let string = String(data: data, encoding: NSUTF8StringEncoding) else { fatalError() }
    return string
}

extension NSMutableDictionary {
    public static func withNew(block: @noescape (dict: NSMutableDictionary) -> ()) -> NSMutableDictionary {
        let dict = NSMutableDictionary()
        block(dict: dict)
        return dict
    }
}

extension SystemPackageProvider: JSONSerializable {
    public func toJSON() -> AnyObject {
        let (name, value) = nameValue
        
        return NSMutableDictionary.withNew { (dict) in
            dict[name] = value
        }
    }
}

extension Package.Dependency: JSONSerializable {
    public func toJSON() -> AnyObject {
        
        let version: NSDictionary = [
            "lowerBound": versionRange.lowerBound.description,
            "upperBound": versionRange.upperBound.description
        ]
        
        return NSMutableDictionary.withNew { (dict) in
            dict["url"] = url
            dict["version"] = version
        }
    }
}

extension Package: JSONSerializable {
    public func toJSON() -> AnyObject {
        
        return NSMutableDictionary.withNew { (dict) in
            if let name = self.name {
                dict["name"] = name
            }
            if let pkgConfig = self.pkgConfig {
                dict["pkgConfig"] = pkgConfig
            }
            dict["dependencies"] = dependencies.map { $0.toJSON() }
            dict["testDependencies"] = testDependencies.map { $0.toJSON() }
            dict["exclude"] = exclude
            dict["package.targets"] = targets.map { $0.toJSON() }
            if let providers = self.providers {
                dict["package.providers"] = providers.map { $0.toJSON() }
            }
        }
    }
}

extension Target.Dependency: JSONSerializable {
    public func toJSON() -> AnyObject {
        switch self {
        case .Target(let name):
            return name
        }
    }
}

extension Target: JSONSerializable {
    public func toJSON() -> AnyObject {
        
        let deps: NSArray = dependencies.map { $0.toJSON() }
        return NSMutableDictionary.withNew { (dict) in
            dict["name"] = name
            dict["dependencies"] = deps
        }
    }
}
