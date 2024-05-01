//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Commands
import SPMTestSupport
import XCTest

import class TSCBasic.Process
import enum TSCBasic.ProcessEnv

private let deprecationWarning = "warning: `swift experimental-sdk` command is deprecated and will be removed in a future version of SwiftPM. Use `swift sdk` instead."

final class SDKCommandTests: CommandsTestCase {
    func testUsage() throws {
        for command in [SwiftPM.sdk, SwiftPM.experimentalSDK] {
            let stdout = try command.execute(["-help"]).stdout
            XCTAssert(stdout.contains("USAGE: swift sdk <subcommand>") || stdout.contains("USAGE: swift sdk [<subcommand>]"), "got stdout:\n" + stdout)
        }
    }

    func testVersion() throws {
        for command in [SwiftPM.sdk, SwiftPM.experimentalSDK] {
            let stdout = try command.execute(["--version"]).stdout
            XCTAssert(stdout.contains("Swift Package Manager"), "got stdout:\n" + stdout)
        }
    }

    func testInstallSDK() throws {
        for command in [SwiftPM.sdk, SwiftPM.experimentalSDK] {
            try fixture(name: "SwiftSDKs") { fixturePath in
                for bundle in ["test-sdk.artifactbundle.tar.gz", "test-sdk.artifactbundle.zip"] {
                    var (stdout, stderr) = try command.execute(
                        [
                            "install",
                            "--swift-sdks-path", fixturePath.pathString,
                            fixturePath.appending(bundle).pathString
                        ]
                    )

                    if command == .experimentalSDK {
                        XCTAssertMatch(stdout, .contains(deprecationWarning))
                    }

                    // We only expect tool's output on the stdout stream.
                    XCTAssertMatch(
                        stdout,
                        .contains("\(bundle)` successfully installed as test-sdk.artifactbundle.")
                    )

                    XCTAssertEqual(stderr.count, 0)

                    (stdout, stderr) = try command.execute(
                        ["list", "--swift-sdks-path", fixturePath.pathString])

                    if command == .experimentalSDK {
                        XCTAssertMatch(stdout, .contains(deprecationWarning))
                    }

                    // We only expect tool's output on the stdout stream.
                    XCTAssertMatch(stdout, .contains("test-artifact"))
                    XCTAssertEqual(stderr.count, 0)

                    XCTAssertThrowsError(try command.execute(
                        [
                            "install",
                            "--swift-sdks-path", fixturePath.pathString,
                            fixturePath.appending(bundle).pathString
                        ]
                    )) { error in
                        guard case SwiftPMError.executionFailure(_, _, let stderr) = error else {
                            XCTFail()
                            return
                        }

                        XCTAssertTrue(
                            stderr.contains(
                                "Error: Swift SDK bundle with name `test-sdk.artifactbundle` is already installed. Can't install a new bundle with the same name."
                            ),
                            "got stderr: \(stderr)"
                        )
                    }

                    if command == .experimentalSDK {
                        XCTAssertMatch(stdout, .contains(deprecationWarning))
                    }

                    (stdout, stderr) = try command.execute(
                        ["remove", "--swift-sdks-path", fixturePath.pathString, "test-artifact"])

                    if command == .experimentalSDK {
                        XCTAssertMatch(stdout, .contains(deprecationWarning))
                    }

                    // We only expect tool's output on the stdout stream.
                    XCTAssertMatch(stdout, .contains("test-sdk.artifactbundle` was successfully removed from the file system."))
                    XCTAssertEqual(stderr.count, 0)

                    (stdout, stderr) = try command.execute(
                        ["list", "--swift-sdks-path", fixturePath.pathString])

                    if command == .experimentalSDK {
                        XCTAssertMatch(stdout, .contains(deprecationWarning))
                    }

                    // We only expect tool's output on the stdout stream.
                    XCTAssertNoMatch(stdout, .contains("test-artifact"))
                    XCTAssertEqual(stderr.count, 0)
                }
            }
        }
    }
}
