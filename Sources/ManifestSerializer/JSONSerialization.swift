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
    
    #if os(Linux)
        let options: NSJSONWritingOptions = .PrettyPrinted
    #else
        let options: NSJSONWritingOptions = .prettyPrinted
    #endif
    
    let json: AnyObject = package.toJSON()
    let data = try NSJSONSerialization.data(withJSONObject: json, options: options)
    guard let string = String(data: data, encoding: NSUTF8StringEncoding) else { fatalError("NSJSONSerialization emitted invalid data") }
    return string
}

extension NSMutableDictionary {
    static func withNew(block: @noescape (dict: NSMutableDictionary) -> ()) -> NSMutableDictionary {
        let dict = NSMutableDictionary()
        block(dict: dict)
        return dict
    }
}

extension String {
    public func asNS() -> NSString {
        #if os(Linux)
            return self.bridge()
        #else
            return self as NSString
        #endif
    }
}

extension SystemPackageProvider: JSONSerializable {
    public func toJSON() -> AnyObject {
        let (name, value) = nameValue
        
        return NSMutableDictionary.withNew { (dict) in
            dict[name.asNS()] = value.asNS()
        }
    }
}

extension Package.Dependency: JSONSerializable {
    public func toJSON() -> AnyObject {
        
        let version: NSDictionary = [
            "lowerBound": versionRange.lowerBound.description.asNS(),
            "upperBound": versionRange.upperBound.description.asNS()
        ]
        
        return NSMutableDictionary.withNew { (dict) in
            dict["url"] = url.asNS()
            dict["version"] = version
        }
    }
}

extension Package: JSONSerializable {
    public func toJSON() -> AnyObject {
        
        return NSMutableDictionary.withNew { (dict) in
            if let name = self.name {
                dict["name"] = name.asNS()
            }
            if let pkgConfig = self.pkgConfig {
                dict["pkgConfig"] = pkgConfig.asNS()
            }
            dict["dependencies"] = dependencies.map { $0.toJSON() } as NSArray
            dict["testDependencies"] = testDependencies.map { $0.toJSON() } as NSArray
            dict["exclude"] = exclude as NSArray
            dict["package.targets"] = targets.map { $0.toJSON() } as NSArray
            if let providers = self.providers {
                dict["package.providers"] = providers.map { $0.toJSON() } as NSArray
            }
        }
    }
}

extension Target.Dependency: JSONSerializable {
    public func toJSON() -> AnyObject {
        switch self {
        case .Target(let name):
            return name.asNS()
        }
    }
}

extension Target: JSONSerializable {
    public func toJSON() -> AnyObject {
        
        let deps = dependencies.map { $0.toJSON() } as NSArray
        return NSMutableDictionary.withNew { (dict) in
            dict["name"] = name.asNS()
            dict["dependencies"] = deps
        }
    }
}
