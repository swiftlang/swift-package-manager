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
        assertEqual(package: package, expected: "{\"dependencies\": [], \"exclude\": [], \"name\": \"Simple\", \"package.targets\": [], \"testDependencies\": []}")
    }
    
    func testDependencies() {
        let deps: [Package.Dependency] =
            [
                .Package(url: "https://github.com/apple/swift.git", majorVersion: 3),
                .Package(url: "https://github.com/apple/llvm.git", majorVersion: 2)
        ]
        let package = Package(name: "WithDeps", pkgConfig: nil, providers: nil, targets: [], dependencies: deps, testDependencies: [], exclude: [])
        assertEqual(package: package, expected: "{\"dependencies\": [{\"url\": \"https://github.com/apple/swift.git\", \"version\": {\"lowerBound\": \"3.0.0\", \"upperBound\": \"3.9223372036854775807.9223372036854775807\"}}, {\"url\": \"https://github.com/apple/llvm.git\", \"version\": {\"lowerBound\": \"2.0.0\", \"upperBound\": \"2.9223372036854775807.9223372036854775807\"}}], \"exclude\": [], \"name\": \"WithDeps\", \"package.targets\": [], \"testDependencies\": []}")
    }

    func testPkgConfig() {
        let providers: [SystemPackageProvider] = [
                            .Brew("BrewPackage"),
                            .Apt("AptPackage")
                            ]
        let package = Package(name: "PkgPackage", pkgConfig: "PkgPackage-1.0", providers: providers)
        assertEqual(package: package, expected: "{\"dependencies\": [], \"exclude\": [], \"name\": \"PkgPackage\", \"package.providers\": [{\"Brew\": \"BrewPackage\"}, {\"Apt\": \"AptPackage\"}], \"package.targets\": [], \"pkgConfig\": \"PkgPackage-1.0\", \"testDependencies\": []}")
    }

    func testExclude() {
        let package = Package(name: "Exclude", exclude: ["pikachu", "bulbasaur"])
        assertEqual(package: package, expected: "{\"dependencies\": [], \"exclude\": [\"pikachu\", \"bulbasaur\"], \"name\": \"Exclude\", \"package.targets\": [], \"testDependencies\": []}")
    }
    
    func testTargets() {
        let t1 = Target(name: "One")
        let t2 = Target(name: "Two", dependencies: [.Target(name: "One")])
        let package = Package(name: "Targets", targets: [t1, t2])
        assertEqual(package: package, expected: "{\"dependencies\": [], \"exclude\": [], \"name\": \"Targets\", \"package.targets\": [{\"dependencies\": [], \"name\": \"One\"}, {\"dependencies\": [\"One\"], \"name\": \"Two\"}], \"testDependencies\": []}")
    }
}

extension JSONSerializationTests {
    
    func assertEqual(package: Package, expected: String) {
        let json = package.toJSON().toString()
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
