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
                            "--enable-code-coverage",
                        ],
                        buildSystem: buildSystem,
                        throwIfCommandFails: true,
                    )
                }
            }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9588", relationship: .defect),
        .IssueWindowsPathNoEntry,
        .tags(
            .Feature.Command.Test,
            .Feature.CommandLineArguments.BuildTests,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms
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
                    "--enable-code-coverage",
                ],
                buildSystem: buildSystem,
            )

            // THEN the coverage directory is non empty
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
            try #require(!localFileSystem.exists(coveragePath))

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
                #expect(localFileSystem.exists(coveragePath))
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
            // try withKnownIssue {
                let html = try #require(reportData.html)
                #expect(localFileSystem.exists(html))
                let json = try #require(reportData.json)
                #expect(localFileSystem.exists(json))
            // } when: {
            //     ProcessInfo.hostOperatingSystem == .linux && buildSystem == .swiftbuild && configuration == .debug
            // }
        }
    }

    @Suite
    struct ShowCoveragePathTests {
        let commonTestArgs = [
            "--show-coverage-path"
        ]
        struct ShowCoveragePathTestData {
            let formats: [CoverageFormat]
            let printMode: CoveragePrintPathMode
            let expected: String
        }
        @Test(
            arguments: SupportedBuildSystemOnAllPlatforms,
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
            buildSystem: BuildSystemProvider.Kind,
            testData: ShowCoveragePathTestData,
        ) async throws {
            let configuration = BuildConfiguration.debug
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

        // static let enableDisableCoverageWarningMessage = "warning: The '--enable-code-coverage' and '--disable-code-coverage' options have been deprecated.  Use '--enable-coverage' instead."
        // static let showCoveragePathWarningMessage = "The '--show-code-coverage-path' and '--show-codecov-path' options are deprecated.  Use '--show-coverage-path' instead."
        @Test(
            arguments: SupportedBuildSystemOnAllPlatforms, [
                (
                    argsUT: CoverageFormat.allCases.flatMap({ ["--coverage-format", $0.rawValue] }) + ["--show-coverage-path"],
                    expectedStderr: [
                        Basics.Diagnostic.showCoveragePathTextOutputWarning,
                        // "warning: The contents of this output are subject to change in the future. Use `--show-coverage-path json` if the output is required in a script.",
                    ],
                    id: "show path text with multiple coverage formats emits a warning",
                ),
                (
                    argsUT: ["--show-code-coverage-path", "--enable-code-coverage"],
                    expectedStderr: [
                        Basics.Diagnostic.deprecatedEnableDisableCoverage,
                        Basics.Diagnostic.deprecatedShowCodeCoveragePath,
                    ],
                    id: "Using deprecated --show-code-coverage-path and --enable-code-coverage arguments emits a warning for each argument",
                ),
                (
                    argsUT: ["--show-codecov-path"],
                    expectedStderr: [
                        Basics.Diagnostic.deprecatedShowCodeCoveragePath
                    ],
                    id: "Using deprecated --show-codecov-path argument emits a warning",
                ),
            ]
        )
        func deprecationWarningIsEmitted(
            buildSystem: BuildSystemProvider.Kind,
            tcData: (argsUT: [String], expectedStderr: [Diagnostic], id: String),
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
                    stderr.contains(htmlCommandRegex),
                    "Did not find HTML command",
                )
                #expect(
                    stderr.contains(jsonCommandRegex),
                    "Did not find JSON command",
                )
            }
        }

    }
}
