//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025-2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Basics.Diagnostic
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
        .tags(
            .Feature.Command.Build,
            .Feature.Command.Test,
            .Feature.CommandLineArguments.BuildTests,
        ),
        .IssueWindowsPathNoEntry,
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9600", relationship: .defect),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func executingTestsWithCoverageWithoutCodeBuiltWithCoverageGeneratesAFailure(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
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
                            "--enable-coverage",
                        ],
                        buildSystem: buildSystem,
                        throwIfCommandFails: true,
                    )
                }
            }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9588", relationship: .verifies),
        .tags(
            .Feature.Command.Test,
            .Feature.CommandLineArguments.BuildTests,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func executingTestsWithCoverageWithCodeBuiltWithCoverageGeneratesCodeCoverage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        // Test that enabling code coverage during building produces the expected folder.
        try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { path in
            let codeCovPathString = try await getCoveragePath(
                path,
                with: BuildData(buildSystem: buildSystem, config: config),
            )

            let codeCovPath = try AbsolutePath(validating: codeCovPathString)

            // WHEN we build with coverage enabled
                try await executeSwiftBuild(
                    path,
                    configuration: config,
                    extraArgs: [
                        "--build-tests",
                        "--enable-coverage",
                    ],
                    buildSystem: buildSystem,
                )

                // AND we test with coverage enabled and skip the build
                try await executeSwiftTest(
                    path,
                    configuration: config,
                    extraArgs: [
                        "--skip-build",
                        "--enable-code-coverage",
                    ],
                    buildSystem: buildSystem,
                )

                // THEN the coverage directory is non empty
                try requireFileExists(at: codeCovPath)
                let codeCovFiles = try localFileSystem.getDirectoryContents(codeCovPath.parentDirectory)
                #expect(codeCovFiles.count > 0)
        }
    }

    struct GenerateCoverageReportTestData {
        let fixtureName: String
        let coverageFormat: CoverageFormat
    }

    @Test(
        .tags(
            .Feature.Command.Test,
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9588", relationship: .defect),
        .IssueWindowsPathNoEntry,
        arguments: SupportedBuildSystemOnAllPlatforms, [
            "Coverage/Simple",
            "Miscellaneous/TestDiscovery/Simple",
        ].flatMap { fixturePath in
            CoverageFormat.allCases.map { format in
                GenerateCoverageReportTestData(
                    fixtureName: fixturePath,
                    coverageFormat: format,
                )
            }
        },
    )
    func generateSingleCoverageReport(
        buildSystem: BuildSystemProvider.Kind,
        testData: GenerateCoverageReportTestData,
    ) async throws {
        let config = BuildConfiguration.debug
        let fixtureName = testData.fixtureName
        let coverageFormat = testData.coverageFormat
        try await fixture(name: fixtureName) { path in

            let commonCoverageArgs = [
                "--coverage-format",
                "\(coverageFormat)",
            ]

            let coveragePathString = try await getCoveragePath(
                path,
                with: BuildData(buildSystem: buildSystem, config: config),
                format: coverageFormat,
            )
            let coveragePath = try AbsolutePath(validating: coveragePathString)
            try #require(localFileSystem.exists(coveragePath) == false)

            // WHEN we test with coverage enabled
                try await executeSwiftTest(
                    path,
                    configuration: config,
                    extraArgs: [
                        "--enable-coverage",
                    ] + commonCoverageArgs,
                    buildSystem: buildSystem,
                    throwIfCommandFails: true,
                )

                // THEN we expect the file to exists
                expectFileExists(at: coveragePath)
        }
    }

    @Test(
        .tags(
            .Feature.Command.Test,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func generateMultipleCoverageReports(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
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
            let html = try #require(reportData.html)
            expectFileExists(at: html)
            let json = try #require(reportData.json)
            expectFileExists(at: json)
        }
    }

    @Suite
    struct ShowCoveragePathTests {
        let commonTestArgs = [
            "--show-coverage-path"
        ]
        struct ShowCoveragePathTestData: CustomTestStringConvertible {
            var testDescription: String { id}

            let formats: [CoverageFormat]
            let printMode: CoveragePrintPathMode
            let expected: String
            let id: String
        }
        @Test(
            arguments: SupportedBuildSystemOnAllPlatforms,
            [
                ShowCoveragePathTestData(
                    formats: [CoverageFormat.html],
                    printMode: CoveragePrintPathMode.text,
                    expected: "$(DEFAULT_BUILD_OUTPUT)/codecov/Simple-html",
                    id: "show path text with one HTML coverage format displays the path",
                ),
                ShowCoveragePathTestData(
                    formats: [CoverageFormat.json],
                    printMode: CoveragePrintPathMode.text,
                    expected: "$(DEFAULT_BUILD_OUTPUT)/codecov/Simple.json",
                    id: "show path text with one JSON coverage format displays the path",
                ),
                ShowCoveragePathTestData(
                    formats: [CoverageFormat.html, .json],
                    printMode: CoveragePrintPathMode.text,
                    expected: """
                        Html: $(DEFAULT_BUILD_OUTPUT)/codecov/Simple-html
                        Json: $(DEFAULT_BUILD_OUTPUT)/codecov/Simple.json
                        """,
                    id: "show path text with HTML and JSON coverage format displays the path",
                ),
                ShowCoveragePathTestData(
                    formats: [CoverageFormat.json, .html],
                    printMode: CoveragePrintPathMode.text,
                    expected: """
                        Html: $(DEFAULT_BUILD_OUTPUT)/codecov/Simple-html
                        Json: $(DEFAULT_BUILD_OUTPUT)/codecov/Simple.json
                        """,
                    id: "show path text with JSON and HTML coverage format displays the path maintains the same order",
                ),
                ShowCoveragePathTestData(
                    formats: [CoverageFormat.json, .html, .json],
                    printMode: CoveragePrintPathMode.text,
                    expected: """
                        Html: $(DEFAULT_BUILD_OUTPUT)/codecov/Simple-html
                        Json: $(DEFAULT_BUILD_OUTPUT)/codecov/Simple.json
                        """,
                    id: "show path text with duplicated coverge format display unique formats while preserving order",
                ),

                ShowCoveragePathTestData(
                    formats: [CoverageFormat.html],
                    printMode: CoveragePrintPathMode.json,
                    expected: """
                        {
                          "html" : "$(DEFAULT_BUILD_OUTPUT)/codecov/Simple-html"
                        }
                        """,
                    id: "show path JSON with one HTML coverage format displays the path",
                ),
                ShowCoveragePathTestData(
                    formats: [CoverageFormat.json],
                    printMode: CoveragePrintPathMode.json,
                    expected: """
                        {
                          "json" : "$(DEFAULT_BUILD_OUTPUT)/codecov/Simple.json"
                        }
                        """,
                    id: "show path JSON with one JSON coverage format displays the path",

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
                    id: "show path JSON with HTML and JSON coverage format displays the path",
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
                    id: "show path JSON with JSON and HTML coverage format displays the path maintains the same order",
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
                    id: "show path JSON with duplicated coverge format display unique formats while preserving order",
                ),

            ]
        )
        func specifiedFormatsFormatInTextModeOnlyDisplaysThePath(
            buildSystem: BuildSystemProvider.Kind,
            testData: ShowCoveragePathTestData,
        ) async throws {
            let configuration = BuildConfiguration.debug
            try await fixture(name: "Coverage/Simple") { fixturePath in
                let defaultBuildOutput = try await executeSwiftBuild(
                    fixturePath,
                    configuration: configuration,
                    extraArgs: ["--show-bin-path"],

                    buildSystem: buildSystem,
                ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                let updatedExpected = testData.expected.replacing(
                    "$(DEFAULT_BUILD_OUTPUT)",
                    with: defaultBuildOutput
                )

                let (stdout, stderr) = try await executeSwiftTest(
                    fixturePath,
                    configuration: configuration,
                    extraArgs: self.commonTestArgs + [
                        "--show-coverage-path",
                        testData.printMode.rawValue,
                    ] + testData.formats.flatMap({ ["--coverage-format", $0.rawValue] }),
                    buildSystem: buildSystem,
                )
                let actual = stdout.trimmingCharacters(in: .whitespacesAndNewlines)

                #expect(actual == updatedExpected, "stdout: \(stdout)\n\nstderr: \(stderr)")
            }
        }

        struct DeprecationWarningIsEmittedTestData: CustomTestStringConvertible {
            var testDescription: String { id }

            let argsUT: [String]
            let expectedStderr: [Diagnostic]
            let id: String
        }

        @Test(
            arguments: SupportedBuildSystemOnAllPlatforms, [
                DeprecationWarningIsEmittedTestData(
                    argsUT: CoverageFormat.allCases.flatMap({ ["--coverage-format", $0.rawValue] }) + ["--show-coverage-path"],
                    expectedStderr: [
                        Basics.Diagnostic.showCoveragePathTextOutputWarning,
                        // "warning: The contents of this output are subject to change in the future. Use `--show-coverage-path json` if the output is required in a script.",
                    ],
                    id: "show path text with multiple coverage formats emits a warning",
                ),
                DeprecationWarningIsEmittedTestData(
                    argsUT: ["--show-code-coverage-path", "--disable-code-coverage"],
                    expectedStderr: [
                        Basics.Diagnostic.deprecatedEnableDisableCoverage,
                        Basics.Diagnostic.deprecatedShowCodeCoveragePath,
                    ],
                    id: "Using deprecated --show-code-coverage-path and --disable-code-coverage arguments emits a warning for each argument",
                ),
                DeprecationWarningIsEmittedTestData(
                    argsUT: ["--show-code-coverage-path", "--enable-code-coverage"],
                    expectedStderr: [
                        Basics.Diagnostic.deprecatedEnableDisableCoverage,
                        Basics.Diagnostic.deprecatedShowCodeCoveragePath,
                    ],
                    id: "Using deprecated --show-code-coverage-path and --enable-code-coverage arguments emits a warning for each argument",
                ),
                DeprecationWarningIsEmittedTestData(
                    argsUT: ["--show-codecov-path"],
                    expectedStderr: [
                        Basics.Diagnostic.deprecatedShowCodeCoveragePath
                    ],
                    id: "Using deprecated --show-codecov-path argument emits a warning",
                ),
                DeprecationWarningIsEmittedTestData(
                    argsUT: ["--enable-coverage", "--enable-code-coverage"],
                    expectedStderr: [
                        Basics.Diagnostic.deprecatedEnableDisableCoverage,
                    ],
                    id: "Combining new --enable-coverage with deprecated --enable-code-coverage emits the deprecation warning",
                ),
                DeprecationWarningIsEmittedTestData(
                    argsUT: ["--disable-code-coverage", "--enable-code-coverage"],
                    expectedStderr: [
                        Basics.Diagnostic.deprecatedEnableDisableCoverage,
                    ],
                    id: "Combining --disable-code-coverage with deprecated --enable-code-coverage emits the deprecation warning",
                ),
            ],
        )
        func deprecationWarningIsEmitted(
            buildSystem: BuildSystemProvider.Kind,
            tcData: DeprecationWarningIsEmittedTestData,
        ) async throws {
            let config = BuildConfiguration.debug
            try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
                let (_, stderr) = try await executeSwiftTest(
                    fixturePath,
                    configuration: config,
                    extraArgs: [
                        "--show-coverage-path", // we don't want to build or execute the tests.
                    ] + tcData.argsUT,
                    buildSystem: buildSystem,
                )

                for diag in tcData.expectedStderr {
                    #expect(
                        stderr.contains("\(diag.severity): \(diag.message)") == true,
                        "expected '\(diag)' in stderr: \(stderr)"
                    )
                }
            }
        }
    }

    @Suite
    struct XcovArgumentsTests {
        @Test(
            arguments: SupportedBuildSystemOnAllPlatforms, [
                (
                    XcovArgs: [
                        "html=--show-region-summary",
                        "--num-threads=4",
                        "json=--use-color",
                        "--summary-only",
                        "html=--project-title=MyTitle",
                    ],
                    expectedHtmlReportCmd: "--show-region-summary --num-threads=4 --summary-only --project-title=MyTitle",
                    expectedJsonReportCmd: "--num-threads=4 --use-color --summary-only",
                ),
                (
                    XcovArgs: [
                        "html=--project-title=\"My Title\"",
                    ],
                    expectedHtmlReportCmd: "--project-title=\"My Title\"",
                    expectedJsonReportCmd: "",
                ),
                (
                    XcovArgs: [
                        "html=--project-title",
                        "html=\"My Title\""
                    ],
                    expectedHtmlReportCmd: "--project-title \"My Title\"",
                    expectedJsonReportCmd: "",
                ),
            ],
        )
        func xcovArgumentsArePassed(
            buildSystem: BuildSystemProvider.Kind,
            xcovData: (XcovArgs: [String], expectedHtmlReportCmd: String, expectedJsonReportCmd: String),
        ) async throws {
            let config = BuildConfiguration.debug
            try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
                let (_, stderr) = try await executeSwiftTest(
                    fixturePath,
                    configuration: config,
                    extraArgs: [
                        "--enable-coverage",
                        "--very-verbose",
                        "--coverage-format",
                        "html",
                        "--coverage-format",
                        "json",
                    ],
                    Xcov: xcovData.XcovArgs,
                    buildSystem: buildSystem,
                )

                let htmlCommandRegex = try Regex("debug: Calling HTML: .*llvm-cov show.*\(xcovData.expectedHtmlReportCmd).*")
                let jsonCommandRegex = try Regex("debug: Calling JSON: .*llvm-cov export.*\(xcovData.expectedJsonReportCmd).*")
                #expect(
                    stderr.contains(htmlCommandRegex) == true,
                    "Did not find HTML command",
                )
                #expect(
                    stderr.contains(jsonCommandRegex) == true,
                    "Did not find JSON command",
                )
            }
        }

        @Test(
            .tags(
                .Feature.Command.Test,
            ),
            arguments: SupportedBuildSystemOnAllPlatforms,
        )
        func htmlCoverageReportRespectsXcovOutputDirOverride(
            buildSystem: BuildSystemProvider.Kind,
        ) async throws {
            let configuration = BuildConfiguration.debug
            try await fixture(name: "Coverage/Simple") { fixturePath in
                let customHtmlDir = fixturePath.appending("custom-html-output")
                try requireDirectoryDoesNotExist(at: customHtmlDir)

                try await executeSwiftTest(
                    fixturePath,
                    configuration: configuration,
                    extraArgs: [
                        "--enable-coverage",
                        "--coverage-format",
                        "html",
                    ],
                    Xcov: [
                        "html=--output-dir=\(customHtmlDir.pathString)",
                    ],
                    buildSystem: buildSystem,
                    throwIfCommandFails: true,
                )

                expectFileExists(at: customHtmlDir.appending("index.html"))
            }
        }

        @Test(
            .tags(
                .Feature.Command.Test,
            ),
            arguments: SupportedBuildSystemOnAllPlatforms,
        )
        func showCoveragePathReflectsXcovHtmlOutputDirOverride(
            buildSystem: BuildSystemProvider.Kind,
        ) async throws {
            let configuration = BuildConfiguration.debug
            try await fixture(name: "Coverage/Simple") { fixturePath in
                let customHtmlDir = fixturePath.appending("custom-html-output")

                let (stdout, stderr) = try await executeSwiftTest(
                    fixturePath,
                    configuration: configuration,
                    extraArgs: [
                        "--show-coverage-path",
                        "--coverage-format",
                        "html",
                    ],
                    Xcov: [
                        "html=--output-dir=\(customHtmlDir.pathString)",
                    ],
                    buildSystem: buildSystem,
                )

                let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                #expect(
                    trimmedStdout == customHtmlDir.pathString,
                    "stdout: '\(stdout)'\n\nstderr: '\(stderr)'",
                )
            }
        }

        @Test(
            .tags(
                .Feature.Command.Test,
            ),
            arguments: SupportedBuildSystemOnAllPlatforms,
        )
        func showCoveragePathIgnoresXcovJsonOutputDirForJsonFormat(
            buildSystem: BuildSystemProvider.Kind,
        ) async throws {
            let configuration = BuildConfiguration.debug
            try await fixture(name: "Coverage/Simple") { fixturePath in
                let bogusOutputDir = fixturePath.appending("this-should-be-ignored")

                let defaultBuildOutput = try await executeSwiftBuild(
                    fixturePath,
                    configuration: configuration,
                    extraArgs: [
                        "--show-bin-path",
                    ],
                    buildSystem: buildSystem,
                ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                let expectedJsonPath = "\(defaultBuildOutput)/codecov/Simple.json"

                let (stdout, stderr) = try await executeSwiftTest(
                    fixturePath,
                    configuration: configuration,
                    extraArgs: [
                        "--show-coverage-path",
                        "--coverage-format",
                        "json",
                    ],
                    Xcov: [
                        "json=--output-dir=\(bogusOutputDir.pathString)",
                    ],
                    buildSystem: buildSystem,
                )

                let actual = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                #expect(
                    actual == expectedJsonPath,
                    "stdout: \(stdout)\n\nstderr: \(stderr)",
                )
                #expect(
                    actual.contains(bogusOutputDir.pathString) == false,
                    "JSON path should not be overridable via -Xcov json=--output-dir. stdout: \(stdout)",
                )
            }
        }

        struct XcovFailureTestData: CustomTestStringConvertible {
            var testDescription: String { id }
            let format: CoverageFormat
            let xcovArg: String
            let expectedErrorSubstring: String
            let id: String
        }

        @Test(
            .tags(
                .Feature.Command.Test,
            ),
            .IssueWindowsPathNoEntry,
            arguments: SupportedBuildSystemOnAllPlatforms, [
                XcovFailureTestData(
                    format: .html,
                    xcovArg: "html=--this-is-not-a-real-llvm-cov-flag",
                    expectedErrorSubstring: "Unable to generate HTML code coverage report",
                    id: "HTML: bogus -Xcov html= arg surfaces llvm-cov show failure",
                ),
                XcovFailureTestData(
                    format: .json,
                    xcovArg: "json=--this-is-not-a-real-llvm-cov-flag",
                    expectedErrorSubstring: "Unable to export code coverage",
                    id: "JSON: bogus -Xcov json= arg surfaces llvm-cov export failure",
                ),
            ],
        )
        func bogusXcovArgumentSurfacesLlvmCovFailure(
            buildSystem: BuildSystemProvider.Kind,
            testData: XcovFailureTestData,
        ) async throws {
            let configuration = BuildConfiguration.debug
            try await fixture(name: "Coverage/Simple") { fixturePath in
                let (_, stderr) = try await executeSwiftTest(
                    fixturePath,
                    configuration: configuration,
                    extraArgs: [
                        "--enable-coverage",
                        "--coverage-format",
                        testData.format.rawValue,
                    ],
                    Xcov: [
                        testData.xcovArg,
                    ],
                    buildSystem: buildSystem,
                )

                #expect(
                    stderr.contains(testData.expectedErrorSubstring),
                    "Expected '\(testData.expectedErrorSubstring)' in stderr for \(testData.id).\nstderr: \(stderr)",
                )
            }
        }
    }
}
