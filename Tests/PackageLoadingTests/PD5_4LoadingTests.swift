/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 - 2021 Apple Inc. and the Swift project authors
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

class PackageDescription5_4LoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v5_4
    }

    func testExecutableTargets() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               targets: [
                   .executableTarget(
                       name: "Foo"
                    ),
               ]
            )
            """

        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.targets[0].type, .executable)
        }
    }
    
    func testPluginsAreUnavailable() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               targets: [
                   .plugin(
                       name: "Foo",
                       capability: .buildTool()
                   ),
               ]
            )
            """
        do {
            try loadManifestThrowing(stream.bytes) { _ in }
            XCTFail("expected manifest loading to fail, but it succeeded")
        }
        catch {
            guard case let ManifestParseError.invalidManifestFormat(message, _) = error else {
                return XCTFail("expected an invalidManifestFormat error, but got: \(error)")
            }

            XCTAssertMatch(message, .contains("is unavailable"))
            XCTAssertMatch(message, .contains("was introduced in PackageDescription 999"))
        }
    }
}
