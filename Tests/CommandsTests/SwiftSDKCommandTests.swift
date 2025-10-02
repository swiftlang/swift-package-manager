//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
// import Foundation

import Basics
import Commands
import _InternalTestSupport
import Testing

import class Basics.AsyncProcess

private let sdkCommandDeprecationWarning = """
    warning: `swift experimental-sdk` command is deprecated and will be removed in a future version of SwiftPM. Use \
    `swift sdk` instead.

    """

@Suite(
    .serialized,
    .tags(
        .Feature.Command.Sdk,
        .TestSize.large,
    ),
)
struct SwiftSDKCommandTests {
    @Test(
        arguments: [SwiftPM.sdk, SwiftPM.experimentalSDK],
    )
    func usage(
        command: SwiftPM,
    ) async throws {

        let stdout = try await command.execute(["-help"]).stdout
        #expect(
            stdout.contains("USAGE: swift sdk <subcommand>") || stdout.contains("USAGE: swift sdk [<subcommand>]"),
            "got stdout:\n\(stdout)",
        )
    }

    @Test(
        arguments: [SwiftPM.sdk, SwiftPM.experimentalSDK],
    )
    func commandDoesNotEmitDuplicateSymbols(
        command: SwiftPM,
    ) async throws {
        let (stdout, stderr) = try await command.execute(["--help"])
        let duplicateSymbolRegex = try Regex(#"objc[83768]: (.*) is implemented in both .* \(.*\) and .* \(.*\) . One of the two will be used. Which one is undefined."#)
        #expect(!stdout.contains(duplicateSymbolRegex))
        #expect(!stderr.contains(duplicateSymbolRegex))

    }

    @Test(
        arguments: [SwiftPM.sdk, SwiftPM.experimentalSDK],
    )
    func version(
        command: SwiftPM,
    ) async throws {
        for command in [SwiftPM.sdk, SwiftPM.experimentalSDK] {
            let stdout = try await command.execute(["--version"]).stdout
            let versionRegex = try Regex(#"Swift Package Manager -( \w+ )?\d+.\d+.\d+(-\w+)?"#)
            #expect(stdout.contains(versionRegex))
        }
    }

    @Test(
        arguments: [SwiftPM.sdk, SwiftPM.experimentalSDK],
        ["test-sdk.artifactbundle.tar.gz", "test-sdk.artifactbundle.zip"],
    )
    func installSubcommand(
        command: SwiftPM,
        bundle: String,
    ) async throws {
        try await fixture(name: "SwiftSDKs") { fixturePath in
            let bundlePath = fixturePath.appending(bundle)
            expectFileExists(at: bundlePath)
            var (stdout, stderr) = try await command.execute(
                [
                    "install",
                    "--swift-sdks-path", fixturePath.pathString,
                    bundlePath.pathString,
                ]
            )

            if command == .experimentalSDK {
                #expect(stderr.contains(sdkCommandDeprecationWarning))
                #expect(!stdout.contains(sdkCommandDeprecationWarning))
            }

            // We only expect tool's output on the stdout stream.
            #expect(
                (stdout + "\nstderr:\n" + stderr).contains("\(bundle)` successfully installed as test-sdk.artifactbundle.")
            )

            (stdout, stderr) = try await command.execute(
                ["list", "--swift-sdks-path", fixturePath.pathString])

            if command == .experimentalSDK {
                #expect(stderr.contains(sdkCommandDeprecationWarning))
                #expect(!stdout.contains(sdkCommandDeprecationWarning))
            }

            // We only expect tool's output on the stdout stream.
            #expect(stdout.contains("test-artifact"))

            await expectThrowsCommandExecutionError(
                try await command.execute(
                    [
                        "install",
                        "--swift-sdks-path", fixturePath.pathString,
                        bundlePath.pathString,
                    ]
                )
            ) { error in
                let stderr = error.stderr
                #expect(
                    stderr.contains(
                        "Error: Swift SDK bundle with name `test-sdk.artifactbundle` is already installed. Can't install a new bundle with the same name."
                    ),
                )
            }

            if command == .experimentalSDK {
                #expect(stderr.contains(sdkCommandDeprecationWarning))
            }

            (stdout, stderr) = try await command.execute(
                ["remove", "--swift-sdks-path", fixturePath.pathString, "test-artifact"])

            if command == .experimentalSDK {
                #expect(stderr.contains(sdkCommandDeprecationWarning))
                #expect(!stdout.contains(sdkCommandDeprecationWarning))
            }

            // We only expect tool's output on the stdout stream.
            #expect(stdout.contains("test-sdk.artifactbundle` was successfully removed from the file system."))

            (stdout, stderr) = try await command.execute(
                ["list", "--swift-sdks-path", fixturePath.pathString])

            if command == .experimentalSDK {
                #expect(stderr.contains(sdkCommandDeprecationWarning))
                #expect(!stdout.contains(sdkCommandDeprecationWarning))
            }

            // We only expect tool's output on the stdout stream.
            #expect(!stdout.contains("test-artifact"))
        }
    }

    @Test(
        arguments: [SwiftPM.sdk, SwiftPM.experimentalSDK],
    )
    func configureSubcommand(
        command: SwiftPM,
    ) async throws {
        let deprecationWarning = """
            warning: `swift sdk configuration` command is deprecated and will be removed in a future version of \
            SwiftPM. Use `swift sdk configure` instead.

            """

        try await fixture(name: "SwiftSDKs") { fixturePath in
            let bundle = "test-sdk.artifactbundle.zip"

            var (stdout, stderr) = try await command.execute([
                "install",
                "--swift-sdks-path", fixturePath.pathString,
                fixturePath.appending(bundle).pathString,
            ])

            // We only expect tool's output on the stdout stream.
            #expect(
                stdout.contains("\(bundle)` successfully installed as test-sdk.artifactbundle.")
            )

            let deprecatedShowSubcommand = ["configuration", "show"]

            for showSubcommand in [deprecatedShowSubcommand, ["configure", "--show-configuration"]] {
                let invocation =
                    showSubcommand + [
                        "--swift-sdks-path", fixturePath.pathString,
                        "test-artifact",
                        "aarch64-unknown-linux-gnu",
                    ]
                (stdout, stderr) = try await command.execute(invocation)

                if command == .experimentalSDK {
                    #expect(stderr.contains(sdkCommandDeprecationWarning))
                }

                if showSubcommand == deprecatedShowSubcommand {
                    #expect(stderr.contains(deprecationWarning))
                }

                let sdkSubpath = ["test-sdk.artifactbundle", "sdk", "sdk"]

                #expect(
                    stdout == """
                        sdkRootPath: \(fixturePath.appending(components: sdkSubpath))
                        swiftResourcesPath: not set
                        swiftStaticResourcesPath: not set
                        includeSearchPaths: not set
                        librarySearchPaths: not set
                        toolsetPaths: not set

                        """
                )

                let deprecatedSetSubcommand = ["configuration", "set"]
                let deprecatedResetSubcommand = ["configuration", "reset"]
                for setSubcommand in [deprecatedSetSubcommand, ["configure"]] {
                    for resetSubcommand in [deprecatedResetSubcommand, ["configure", "--reset"]] {
                        var invocation =
                            setSubcommand + [
                                "--swift-resources-path", fixturePath.appending("foo").pathString,
                                "--swift-sdks-path", fixturePath.pathString,
                                "test-artifact",
                                "aarch64-unknown-linux-gnu",
                            ]
                        (stdout, stderr) = try await command.execute(invocation)

                        #expect(
                            stdout == """
                                info: These properties of Swift SDK `test-artifact` for target triple `aarch64-unknown-linux-gnu` \
                                were successfully updated: swiftResourcesPath.

                                """
                        )

                        if command == .experimentalSDK {
                            #expect(stderr.contains(sdkCommandDeprecationWarning))
                        }

                        if setSubcommand == deprecatedSetSubcommand {
                            #expect(stderr.contains(deprecationWarning))
                        }

                        invocation =
                            showSubcommand + [
                                "--swift-sdks-path", fixturePath.pathString,
                                "test-artifact",
                                "aarch64-unknown-linux-gnu",
                            ]
                        (stdout, stderr) = try await command.execute(invocation)

                        #expect(
                            stdout == """
                                sdkRootPath: \(fixturePath.appending(components: sdkSubpath).pathString)
                                swiftResourcesPath: \(fixturePath.appending("foo"))
                                swiftStaticResourcesPath: not set
                                includeSearchPaths: not set
                                librarySearchPaths: not set
                                toolsetPaths: not set

                                """
                        )

                        invocation =
                            resetSubcommand + [
                                "--swift-sdks-path", fixturePath.pathString,
                                "test-artifact",
                                "aarch64-unknown-linux-gnu",
                            ]
                        (stdout, stderr) = try await command.execute(invocation)

                        if command == .experimentalSDK {
                            #expect(stderr.contains(sdkCommandDeprecationWarning))
                        }

                        if resetSubcommand == deprecatedResetSubcommand {
                            #expect(stderr.contains(deprecationWarning))
                        }

                        #expect(
                            stdout == """
                                info: All configuration properties of Swift SDK `test-artifact` for target triple `aarch64-unknown-linux-gnu` were successfully reset.

                                """
                        )
                    }
                }
            }

            (stdout, stderr) = try await command.execute(
                ["remove", "--swift-sdks-path", fixturePath.pathString, "test-artifact"])

            // We only expect tool's output on the stdout stream.
            #expect(stdout.contains("test-sdk.artifactbundle` was successfully removed from the file system."))
        }
    }
}
