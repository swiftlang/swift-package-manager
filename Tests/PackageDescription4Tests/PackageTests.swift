/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import PackageDescription4
import XCTest

class PackageTests: XCTestCase {

    func testBasics() {
        let package = Package(
            name: "Foo",
            products: [
                .library(name: "foo", targets: ["foo"]),
                .library(name: "bar", type: .dynamic, targets: ["bar"]),
                .executable(name: "exec", targets: ["exe"]),
            ],
            dependencies: [
                .package(url: "/dep1", from: "1.0.0"),
                .package(url: "/dep2", .exact("1.0.0")),
                .package(url: "/dep3", "1.0.0"..."2.1.1"),
                .package(url: "/dep4", .revision("ref")),
                .package(url: "/dep5", .branch("master")),
            ],
            targets: [
                .target(name: "foo", dependencies: [
                    .byName(name: "dep1"),
                    .product(name: "dep2"),
                    .target(name: "bar"),
                ]),
                .target(name: "bar"),
                .testTarget(name: "allTests", dependencies: ["foo", "bar"]),
            ],
            swiftLanguageVersions: [3, 4],
            cLanguageStandard: .c99,
            cxxLanguageStandard: .cxx14
        )
        XCTAssertEqual(package.toJSON().toString(), """
            {"cLanguageStandard": "c99", "cxxLanguageStandard": "c++14", "dependencies": [{"requirement": {"lowerBound": "1.0.0", "type": "range", "upperBound": "2.0.0"}, "url": "/dep1"}, {"requirement": {"identifier": "1.0.0", "type": "exact"}, "url": "/dep2"}, {"requirement": {"lowerBound": "1.0.0", "type": "range", "upperBound": "2.1.2"}, "url": "/dep3"}, {"requirement": {"identifier": "ref", "type": "revision"}, "url": "/dep4"}, {"requirement": {"identifier": "master", "type": "branch"}, "url": "/dep5"}], "name": "Foo", "products": [{"name": "foo", "product_type": "library", "targets": ["foo"], "type": null}, {"name": "bar", "product_type": "library", "targets": ["bar"], "type": "dynamic"}, {"name": "exec", "product_type": "executable", "targets": ["exe"]}], "swiftLanguageVersions": [3, 4], "targets": [{"dependencies": [{"name": "dep1", "type": "byname"}, {"name": "dep2", "package": null, "type": "product"}, {"name": "bar", "type": "target"}], "exclude": [], "isTest": false, "name": "foo", "path": null, "publicHeadersPath": null, "sources": null}, {"dependencies": [], "exclude": [], "isTest": false, "name": "bar", "path": null, "publicHeadersPath": null, "sources": null}, {"dependencies": [{"name": "foo", "type": "byname"}, {"name": "bar", "type": "byname"}], "exclude": [], "isTest": true, "name": "allTests", "path": null, "publicHeadersPath": null, "sources": null}]}
            """)
    }

    func testSystemPkg() {
        let package = Package(
            name: "Foo",
            pkgConfig: "foo",
            providers: [
                .brew(["foo"]),
                .apt(["bar"]),
            ]
        )
        XCTAssertEqual(package.toJSON().toString(), """
            {"cLanguageStandard": null, "cxxLanguageStandard": null, "dependencies": [], "name": "Foo", "pkgConfig": "foo", "products": [], "providers": [{"name": "brew", "values": ["foo"]}, {"name": "apt", "values": ["bar"]}], "targets": []}
            """)
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testSystemPkg", testSystemPkg),
    ]
}

