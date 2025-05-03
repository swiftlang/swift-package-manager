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

import Basics

@testable
import Commands

import PackageModel

import XCTest

final class MigrateCommandTests: CommandsTestCase {
    func testHelp() async throws {
        let stdout = try await SwiftPM.Migrate.execute(["-help"]).stdout

        XCTAssert(stdout.contains("USAGE: swift migrate"), stdout)
        XCTAssert(stdout.contains("-h, -help, --help"), stdout)
    }

    func testMigration() async throws {
        try XCTSkipIf(
            !UserToolchain.default.supportesSupportedFeatures,
            "skipping because test environment compiler doesn't support `-print-supported-features`"
        )

        try await fixture(name: "SwiftMigrate/ExistentialAnyMigration") { fixturePath in
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

            _ = try await executeSwiftMigrate(
                fixturePath,
                extraArgs: ["--to-feature", "ExistentialAny"]
            )

            XCTAssertEqual(sourcePaths.count, fixedSourcePaths.count)

            for (sourcePath, fixedSourcePath) in zip(sourcePaths, fixedSourcePaths) {
                try XCTAssertEqual(
                    localFileSystem.readFileContents(sourcePath),
                    localFileSystem.readFileContents(fixedSourcePath)
                )
            }
        }
    }
}
