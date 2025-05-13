//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _InternalTestSupport
import struct Basics.AbsolutePath
import var Basics.localFileSystem
@testable
import Commands
import class PackageModel.UserToolchain
import XCTest

final class FixItCommandTests: CommandsTestCase {
    func testHelp() async throws {
        let stdout = try await SwiftPM.fixit.execute(["-help"]).stdout

        XCTAssert(stdout.contains("USAGE: swift fixit"), stdout)
        XCTAssert(stdout.contains("-h, -help, --help"), stdout)
    }

    func testApplyFixIts() async throws {
        try await fixture(name: "SwiftFixIt/SwiftFixItPackage") { fixturePath in
            let sourcePaths: [AbsolutePath]
            let fixedSourcePaths: [AbsolutePath]
            do {
                let sourcesPath = fixturePath.appending(components: "Sources")
                let fixedSourcesPath = sourcesPath.appending("Fixed")

                sourcePaths = try localFileSystem.getDirectoryContents(sourcesPath).filter { filename in
                    filename.hasSuffix(".swift")
                }.sorted().map { filename in
                    sourcesPath.appending(filename)
                }
                fixedSourcePaths = try localFileSystem.getDirectoryContents(fixedSourcesPath).filter { filename in
                    filename.hasSuffix(".swift")
                }.sorted().map { filename in
                    fixedSourcesPath.appending(filename)
                }
            }

            XCTAssertEqual(sourcePaths.count, fixedSourcePaths.count)

            let targetName = "Diagnostics"

            _ = try? await executeSwiftBuild(fixturePath, extraArgs: ["--target", targetName])

            do {
                let artifactsPath = try fixturePath.appending(
                    components: ".build",
                    UserToolchain.default.targetTriple.platformBuildPathComponent,
                    "debug",
                    "\(targetName).build"
                )
                let diaFilePaths = try localFileSystem.getDirectoryContents(artifactsPath).filter { filename in
                    // Ignore "*.emit-module.dia".
                    filename.split(".").1 == "dia"
                }.map { filename in
                    artifactsPath.appending(component: filename).pathString
                }

                XCTAssertEqual(sourcePaths.count, diaFilePaths.count)

                _ = try await SwiftPM.fixit.execute(diaFilePaths)
            }

            for (sourcePath, fixedSourcePath) in zip(sourcePaths, fixedSourcePaths) {
                try XCTAssertEqual(
                    localFileSystem.readFileContents(sourcePath),
                    localFileSystem.readFileContents(fixedSourcePath)
                )
            }
        }
    }
}
