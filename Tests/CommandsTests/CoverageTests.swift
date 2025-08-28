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

import Commands
import CoreCommands
import Foundation
import RegexBuilder
import Testing
import _InternalTestSupport

import struct Basics.AbsolutePath
import var Basics.localFileSystem
import func Basics.resolveSymlinks
import enum PackageModel.BuildConfiguration
import struct SPMBuildCore.BuildSystemProvider
import class TSCBasic.BufferedOutputByteStream

@Suite(
    .serializedIfOnWindows,
    .tags(
        .TestSize.large,
        .Feature.CodeCoverage,
        .Feature.CommandLineArguments.EnableCodeCoverage
    )
)
struct CoverageTests {
    @Test(
        .SWBINTTODO(
            "Test failed because of missing plugin support in the PIF builder. This can be reinvestigated after the support is there."
        ),
        .tags(
            .Feature.Command.Build,
            .Feature.Command.Test,
            .Feature.CommandLineArguments.BuildTests,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func executingTestsWithCoverageWithoutCodeBuiltWithCoverageGeneratesAFailure(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await withKnownIssue(
            isIntermittent: (ProcessInfo.hostOperatingSystem == .linux && buildSystem == .swiftbuild)
        ) {
            try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { path in
                _ = try await executeSwiftBuild(
                    path,
                    configuration: config,
                    extraArgs: ["--build-tests"],
                    buildSystem: buildSystem,
                )
                await #expect(throws: (any Error).self) {
                    try await executeSwiftTest(
                        path,
                        configuration: config,
                        extraArgs: [
                            "--skip-build",
                            "--enable-code-coverage",
                        ],
                        throwIfCommandFails: true,
                        buildSystem: buildSystem,
                    )
                }
            }
        } when: {
            buildSystem == .swiftbuild && [.linux, .windows].contains(ProcessInfo.hostOperatingSystem)
        }
    }

    @Test(
        .SWBINTTODO(
            "Test failed because of missing plugin support in the PIF builder. This can be reinvestigated after the support is there."
        ),
        .IssueWindowsCannotSaveAttachment,
        .tags(
            .Feature.Command.Test,
            .Feature.CommandLineArguments.BuildTests,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func executingTestsWithCoverageWithCodeBuiltWithCoverageGeneratesCodeCoverage(
        buildData: BuildData
    ) async throws {
        let buildSystem = buildData.buildSystem
        let config = buildData.config
        // Test that enabling code coverage during building produces the expected folder.
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { path in
                let codeCovPathString = try await executeSwiftTest(
                    path,
                    configuration: config,
                    extraArgs: [
                        "--show-coverage-path"
                    ],
                    throwIfCommandFails: true,
                    buildSystem: buildSystem,
                ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)

                let codeCovPath = try AbsolutePath(validating: codeCovPathString)

                // WHEN we build with coverage enabled
                try await withKnownIssue {
                    try await executeSwiftBuild(
                        path,
                        configuration: config,
                        extraArgs: ["--build-tests", "--enable-code-coverage"],
                        buildSystem: buildSystem,
                    )

                    // AND we test with coverag enabled and skip the build
                    try await executeSwiftTest(
                        path,
                        configuration: config,
                        extraArgs: [
                            "--skip-build",
                            "--enable-code-coverage",
                        ],
                        buildSystem: buildSystem,
                    )

                    // THEN we expect the file to exists
                    expectFileExists(at: codeCovPath)

                    // AND the parent directory is non empty
                    let codeCovFiles = try localFileSystem.getDirectoryContents(codeCovPath.parentDirectory)
                    #expect(codeCovFiles.count > 0)
                } when: {
                    ProcessInfo.hostOperatingSystem == .linux && buildSystem == .swiftbuild
                }
            }
        } when: {
            (ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild)
                || (
                    // error: failed to load coverage: '<scratch-path>/arm64-apple-macosx/Products/Release/SimpleTests.xctest/Contents/MacOS/SimpleTests': `-arch` specifier is invalid or missing for universal binary
                    buildData.buildSystem == .swiftbuild && buildData.config == .release)
                || (
                    // error: /private/var/folders/9j/994sp90x6y3232rzrl9h_z4w0000gn/T/Miscellaneous_TestDiscovery_Simple.3EzR9a/Miscellaneous_TestDiscovery_Simple/Tests/SimpleTests/SwiftTests.swift:2:18 Unable to find module dependency: 'Simple'
                    // @testable import Simple
                    //                  ^
                    // error: SwiftDriver SimpleTests normal arm64 com.apple.xcode.tools.swift.compiler failed with a nonzero exit code. Command line:     cd /private/var/folders/9j/994sp90x6y3232rzrl9h_z4w0000gn/T/Miscellaneous
                    buildData.buildSystem == .native && buildData.config == .release)
        }
    }

    struct GenerateCoverageReportTestData {
        // let buildData: BuildData
        let fixtureName: String
        let coverageFormat: CoverageFormat
    }

    @Test(
        .tags(
            .Feature.Command.Test,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        [
            "Coverage/Simple",
            "Miscellaneous/TestDiscovery/Simple",
        ].flatMap { fixturePath in
            // getBuildData(for: SupportedBuildSystemOnAllPlatforms).flatMap { buildData in
            CoverageFormat.allCases.map { format in
                GenerateCoverageReportTestData(
                    // buildData: buildData,
                    fixtureName: fixturePath,
                    coverageFormat: format,
                )
            }
            // }
        },
    )
    func generateSingleCoverageReport(
        buildData: BuildData,
        testData: GenerateCoverageReportTestData,
    ) async throws {
        let fixtureName = testData.fixtureName
        let coverageFormat = testData.coverageFormat
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: fixtureName) { path in
                let commonCoverageArgs = [
                    "--coverage-format",
                    "\(coverageFormat)",
                ]
                let coveragePathString = try await executeSwiftTest(
                    path,
                    configuration: buildData.config,
                    extraArgs: [
                        "--show-coverage-path"
                    ] + commonCoverageArgs,
                    throwIfCommandFails: true,
                    buildSystem: buildData.buildSystem,
                ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                let coveragePath = try AbsolutePath(validating: coveragePathString)
                try #require(!localFileSystem.exists(coveragePath))

                // WHEN we test with coverage enabled
                try await withKnownIssue {
                    try await executeSwiftTest(
                        path,
                        configuration: buildData.config,
                        extraArgs: [
                            "--enable-code-coverage"
                        ] + commonCoverageArgs,
                        throwIfCommandFails: true,
                        buildSystem: buildData.buildSystem,
                    )

                    // THEN we expect the file to exists
                    #expect(localFileSystem.exists(coveragePath))
                } when: {
                    (buildData.buildSystem == .swiftbuild
                        && [.windows, .linux].contains(ProcessInfo.hostOperatingSystem))
                }
            }
        } when: {
            // error: failed to load coverage: '<scratch-path>/arm64-apple-macosx/Products/Release/SimpleTests.xctest/Contents/MacOS/SimpleTests': `-arch` specifier is invalid or missing for universal binary
            buildData.buildSystem == .swiftbuild && buildData.config == .release
        }

    }

    @Test(
        .tags(
            .Feature.Command.Test,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func generateMultipleCoverageReports(
        buildData: BuildData
    ) async throws {
        let configuration = buildData.config
        let buildSystem = buildData.buildSystem
        try await fixture(name: "Coverage/Simple") { fixturePath in
            let commonCoverageArgs = [
                "--coverage-format",
                "html",
                "--coverage-format",
                "json",
            ]
            let coverateLocationJsonString = try await executeSwiftTest(
                fixturePath,
                configuration: configuration,
                extraArgs: commonCoverageArgs + [
                    "--show-coverage-path",
                    "--show-coverage-path-mode",
                    "json",
                ],
                buildSystem: buildSystem
            ).stdout
            struct ReportOutput: Codable {
                let html: AbsolutePath?
                let json: AbsolutePath?
            }

            let outputData = try #require(
                coverateLocationJsonString.data(using: .utf8),
                "Unable to parse stdout into Data"
            )
            let decoder = JSONDecoder()
            let reportData = try decoder.decode(ReportOutput.self, from: outputData)

            let (_, _) = try await executeSwiftTest(
                fixturePath,
                configuration: configuration,
                extraArgs: commonCoverageArgs + [
                    "--enable-coverage"
                ],
                buildSystem: buildSystem
            )

            // Ensure all paths in the data exists.
            try withKnownIssue {
                let html = try #require(reportData.html)
                #expect(localFileSystem.exists(html))
                let json = try #require(reportData.json)
                #expect(localFileSystem.exists(json))
            } when: {
                // error: failed to load coverage: '<scratch-path>/arm64-apple-macosx/Products/Release/SimpleTests.xctest/Contents/MacOS/SimpleTests': `-arch` specifier is invalid or missing for universal binary
                (buildSystem == .swiftbuild && configuration == .release)
                || (
                    ProcessInfo.hostOperatingSystem == .linux
                    && buildSystem == .swiftbuild && configuration == .debug
                )
            }
        }
    }

    @Suite
    struct htmlCoverageReportTests {
        let commonHtmlCoverageArgs = [
            "--enable-coverage",
            "--coverage-format",
            "html",
        ]
        let responseFilePathComponents = [
            ".swiftpm",
            "configuration",
            "coverage.html.report.args.txt",
        ]

        @Test(
            .tags(
                .Feature.Command.Test,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
            [
                true, false,
            ]
        )
        func htmlReportOutputDirectoryInResponseFileOverrideTheDefaultLocation(
            buildData: BuildData,
            isResponseFileOutputAbsolutePath: Bool,
        ) async throws {
            let buildSystem = buildData.buildSystem
            let configuration = buildData.config
            try await withKnownIssue(isIntermittent: true) {
                // Verify the output directory argument specified in the response file override the default location.
                try await fixture(name: "Coverage/Simple") { fixturePath in
                    let responseFilePath = fixturePath.appending(components: responseFilePathComponents)
                    let responseFileContent: String
                    let expectedOutputPath: String
                    if isResponseFileOutputAbsolutePath {
                        responseFileContent = "--output-dir /foo"
                        expectedOutputPath = AbsolutePath("/foo").pathString
                    } else {
                        responseFileContent = "--output-dir ./foo"
                        expectedOutputPath = fixturePath.appending("foo").pathString
                    }

                    try localFileSystem.createDirectory(responseFilePath.parentDirectory, recursive: true)
                    try localFileSystem.writeFileContents(responseFilePath, string: responseFileContent)

                    let (stdout, stderr) = try await executeSwiftTest(
                        fixturePath,
                        configuration: configuration,
                        extraArgs: [
                            "--show-coverage-path",
                            "--coverage-format",
                            "html",
                        ],
                        buildSystem: buildSystem,
                    )
                    let actualOutput = stdout.trimmingCharacters(in: .whitespacesAndNewlines)

                    #expect(actualOutput == expectedOutputPath, "stderr: \(stderr)")
                }
            } when: {
                // error: failed to load coverage: '<scratch-path>/arm64-apple-macosx/Products/Release/SimpleTests.xctest/Contents/MacOS/SimpleTests': `-arch` specifier is invalid or missing for universal binary
                buildSystem == .swiftbuild && configuration == .release
            }
        }

        @Test(
            .tags(
                .Feature.Command.Test,
            ),
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func existenceOfResponseFileWithNotOutputDirectorySpecifiedUsedTheDefaultLocation(
            buildData: BuildData,
        ) async throws {
            let buildSystem = buildData.buildSystem
            let configuration = buildData.config
            // Verify the output directory argument specified in the response file override the default location.
            try await fixture(name: "Coverage/Simple") { fixturePath in
                let responseFilePath = fixturePath.appending(components: responseFilePathComponents)
                let responseFileContent = "--tab-size=10"

                try localFileSystem.createDirectory(responseFilePath.parentDirectory, recursive: true)
                try localFileSystem.writeFileContents(responseFilePath, string: responseFileContent)

                let (stdout, _) = try await executeSwiftTest(
                    fixturePath,
                    configuration: configuration,
                    extraArgs: [
                        "--show-coverage-path",
                        "--coverage-format",
                        "html",
                    ],
                    buildSystem: buildSystem,
                )
                let actualOutput = stdout.trimmingCharacters(in: .whitespacesAndNewlines)

                #expect(actualOutput.contains(fixturePath.pathString))
            }
        }

        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func htmlExistenceOfReportResponseFileHasFileOnTheCommandLine(
            buildData: BuildData,
        ) async throws {
            // Verify the arguments specified in the response file are used.
            try await fixture(name: "Coverage/Simple") { fixturePath in
                let responseFilePath = fixturePath.appending(components: responseFilePathComponents)

                try localFileSystem.writeFileContents(responseFilePath, string: "")
                expectFileExists(at: responseFilePath)
                let (_, stderr) = try await executeSwiftTest(
                    fixturePath,
                    configuration: buildData.config,
                    extraArgs: [
                        "--very-verbose"  // this emits the coverage commmands
                    ] + commonHtmlCoverageArgs,
                    throwIfCommandFails: false,
                    buildSystem: buildData.buildSystem,
                )
                let responseFileArgument = try Regex("@.*\(responseFilePath)")
                let contains = stderr.components(separatedBy: .newlines).filter {
                    $0.contains("llvm-cov show") && $0.contains(responseFileArgument)  //$0.contains("@\(responseFilePath)")
                }
                #expect(contains.count >= 1)
            }
        }
    }

    @Suite
    struct ShowCoveragePathTests {
        let commonTestArgs = [
            "--show-codecov-path"
        ]
        struct ShowCoveragePathTestData {
            let formats: [CoverageFormat]
            let printMode: CoveragePrintPathMode
            let expected: String
        }
        @Test(
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
            [
                ShowCoveragePathTestData(
                    formats: [CoverageFormat.html],
                    printMode: CoveragePrintPathMode.text,
                    expected: "$(DEFAULT_BUILD_OUTPUT)/codecov/Simple-html",
                ),
                ShowCoveragePathTestData(
                    formats: [CoverageFormat.json],
                    printMode: CoveragePrintPathMode.text,
                    expected: "$(DEFAULT_BUILD_OUTPUT)/codecov/Simple.json",
                ),
                ShowCoveragePathTestData(
                    formats: [CoverageFormat.html, .json],
                    printMode: CoveragePrintPathMode.text,
                    expected: """
                        Html: $(DEFAULT_BUILD_OUTPUT)/codecov/Simple-html
                        Json: $(DEFAULT_BUILD_OUTPUT)/codecov/Simple.json
                        """,
                ),
                ShowCoveragePathTestData(
                    formats: [CoverageFormat.json, .html],
                    printMode: CoveragePrintPathMode.text,
                    expected: """
                        Html: $(DEFAULT_BUILD_OUTPUT)/codecov/Simple-html
                        Json: $(DEFAULT_BUILD_OUTPUT)/codecov/Simple.json
                        """,
                ),
                ShowCoveragePathTestData(
                    formats: [CoverageFormat.json, .html, .json],
                    printMode: CoveragePrintPathMode.text,
                    expected: """
                        Html: $(DEFAULT_BUILD_OUTPUT)/codecov/Simple-html
                        Json: $(DEFAULT_BUILD_OUTPUT)/codecov/Simple.json
                        """,
                ),

                ShowCoveragePathTestData(
                    formats: [CoverageFormat.html],
                    printMode: CoveragePrintPathMode.json,
                    expected: """
                        {
                          "html" : "$(DEFAULT_BUILD_OUTPUT)/codecov/Simple-html"
                        }
                        """,
                ),
                ShowCoveragePathTestData(
                    formats: [CoverageFormat.json],
                    printMode: CoveragePrintPathMode.json,
                    expected: """
                        {
                          "json" : "$(DEFAULT_BUILD_OUTPUT)/codecov/Simple.json"
                        }
                        """,
                ),
                ShowCoveragePathTestData(
                    formats: [CoverageFormat.html, .json],
                    printMode: CoveragePrintPathMode.json,
                    expected: """
                        {
                          "html" : "$(DEFAULT_BUILD_OUTPUT)/codecov/Simple-html",
                          "json" : "$(DEFAULT_BUILD_OUTPUT)/codecov/Simple.json"
                        }
                        """,
                ),
                ShowCoveragePathTestData(
                    formats: [CoverageFormat.json, .html],
                    printMode: CoveragePrintPathMode.json,
                    expected: """
                        {
                          "html" : "$(DEFAULT_BUILD_OUTPUT)/codecov/Simple-html",
                          "json" : "$(DEFAULT_BUILD_OUTPUT)/codecov/Simple.json"
                        }
                        """,
                ),
                ShowCoveragePathTestData(
                    formats: [CoverageFormat.json, .html, .json],
                    printMode: CoveragePrintPathMode.json,
                    expected: """
                        {
                          "html" : "$(DEFAULT_BUILD_OUTPUT)/codecov/Simple-html",
                          "json" : "$(DEFAULT_BUILD_OUTPUT)/codecov/Simple.json"
                        }
                        """,
                ),

            ]
        )
        func specifiedFormatsFormatInTextModeOnlyDisplaysThePath(
            buildData: BuildData,
            testData: ShowCoveragePathTestData,
        ) async throws {
            let buildSystem = buildData.buildSystem
            let configuration = buildData.config
            try await fixture(name: "Coverage/Simple") { fixturePath in
                let defaultBuildOUtput = try await executeSwiftBuild(
                    fixturePath,
                    configuration: configuration,
                    extraArgs: ["--show-bin-path"],

                    buildSystem: buildSystem,
                ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                let updatedExpected = testData.expected.replacing(
                    "$(DEFAULT_BUILD_OUTPUT)",
                    with: defaultBuildOUtput
                )

                let actual = try await executeSwiftTest(
                    fixturePath,
                    configuration: configuration,
                    extraArgs: self.commonTestArgs + [
                        "--show-codecov-path-mode",
                        testData.printMode.rawValue,
                    ] + testData.formats.flatMap({ ["--coverage-format", $0.rawValue] }),
                    buildSystem: buildSystem,
                ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)

                #expect(actual == updatedExpected)
            }
        }
    }

}
