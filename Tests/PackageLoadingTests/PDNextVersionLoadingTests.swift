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

class PackageDescriptionNextVersionLoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .vNext
    }

    func testPrebuildPluginTarget() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               targets: [
                   .plugin(
                       name: "Foo",
                       capability: .prebuild()
                    )
               ]
            )
            """

        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.targets[0].type, .plugin)
            XCTAssertEqual(manifest.targets[0].pluginCapability, .prebuild)
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

    func testPostbuildPluginTarget() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               targets: [
                   .plugin(
                       name: "Foo",
                       capability: .postbuild()
                    )
               ]
            )
            """

        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.targets[0].type, .plugin)
            XCTAssertEqual(manifest.targets[0].pluginCapability, .postbuild)
        }
    }
}
