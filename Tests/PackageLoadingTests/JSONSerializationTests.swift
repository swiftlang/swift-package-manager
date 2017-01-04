/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import XCTest

@testable import PackageDescription

@testable import PackageLoading

class JSONSerializationTests: XCTestCase {
    func assertEqual(package: Package, expected: String, file: StaticString = #file, line: UInt = #line) {
        let json = package.toJSON().toString()
        XCTAssertEqual(json, expected, file: file, line: line)
    }

    func testSimple() {
        let package = Package(name: "Simple")
        assertEqual(package: package, expected: "{\"dependencies\": [], \"exclude\": [], \"name\": \"Simple\", \"products\": [], \"targets\": []}")
    }
    
    func testDependencies() {
        let deps: [Package.Dependency] =
            [
                .Package(url: "https://github.com/apple/swift.git", majorVersion: 3),
                .Package(url: "https://github.com/apple/llvm.git", majorVersion: 2)
        ]
        let package = Package(name: "WithDeps", pkgConfig: nil, providers: nil, targets: [], dependencies: deps, exclude: [])
        assertEqual(package: package, expected: "{\"dependencies\": [{\"url\": \"https://github.com/apple/swift.git\", \"version\": {\"lowerBound\": \"3.0.0\", \"upperBound\": \"3.9223372036854775807.9223372036854775807\"}}, {\"url\": \"https://github.com/apple/llvm.git\", \"version\": {\"lowerBound\": \"2.0.0\", \"upperBound\": \"2.9223372036854775807.9223372036854775807\"}}], \"exclude\": [], \"name\": \"WithDeps\", \"products\": [], \"targets\": []}")
    }

    func testPkgConfig() {
        let providers: [SystemPackageProvider] = [
                            .Brew("BrewPackage"),
                            .Apt("AptPackage")
                            ]
        let package = Package(name: "PkgPackage", pkgConfig: "PkgPackage-1.0", providers: providers)
        assertEqual(package: package, expected: "{\"dependencies\": [], \"exclude\": [], \"name\": \"PkgPackage\", \"pkgConfig\": \"PkgPackage-1.0\", \"products\": [], \"providers\": [{\"name\": \"Brew\", \"value\": \"BrewPackage\"}, {\"name\": \"Apt\", \"value\": \"AptPackage\"}], \"targets\": []}")
    }

    func testExclude() {
        let package = Package(name: "Exclude", exclude: ["pikachu", "bulbasaur"])
        assertEqual(package: package, expected: "{\"dependencies\": [], \"exclude\": [\"pikachu\", \"bulbasaur\"], \"name\": \"Exclude\", \"products\": [], \"targets\": []}")
    }
    
    func testTargets() {
        let t1 = Target(name: "One")
        let t2 = Target(name: "Two", dependencies: [.Target(name: "One")])
        let package = Package(name: "Targets", targets: [t1, t2])
        assertEqual(package: package, expected: "{\"dependencies\": [], \"exclude\": [], \"name\": \"Targets\", \"products\": [], \"targets\": [{\"dependencies\": [], \"name\": \"One\"}, {\"dependencies\": [\"One\"], \"name\": \"Two\"}]}")
    }
    
    func testProducts() {
        var product: PackageDescription.Product

        product = .Executable(name: "exe", targets: ["foo", "bar"])
        XCTAssertEqual(product.toJSON().toString(), "{\"name\": \"exe\", \"product_type\": \"exe\", \"targets\": [\"foo\", \"bar\"]}")

        product = .Library(name: "lib", targets: ["foo", "bar"])
        XCTAssertEqual(product.toJSON().toString(), "{\"name\": \"lib\", \"product_type\": \"lib\", \"targets\": [\"foo\", \"bar\"], \"type\": null}")

        product = .Library(name: "lib", type: .static, targets: ["foo", "bar"])
        XCTAssertEqual(product.toJSON().toString(), "{\"name\": \"lib\", \"product_type\": \"lib\", \"targets\": [\"foo\", \"bar\"], \"type\": \"static\"}")

        product = .Library(name: "lib", type: .dynamic, targets: ["foo", "bar"])
        XCTAssertEqual(product.toJSON().toString(), "{\"name\": \"lib\", \"product_type\": \"lib\", \"targets\": [\"foo\", \"bar\"], \"type\": \"dynamic\"}")
    }

    static var allTests = [
        ("testSimple", testSimple),
        ("testDependencies", testDependencies),
        ("testPkgConfig", testPkgConfig),
        ("testExclude", testExclude),
        ("testTargets", testTargets),
        ("testProducts", testProducts),
    ]
}
