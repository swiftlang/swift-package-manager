/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageModel
import XCTest

class PackageDescriptionNextLoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .vNext
    }
    
    func testRegistryDependencies() throws {
        let manifest = """
            import PackageDescription
            let package = Package(
               name: "MyPackage",
               dependencies: [
                   .package(id: "foo", from: "1.1.1"),
                   .package(id: "bar", exact: "1.1.1"),
                   .package(id: "baz", .upToNextMajor(from: "1.1.1")),
                   .package(id: "qux", .upToNextMinor(from: "1.1.1")),
                   .package(id: "quux", "1.1.1" ..< "3.0.0"),
               ]
            )
            """
        loadManifest(manifest, toolsVersion: self.toolsVersion) { manifest in
        let deps = Dictionary(uniqueKeysWithValues: manifest.dependencies.map{ ($0.identity.description, $0) })
            XCTAssertEqual(deps["foo"], .registry(identity: "foo", requirement: .range("1.1.1" ..< "2.0.0")))
            XCTAssertEqual(deps["bar"], .registry(identity: "bar", requirement: .exact("1.1.1")))
            XCTAssertEqual(deps["baz"], .registry(identity: "baz", requirement: .range("1.1.1" ..< "2.0.0")))
            XCTAssertEqual(deps["qux"], .registry(identity: "qux", requirement: .range("1.1.1" ..< "1.2.0")))
            XCTAssertEqual(deps["quux"], .registry(identity: "quux", requirement: .range("1.1.1" ..< "3.0.0")))
        }
    }
}
