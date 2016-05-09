/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import ManifestSerializer
import PackageDescription
import XCTest

class JSONSerializationTests: XCTestCase {
    
    func testSimple() {
        let package = Package(name: "Simple")
        let exp = NSMutableDictionary.withNew { (dict) in
            dict["name"] = "Simple"
            fillWithEmptyArrays(keyNames: ["dependencies", "testDependencies", "exclude", "package.targets"], dict: dict)
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
            dict["name"] = "WithDeps"
            let dep1 = [
                           "url": "https://github.com/apple/swift.git",
                           "version": [
                                          "lowerBound":"3.0.0",
                                          "upperBound":"3.9223372036854775807.9223372036854775807"
                ]
            ] as NSDictionary
            let dep2 = [
                           "url": "https://github.com/apple/llvm.git",
                           "version": [
                                          "lowerBound":"2.0.0",
                                          "upperBound":"2.9223372036854775807.9223372036854775807"
                ]
            ] as NSDictionary
            dict["dependencies"] = [dep1, dep2] as NSArray
            fillWithEmptyArrays(keyNames: ["testDependencies", "exclude", "package.targets"], dict: dict)
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
            dict["name"] = "PkgPackage"
            dict["pkgConfig"] = "PkgPackage-1.0"
            dict["package.providers"] = [
                ["Brew": "BrewPackage"],
                ["Apt": "AptPackage"]
            ]
            fillWithEmptyArrays(keyNames: ["dependencies", "testDependencies", "exclude", "package.targets"], dict: dict)
        }
        assertEqual(package: package, expected: exp)
    }
    
    func testExclude() {
        let package = Package(name: "Exclude", exclude: ["pikachu", "bulbasaur"])
        let exp = NSMutableDictionary.withNew { (dict) in
            dict["name"] = "Exclude"
            dict["exclude"] = ["pikachu", "bulbasaur"]
            fillWithEmptyArrays(keyNames: ["dependencies", "testDependencies", "package.targets"], dict: dict)
        }
        assertEqual(package: package, expected: exp)
    }
    
    func testTargets() {
        let t1 = Target(name: "One")
        let t2 = Target(name: "Two", dependencies: [.Target(name: "One")])
        let package = Package(name: "Targets", targets: [t1, t2])
        let exp = NSMutableDictionary.withNew { (dict) in
            dict["name"] = "Targets"
            let ts1 = ["name": "One", "dependencies": NSArray()] as NSDictionary
            let ts2 = ["name": "Two", "dependencies": ["One"] as NSArray] as NSDictionary
            dict["package.targets"] = [ts1, ts2] as NSArray
            fillWithEmptyArrays(keyNames: ["dependencies", "testDependencies", "exclude", ], dict: dict)
        }
        assertEqual(package: package, expected: exp)
    }
}

extension JSONSerializationTests {
    
    func fillWithEmptyArrays(keyNames: [String], dict: NSMutableDictionary) {
        keyNames.forEach {
            dict[$0 as NSString] = NSArray()
        }
    }
    
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
