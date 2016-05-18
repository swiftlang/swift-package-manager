/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import XCTest

import PackageDescription

@testable import PackageLoading

class JSONSerializationTests: XCTestCase {
    
    func testSimple() {
        let package = Package(name: "Simple")
        let exp = NSMutableDictionary.withNew { (dict) in
            dict.set(object: "Simple".asNS(), forKey: "name")
            dict.fillWithEmptyArrays(keyNames: ["dependencies", "testDependencies", "exclude", "package.targets"])
        }
        assertEqual(package: package, expected: exp)
    }
    
    func testDependencies() {
        let deps: [Package.Dependency] =
            [
                .Package(url: "https://github.com/apple/swift.git", majorVersion: 3),
                .Package(url: "https://github.com/apple/llvm.git", majorVersion: 2)
        ]
        let package = Package(name: "WithDeps", pkgConfig: nil, providers: nil, targets: [], dependencies: deps, testDependencies: [], exclude: [])
        let exp = NSMutableDictionary.withNew { (dict) in
            dict.set(object: "WithDeps".asNS(), forKey: "name")
            let dep1version: NSDictionary = [
                "lowerBound".asNS():"3.0.0".asNS(),
                "upperBound".asNS():"3.9223372036854775807.9223372036854775807".asNS()
            ]
            let dep1: NSDictionary = [
                "url".asNS(): "https://github.com/apple/swift.git".asNS(),
                "version".asNS(): dep1version
            ]
            let dep2version: NSDictionary = [
                "lowerBound".asNS():"2.0.0".asNS(),
                "upperBound".asNS():"2.9223372036854775807.9223372036854775807".asNS()
            ]
            let dep2: NSDictionary = [
                "url".asNS(): "https://github.com/apple/llvm.git".asNS(),
                "version".asNS(): dep2version
            ]
            dict["dependencies".asNS()] = [dep1, dep2].asNS()
            dict.fillWithEmptyArrays(keyNames: ["testDependencies", "exclude", "package.targets"])
        }
        assertEqual(package: package, expected: exp)
    }
    
    func testPkgConfig() {
        let providers: [SystemPackageProvider] = [
                            .Brew("BrewPackage"),
                            .Apt("AptPackage")
                            ]
        let package = Package(name: "PkgPackage", pkgConfig: "PkgPackage-1.0", providers: providers)
        let exp = NSMutableDictionary.withNew { (dict) in
            dict.set(object: "PkgPackage".asNS(), forKey: "name")
            dict.set(object: "PkgPackage-1.0".asNS(), forKey: "pkgConfig")
            let providers: [AnyObject] = [
                ["Brew".asNS() : "BrewPackage".asNS()] as NSDictionary,
                ["Apt".asNS() : "AptPackage".asNS()] as NSDictionary
            ]
            dict.set(object: providers.asNS(), forKey: "package.providers") 
            dict.fillWithEmptyArrays(keyNames: ["dependencies", "testDependencies", "exclude", "package.targets"])
        }
        assertEqual(package: package, expected: exp)
    }
    
    func testExclude() {
        let package = Package(name: "Exclude", exclude: ["pikachu", "bulbasaur"])
        let exp = NSMutableDictionary.withNew { (dict) in
            dict.set(object: "Exclude".asNS(), forKey: "name")
            dict.set(object: ["pikachu".asNS(), "bulbasaur".asNS()].asNS(), forKey: "exclude") 
            dict.fillWithEmptyArrays(keyNames: ["dependencies", "testDependencies", "package.targets"])
        }
        assertEqual(package: package, expected: exp)
    }
    
    func testTargets() {
        let t1 = Target(name: "One")
        let t2 = Target(name: "Two", dependencies: [.Target(name: "One")])
        let package = Package(name: "Targets", targets: [t1, t2])
        let exp = NSMutableDictionary.withNew { (dict) in
            dict.set(object: "Targets".asNS(), forKey: "name")
            let ts1 = ["name".asNS(): "One".asNS(), "dependencies": NSArray()] as NSDictionary
            let ts2 = ["name".asNS(): "Two".asNS(), "dependencies": ["One"].asNS()] as NSDictionary
            dict.set(object: [ts1, ts2].asNS(), forKey: "package.targets")
            dict.fillWithEmptyArrays(keyNames: ["dependencies", "testDependencies", "exclude", ])
        }
        assertEqual(package: package, expected: exp)
    }
}

extension NSMutableDictionary {
    
    func fillWithEmptyArrays(keyNames: [String]) {
        keyNames.forEach {
            self[$0.asNS()] = NSArray()
        }
    }
}

extension JSONSerializationTests {
    
    func assertEqual(package: Package, expected: NSMutableDictionary) {
        let json = package.toJSON() as! NSMutableDictionary
        XCTAssertEqual(json, expected)
    }
}

extension JSONSerializationTests {
    static var allTests : [(String, (JSONSerializationTests) -> () throws -> Void)] {
        return [
            ("testSimple", testSimple),
            ("testDependencies", testDependencies),
            ("testPkgConfig", testPkgConfig),
            ("testExclude", testExclude),
            ("testTargets", testTargets),
        ]
    }
}
