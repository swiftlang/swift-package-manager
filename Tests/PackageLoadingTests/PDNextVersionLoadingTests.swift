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

    func testPrebuildExtensionTarget() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               targets: [
                   .extension(
                       name: "Foo",
                       capability: .prebuild()
                    ),
               ]
            )
            """

        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.targets[0].type, .extension)
            XCTAssertEqual(manifest.targets[0].extensionCapability, .prebuild)
        }
    }

    func testBuildToolExtensionTarget() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               targets: [
                   .extension(
                       name: "Foo",
                       capability: .buildTool()
                    ),
               ]
            )
            """

        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.targets[0].type, .extension)
            XCTAssertEqual(manifest.targets[0].extensionCapability, .buildTool)
        }
    }

    func testPostbuildExtensionTarget() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               targets: [
                   .extension(
                       name: "Foo",
                       capability: .postbuild()
                    ),
               ]
            )
            """

        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.targets[0].type, .extension)
            XCTAssertEqual(manifest.targets[0].extensionCapability, .postbuild)
        }
    }
}
