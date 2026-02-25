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
        .SWBINTTODO("Test failed because of missing plugin support in the PIF builder. This can be reinvestigated after the support is there."),
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
        try await withKnownIssue(isIntermittent: true) {
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
        .SWBINTTODO("Test failed because of missing plugin support in the PIF builder. This can be reinvestigated after the support is there."),
        .IssueWindowsCannotSaveAttachment,
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
                try await withKnownIssue(isIntermittent: true) {
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
                // || (
                //     // error: failed to load coverage: '<scratch-path>/arm64-apple-macosx/Products/Release/SimpleTests.xctest/Contents/MacOS/SimpleTests': `-arch` specifier is invalid or missing for universal binary
                //     buildData.buildSystem == .swiftbuild && buildData.config == .release)
                // || (
                //     // error: /private/var/folders/9j/994sp90x6y3232rzrl9h_z4w0000gn/T/Miscellaneous_TestDiscovery_Simple.3EzR9a/Miscellaneous_TestDiscovery_Simple/Tests/SimpleTests/SwiftTests.swift:2:18 Unable to find module dependency: 'Simple'
                //     // @testable import Simple
                //     //                  ^
                //     // error: SwiftDriver SimpleTests normal arm64 com.apple.xcode.tools.swift.compiler failed with a nonzero exit code. Command line:     cd /private/var/folders/9j/994sp90x6y3232rzrl9h_z4w0000gn/T/Miscellaneous
                //     buildData.buildSystem == .native && buildData.config == .release)
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
        arguments: SupportedBuildSystemOnAllPlatforms,
        [
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
            let coveragePathString = try await executeSwiftTest(
                path,
                configuration: config,
                extraArgs: [
                    "--show-coverage-path"
                ] + commonCoverageArgs,
                throwIfCommandFails: true,
                buildSystem: buildSystem,
            ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let coveragePath = try AbsolutePath(validating: coveragePathString)
            try #require(!localFileSystem.exists(coveragePath))

            // WHEN we test with coverage enabled
            try await withKnownIssue(isIntermittent: true) {
                try await executeSwiftTest(
                    path,
                    configuration: config,
                    extraArgs: [
                        "--enable-code-coverage"
                    ] + commonCoverageArgs,
                    throwIfCommandFails: true,
                    buildSystem: buildSystem,
                )

                // THEN we expect the file to exists
                #expect(localFileSystem.exists(coveragePath))
            } when: {
                (buildSystem == .swiftbuild
                    && [.windows, .linux].contains(ProcessInfo.hostOperatingSystem))
            }
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
            try withKnownIssue {
                let html = try #require(reportData.html)
                #expect(localFileSystem.exists(html))
                let json = try #require(reportData.json)
                #expect(localFileSystem.exists(json))
            } when: {
                ProcessInfo.hostOperatingSystem == .linux && buildSystem == .swiftbuild && configuration == .debug
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
        // let responseFilePathComponents = [
        //     ".swiftpm",
        //     "configuration",
        //     "coverage.html.report.args.txt",
        // ]

        // @Test(
        //     .tags(
        //         .Feature.Command.Test,
        //     ),
        //     arguments: SupportedBuildSystemOnAllPlatforms,
        //     [
        //         true, false,
        //     ]
        // )
        // func htmlReportOutputDirectoryInResponseFileOverrideTheDefaultLocation(
        //     buildSystem: BuildSystemProvider.Kind,
        //     isResponseFileOutputAbsolutePath: Bool,
        // ) async throws {
        //     let configuration = BuildConfiguration.debug
        //     // Verify the output directory argument specified in the response file override the default location.
        //     try await fixture(name: "Coverage/Simple") { fixturePath in
        //         let responseFilePath = fixturePath.appending(components: responseFilePathComponents)
        //         let responseFileContent: String
        //         let expectedOutputPath: String
        //         if isResponseFileOutputAbsolutePath {
        //             responseFileContent = "--output-dir /foo"
        //             expectedOutputPath = AbsolutePath("/foo").pathString
        //         } else {
        //             responseFileContent = "--output-dir ./foo"
        //             expectedOutputPath = fixturePath.appending("foo").pathString
        //         }

        //         try localFileSystem.createDirectory(responseFilePath.parentDirectory, recursive: true)
        //         try localFileSystem.writeFileContents(responseFilePath, string: responseFileContent)

        //         let (stdout, stderr) = try await executeSwiftTest(
        //             fixturePath,
        //             configuration: configuration,
        //             extraArgs: [
        //                 "--show-coverage-path",
        //                 "--coverage-format",
        //                 "html",
        //             ],
        //             buildSystem: buildSystem,
        //         )
        //         let actualOutput = stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        //         #expect(actualOutput == expectedOutputPath, "stderr: \(stderr)")
        //     }
        // }

        // @Test(
        //     .tags(
        //         .Feature.Command.Test,
        //     ),
        //     arguments: SupportedBuildSystemOnAllPlatforms,
        // )
        // func existenceOfResponseFileWithNotOutputDirectorySpecifiedUsedTheDefaultLocation(
        //     buildSystem: BuildSystemProvider.Kind,
        // ) async throws {
        //     let configuration = BuildConfiguration.debug
        //     // Verify the output directory argument specified in the response file override the default location.
        //     try await fixture(name: "Coverage/Simple") { fixturePath in
        //         let responseFilePath = fixturePath.appending(components: responseFilePathComponents)
        //         let responseFileContent = "--tab-size=10"

        //         try localFileSystem.createDirectory(responseFilePath.parentDirectory, recursive: true)
        //         try localFileSystem.writeFileContents(responseFilePath, string: responseFileContent)

        //         let (stdout, _) = try await executeSwiftTest(
        //             fixturePath,
        //             configuration: configuration,
        //             extraArgs: [
        //                 "--show-coverage-path",
        //                 "--coverage-format",
        //                 "html",
        //             ],
        //             buildSystem: buildSystem,
        //         )
        //         let actualOutput = stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        //         #expect(actualOutput.contains(fixturePath.pathString))
        //     }
        // }

        // @Test(
        //     arguments: SupportedBuildSystemOnAllPlatforms,
        // )
        // func htmlExistenceOfReportResponseFileHasFileOnTheCommandLine(
        //     buildSystem: BuildSystemProvider.Kind,
        // ) async throws {
        //     // Verify the arguments specified in the response file are used.
        //     let config = BuildConfiguration.debug
        //     try await withKnownIssue {
        //     try await fixture(name: "Coverage/Simple") { fixturePath in
        //         let responseFilePath = fixturePath.appending(components: responseFilePathComponents)

        //         try localFileSystem.writeFileContents(responseFilePath, string: "")
        //         expectFileExists(at: responseFilePath)
        //         let (_, stderr) = try await executeSwiftTest(
        //             fixturePath,
        //             configuration: config,
        //             extraArgs: [
        //                 "--very-verbose"  // this emits the coverage commmands
        //             ] + commonHtmlCoverageArgs,
        //             throwIfCommandFails: false,
        //             buildSystem: buildSystem,
        //         )
        //         let responseFileArgument = try Regex("@.*\(responseFilePath)")
        //         let contains = stderr.components(separatedBy: .newlines).filter {
        //             $0.contains("llvm-cov show") && $0.contains(responseFileArgument)  //$0.contains("@\(responseFilePath)")
        //         }
        //         #expect(contains.count >= 1)
        //     }
        //     } when: {
        //         ProcessInfo.hostOperatingSystem == .linux && buildSystem == .swiftbuild  // TO Fix before merge
        //     }
        // }
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

        @Test(
            arguments: SupportedBuildSystemOnAllPlatforms, [
                (
                    argsUT: CoverageFormat.allCases.flatMap({ ["--coverage-format", $0.rawValue] }) + ["--show-coverage-path"],
                    expectedStderr: [
                        "warning: The contents of this output are subject to change in the future. Use `--show-coverage-path json` if the output is required in a script.",
                    ],
                    id: "show path text with multiple coverage formats emits a warning",
                ),
                (
                    argsUT: ["--show-code-coverage-path", "--enable-code-coverage"],
                    expectedStderr: [
                        "warning: The '--enable-code-coverage' option has been deprecated.  Use '--enable-coverage' instead.",
                        "warning: The '--show-code-coverage-path' and '--show-codecov-path' options are deprecated.  Use '--show-coverage-path' instead.",
                    ],
                    id: "Using deprecated --show-code-coverage-path and --enable-code-coverage arguments emits a warning for each argument",
                ),
                (
                    argsUT: ["--show-codecov-path"],
                    expectedStderr: [
                        "warning: The '--show-code-coverage-path' and '--show-codecov-path' options are deprecated.  Use '--show-coverage-path' instead.",
                    ],
                    id: "Using deprecated --show-codecov-path argument emits a warning",
                ),
            ]
        )
        func showPathTextWithMultipleCoverageFormatSelectedEmitsAWarning(
            buildSystem: BuildSystemProvider.Kind,
            tcData: (argsUT: [String], expectedStderr: [String], id: String),
        ) async throws {
            let config = BuildConfiguration.debug
            try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
                let (_, stderr) = try await executeSwiftTest(
                    fixturePath,
                    configuration: config,
                    extraArgs: tcData.argsUT,
                    buildSystem: buildSystem,
                )

                for line in tcData.expectedStderr {
                    #expect(
                        stderr.contains(line),
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
            xcovData: (XcodeArgs: [String], expectedHtmlReportCmd: String, expectedJsonReportCmd: String),
        ) async throws {
            let config = BuildConfiguration.debug
            try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
                let (stdout, stderr) = try await executeSwiftTest(
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
                    Xcov: xcovData.XcodeArgs,
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
