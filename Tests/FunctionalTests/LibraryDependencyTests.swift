//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import _InternalTestSupport
import XCTest

final class LibraryDependencyTests: XCTestCase {
    func testClientPackage() async throws {
        #if os(macOS) || os(Linux)
        #else
        try XCTSkipIf(true, "This test requires macOS or Linux")
        #endif

        try await fixture(name: "LibraryDependencies/KrabbyPatty") { fixturePath in

            let scratchPath = fixturePath.appending(component: ".build.tests")
            try await executeSwiftBuild(fixturePath,
                configuration: .debug,
                extraArgs: ["--scratch-path", scratchPath.pathString]
            )

            let artifactbundlePath = scratchPath.appending(component: "main.artifactbundle")
            let artifactsPath = artifactbundlePath.appending(component: "KrabbyPatty")

            #if os(macOS)
            let libraryExtension = "dylib"
            #else
            let libraryExtension = "so"
            #endif

            let libraryName = "libKrabbyPatty.\(libraryExtension)"

            try localFileSystem.createDirectory(artifactsPath, recursive: true)
            try localFileSystem.move(
                from: scratchPath.appending(
                    components: "debug", "Modules", "KrabbyPatty.swiftinterface"
                ),
                to: artifactsPath.appending(component: "KrabbyPatty.swiftinterface")
            )
            try localFileSystem.move(
                from: scratchPath.appending(components: "debug", libraryName),
                to: artifactsPath.appending(component: libraryName)
            )

            try localFileSystem.writeFileContents(
                artifactbundlePath.appending(component: "info.json"),
                string: """
                {
                    "schemaVersion": "1.2",
                    "artifacts": {
                        "KrabbyPatty": {
                            "type": "dynamicLibrary",
                            "version": "0.0.0",
                            "variants": [{ "path": "KrabbyPatty" }]
                        }
                    }
                }
                """
            )

            try await fixture(name: "LibraryDependencies/KrustyKrab") { fixturePath in

                try localFileSystem.copy(
                    from: artifactbundlePath,
                    to: fixturePath.appending(component: "main.artifactbundle")
                )

                let (output, _) = try await executeSwiftRun(fixturePath, "KrustyKrab", buildSystem: .native)
                XCTAssertTrue(
                    output.contains("Latest Krabby Patty formula version: v2"),
                    output
                )
            }
        }
    }
}
