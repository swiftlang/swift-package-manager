/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import TSCUtility
import SPMTestSupport
import PackageModel
import PackageLoading

class PackageDescription5_5LoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v5_5
    }

    func testPackageDependencies() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               dependencies: [
                   .package(url: "/foo5", branch: "main"),
                   .package(url: "/foo7", revision: "58e9de4e7b79e67c72a46e164158e3542e570ab6"),
               ]
            )
            """
        loadManifest(stream.bytes, toolsVersion: .v5_5) { manifest in
        let deps = Dictionary(uniqueKeysWithValues: manifest.dependencies.map{ ($0.identity.description, $0) })
            XCTAssertEqual(deps["foo5"], .scm(location: "/foo5", requirement: .branch("main")))
            XCTAssertEqual(deps["foo7"], .scm(location: "/foo7", requirement: .revision("58e9de4e7b79e67c72a46e164158e3542e570ab6")))
        }
    }

    func testBuildToolPluginTarget() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               targets: [
                   .plugin(
                       name: "Foo",
                       capability: .buildTool()
                    )
               ]
            )
            """

        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.targets[0].type, .plugin)
            XCTAssertEqual(manifest.targets[0].pluginCapability, .buildTool)
        }
    }

    func testPluginPluginTargetCustomization() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               targets: [
                   .plugin(
                       name: "Foo",
                       capability: .buildTool(),
                       path: "Sources/Foo",
                       exclude: ["IAmOut.swift"],
                       sources: ["CountMeIn.swift"]
                    )
               ]
            )
            """

        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.targets[0].type, .plugin)
            XCTAssertEqual(manifest.targets[0].pluginCapability, .buildTool)
            XCTAssertEqual(manifest.targets[0].path, "Sources/Foo")
            XCTAssertEqual(manifest.targets[0].exclude, ["IAmOut.swift"])
            XCTAssertEqual(manifest.targets[0].sources, ["CountMeIn.swift"])
        }
    }
}
