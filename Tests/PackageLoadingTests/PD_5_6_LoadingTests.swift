/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageModel
import XCTest

class PackageDescription5_6LoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v5_6
    }

    func testSourceControlDependencies() throws {
        let manifest = """
            import PackageDescription
            let package = Package(
               name: "MyPackage",
               dependencies: [
                    // from
                   .package(name: "foo1", url: "http://localhost/foo1", from: "1.1.1"),
                   .package(url: "http://localhost/foo2", from: "1.1.1"),
                    // upToNextMajor
                   .package(name: "bar1", url: "http://localhost/bar1", .upToNextMajor(from: "1.1.1")),
                   .package(url: "http://localhost/bar2", .upToNextMajor(from: "1.1.1")),
                    // upToNextMinor
                   .package(name: "baz1", url: "http://localhost/baz1", .upToNextMinor(from: "1.1.1")),
                   .package(url: "http://localhost/baz2", .upToNextMinor(from: "1.1.1")),
                    // exact
                   .package(name: "qux1", url: "http://localhost/qux1", .exact("1.1.1")),
                   .package(url: "http://localhost/qux2", .exact("1.1.1")),
                   .package(url: "http://localhost/qux3", exact: "1.1.1"),
                    // branch
                   .package(name: "quux1", url: "http://localhost/quux1", .branch("main")),
                   .package(url: "http://localhost/quux2", .branch("main")),
                   .package(url: "http://localhost/quux3", branch: "main"),
                    // revision
                   .package(name: "quuz1", url: "http://localhost/quuz1", .revision("abcdefg")),
                   .package(url: "http://localhost/quuz2", .revision("abcdefg")),
                   .package(url: "http://localhost/quuz3", revision: "abcdefg"),
               ]
            )
            """
        loadManifest(manifest, toolsVersion: self.toolsVersion) { manifest in
        let deps = Dictionary(uniqueKeysWithValues: manifest.dependencies.map{ ($0.identity.description, $0) })
            XCTAssertEqual(deps["foo1"], .sourceControl(identity: .plain("foo1"), name: "foo1", location: "http://localhost/foo1", requirement: .range("1.1.1" ..< "2.0.0")))
            XCTAssertEqual(deps["foo2"], .sourceControl(identity: .plain("foo2"), name: nil, location: "http://localhost/foo2", requirement: .range("1.1.1" ..< "2.0.0")))
            XCTAssertEqual(deps["bar1"], .sourceControl(identity: .plain("bar1"), name: "bar1", location: "http://localhost/bar1", requirement: .range("1.1.1" ..< "2.0.0")))
            XCTAssertEqual(deps["bar2"], .sourceControl(identity: .plain("bar2"), name: nil, location: "http://localhost/bar2", requirement: .range("1.1.1" ..< "2.0.0")))
            XCTAssertEqual(deps["baz1"], .sourceControl(identity: .plain("baz1"), name: "baz1", location: "http://localhost/baz1", requirement: .range("1.1.1" ..< "1.2.0")))
            XCTAssertEqual(deps["baz2"], .sourceControl(identity: .plain("baz2"), name: nil, location: "http://localhost/baz2", requirement: .range("1.1.1" ..< "1.2.0")))
            XCTAssertEqual(deps["qux1"], .sourceControl(identity: .plain("qux1"), name: "qux1", location: "http://localhost/qux1", requirement: .exact("1.1.1")))
            XCTAssertEqual(deps["qux2"], .sourceControl(identity: .plain("qux2"), name: nil, location: "http://localhost/qux2", requirement: .exact("1.1.1")))
            XCTAssertEqual(deps["qux3"], .sourceControl(identity: .plain("qux3"), name: nil, location: "http://localhost/qux3", requirement: .exact("1.1.1")))
            XCTAssertEqual(deps["quux1"], .sourceControl(identity: .plain("quux1"), name: "quux1", location: "http://localhost/quux1", requirement: .branch("main")))
            XCTAssertEqual(deps["quux2"], .sourceControl(identity: .plain("quux2"), name: nil, location: "http://localhost/quux2", requirement: .branch("main")))
            XCTAssertEqual(deps["quux3"], .sourceControl(identity: .plain("quux3"), name: nil, location: "http://localhost/quux3", requirement: .branch("main")))
            XCTAssertEqual(deps["quuz1"], .sourceControl(identity: .plain("quuz1"), name: "quuz1", location: "http://localhost/quuz1", requirement: .revision("abcdefg")))
            XCTAssertEqual(deps["quuz2"], .sourceControl(identity: .plain("quuz2"), name: nil, location: "http://localhost/quuz2", requirement: .revision("abcdefg")))
            XCTAssertEqual(deps["quuz3"], .sourceControl(identity: .plain("quuz3"), name: nil, location: "http://localhost/quuz3", requirement: .revision("abcdefg")))
        }
    }

}
