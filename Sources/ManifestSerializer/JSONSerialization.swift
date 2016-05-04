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
    
    func set(object: AnyObject, forKey key: String) {
        self[key.asNS()] = object
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

extension Array {
    public func asNS() -> NSArray {
        #if os(Linux)
            return self.bridge()
        #else
            return self.map { $0 as! AnyObject } as NSArray
        #endif
    }
}

extension SystemPackageProvider: JSONSerializable {
    public func toJSON() -> AnyObject {
        let (name, value) = nameValue
        
        return NSMutableDictionary.withNew { (dict) in
            dict.set(object: value.asNS(), forKey: name)
        }
    }
}

extension Package.Dependency: JSONSerializable {
    public func toJSON() -> AnyObject {
        
        let version = NSMutableDictionary.withNew { (dict) in
            dict.set(object: versionRange.lowerBound.description.asNS(), forKey: "lowerBound")
            dict.set(object: versionRange.upperBound.description.asNS(), forKey: "upperBound")
        }
        return NSMutableDictionary.withNew { (dict) in
            dict.set(object: url.asNS(), forKey: "url")
            dict.set(object: version, forKey: "version")
        }
    }
}

extension Package: JSONSerializable {
    public func toJSON() -> AnyObject {
        
        return NSMutableDictionary.withNew { (dict) in
            if let name = self.name {
                dict.set(object: name.asNS(), forKey: "name")
            }
            if let pkgConfig = self.pkgConfig {
                dict.set(object: pkgConfig.asNS(), forKey: "pkgConfig")
            }
            dict.set(object: dependencies.map { $0.toJSON() }.asNS(), forKey: "dependencies")
            dict.set(object: testDependencies.map { $0.toJSON() }.asNS(), forKey: "testDependencies")
            dict.set(object: exclude.asNS(), forKey: "exclude")
            dict.set(object: targets.map { $0.toJSON() }.asNS(), forKey: "package.targets")
            if let providers = self.providers {
                dict.set(object: providers.map { $0.toJSON() }.asNS(), forKey: "package.providers")
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
        
        let deps = dependencies.map { $0.toJSON() }.asNS()
        return NSMutableDictionary.withNew { (dict) in
            dict.set(object: name.asNS(), forKey: "name")
            dict.set(object: deps, forKey: "dependencies")
        }
    }
}
