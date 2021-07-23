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
                   .package(identity: "foo", branch: "main"),
                   .package(identity: "bar", revision: "58e9de4e7b79e67c72a46e164158e3542e570ab6"),
                   .package(identity: "baz", from: "1.1.1"),
                   .package(identity: "qux", .exact("1.1.1")),
               ]
            )
            """
        loadManifest(manifest, toolsVersion: self.toolsVersion) { manifest in
        let deps = Dictionary(uniqueKeysWithValues: manifest.dependencies.map{ ($0.identity.description, $0) })
            XCTAssertEqual(deps["foo"], .registry(identity: "foo", requirement: .branch("main")))
            XCTAssertEqual(deps["bar"], .registry(identity: "bar", requirement: .revision("58e9de4e7b79e67c72a46e164158e3542e570ab6")))
            XCTAssertEqual(deps["baz"], .registry(identity: "baz", requirement: .range("1.1.1" ..< "2.0.0")))
            XCTAssertEqual(deps["qux"], .registry(identity: "qux", requirement: .exact("1.1.1")))
        }
    }
}
