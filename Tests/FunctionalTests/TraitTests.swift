//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

import DriverSupport
import PackageModel
import struct TSCBasic.ByteString
import enum TSCBasic.JSON
import struct SPMBuildCore.BuildSystemProvider
import Testing
import _InternalTestSupport

@Suite(
    .tags(
        Tag.TestSize.large,
        Tag.Feature.Traits,
    ),
)
struct TraitTests {
    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8511"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8602"),
        .IssueSwiftBuildLinuxRunnable,
        .IssueProductTypeForObjectLibraries,
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func traits_whenNoFlagPassed(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue("""
        Linux: https://github.com/swiftlang/swift-package-manager/issues/8416
        """, isIntermittent: (ProcessInfo.hostOperatingSystem == .linux) || (ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild)) {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                configuration: configuration,
                buildSystem: buildSystem,
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            let unusedDependencyRegex = try Regex("warning: '.*': dependency '.*' is not used by any target")
            #expect(!stderr.contains(unusedDependencyRegex))
            #expect(stdout == """
            Package1Library1 trait1 enabled
            Package2Library1 trait2 enabled
            Package3Library1 trait3 enabled
            Package4Library1 trait1 disabled
            DEFINE1 enabled
            DEFINE2 disabled
            DEFINE3 disabled

            """)
        }
        } when: {
            (ProcessInfo.hostOperatingSystem == .windows && (CiEnvironment.runningInSmokeTestPipeline || buildSystem == .swiftbuild))
            || (buildSystem == .swiftbuild && [.linux, .windows].contains(ProcessInfo.hostOperatingSystem))
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8511"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8602"),
        .IssueSwiftBuildLinuxRunnable,
        .IssueProductTypeForObjectLibraries,
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func traits_whenTraitUnification(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue(
            """
            Linux: https://github.com/swiftlang/swift-package-manager/issues/8416
            Windows: "https://github.com/swiftlang/swift-build/issues/609"
            """,
            isIntermittent: (ProcessInfo.hostOperatingSystem == .windows),
        ) {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                configuration: configuration,
                extraArgs: ["--traits", "default,Package9,Package10"],
                buildSystem: buildSystem,
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            let unusedDependencyRegex = try Regex("warning: '.*': dependency '.*' is not used by any target")
            #expect(!stderr.contains(unusedDependencyRegex))
            #expect(stdout == """
            Package1Library1 trait1 enabled
            Package2Library1 trait2 enabled
            Package3Library1 trait3 enabled
            Package4Library1 trait1 disabled
            Package10Library1 trait1 enabled
            Package10Library1 trait2 enabled
            Package10Library1 trait1 enabled
            Package10Library1 trait2 enabled
            DEFINE1 enabled
            DEFINE2 disabled
            DEFINE3 disabled

            """)
        }
        } when: {
            (ProcessInfo.hostOperatingSystem == .windows && (CiEnvironment.runningInSmokeTestPipeline || buildSystem == .swiftbuild))
            || (buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux && CiEnvironment.runningInSelfHostedPipeline)
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8511"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8602"),
        .IssueSwiftBuildLinuxRunnable,
        .IssueProductTypeForObjectLibraries,
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func traits_whenTraitUnification_whenSecondTraitNotEnabled(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue(
            """
            Linux: https://github.com/swiftlang/swift-package-manager/issues/8416,
            Windows: https://github.com/swiftlang/swift-build/issues/609
            """,
            isIntermittent: (ProcessInfo.hostOperatingSystem == .windows),
        ) {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                configuration: configuration,
                extraArgs: ["--traits", "default,Package9"],
                buildSystem: buildSystem,
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            let unusedDependencyRegex = try Regex("warning: '.*': dependency '.*' is not used by any target")
            #expect(!stderr.contains(unusedDependencyRegex))
            #expect(stdout == """
            Package1Library1 trait1 enabled
            Package2Library1 trait2 enabled
            Package3Library1 trait3 enabled
            Package4Library1 trait1 disabled
            Package10Library1 trait1 enabled
            Package10Library1 trait2 enabled
            DEFINE1 enabled
            DEFINE2 disabled
            DEFINE3 disabled

            """)
        }
        } when: {
            (ProcessInfo.hostOperatingSystem == .windows && (CiEnvironment.runningInSmokeTestPipeline || buildSystem == .swiftbuild))
            || (buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux && CiEnvironment.runningInSelfHostedPipeline)
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8511"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8602"),
        .IssueSwiftBuildLinuxRunnable,
        .IssueProductTypeForObjectLibraries,
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func traits_whenIndividualTraitsEnabled_andDefaultTraits(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue(
            """
            Linux: https://github.com/swiftlang/swift-package-manager/issues/8416,
            Windows: https://github.com/swiftlang/swift-build/issues/609
            """,
            isIntermittent: (ProcessInfo.hostOperatingSystem == .windows),
        ) {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                configuration: configuration,
                extraArgs: [
                    "--traits",
                    "default,Package5,Package7,BuildCondition3",
                ],
                buildSystem: buildSystem,
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            let unusedDependencyRegex = try Regex("warning: '.*': dependency '.*' is not used by any target")
            #expect(!stderr.contains(unusedDependencyRegex))
            #expect(stdout == """
            Package1Library1 trait1 enabled
            Package2Library1 trait2 enabled
            Package3Library1 trait3 enabled
            Package4Library1 trait1 disabled
            Package5Library1 trait1 enabled
            Package6Library1 trait1 enabled
            Package7Library1 trait1 disabled
            DEFINE1 enabled
            DEFINE2 disabled
            DEFINE3 enabled

            """)
        }
        } when: {
            (ProcessInfo.hostOperatingSystem == .windows && (CiEnvironment.runningInSmokeTestPipeline || buildSystem == .swiftbuild))
            || (buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux && CiEnvironment.runningInSelfHostedPipeline)
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8511"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8602"),
        .IssueSwiftBuildLinuxRunnable,
        .IssueProductTypeForObjectLibraries,
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func traits_whenDefaultTraitsDisabled(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue("""
        Linux: https://github.com/swiftlang/swift-package-manager/issues/8416,
        """,
        isIntermittent: (ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild)) {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                configuration: configuration,
                extraArgs: ["--disable-default-traits"],
                buildSystem: buildSystem,
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            let unusedDependencyRegex = try Regex("warning: '.*': dependency '.*' is not used by any target")
            #expect(!stderr.contains(unusedDependencyRegex))
            #expect(stdout == """
            DEFINE1 disabled
            DEFINE2 disabled
            DEFINE3 disabled

            """)
        }
        } when: {
            (ProcessInfo.hostOperatingSystem == .windows && (CiEnvironment.runningInSmokeTestPipeline || buildSystem == .swiftbuild))
            || (buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux && CiEnvironment.runningInSelfHostedPipeline)
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8511"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8602"),
        .IssueSwiftBuildLinuxRunnable,
        .IssueProductTypeForObjectLibraries,
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func traits_whenIndividualTraitsEnabled_andDefaultTraitsDisabled(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue("""
            Linux: https://github.com/swiftlang/swift-package-manager/issues/8416,
            Windows: https://github.com/swiftlang/swift-build/issues/609
            """,
            isIntermittent: (ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild),
        ) {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                configuration: configuration,
                extraArgs: ["--traits", "Package5,Package7"],
                buildSystem: buildSystem,
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            let unusedDependencyRegex = try Regex("warning: '.*': dependency '.*' is not used by any target")
            #expect(!stderr.contains(unusedDependencyRegex))
            #expect(stdout == """
            Package5Library1 trait1 enabled
            Package6Library1 trait1 enabled
            Package7Library1 trait1 disabled
            DEFINE1 disabled
            DEFINE2 disabled
            DEFINE3 disabled

            """)
        }
        } when: {
            (ProcessInfo.hostOperatingSystem == .windows && (CiEnvironment.runningInSmokeTestPipeline || buildSystem == .swiftbuild))
            || (buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux && CiEnvironment.runningInSelfHostedPipeline)
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8511"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8602"),
        .IssueSwiftBuildLinuxRunnable,
        .IssueProductTypeForObjectLibraries,
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func traits_whenAllTraitsEnabled(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue(
            """
            Linux: https://github.com/swiftlang/swift-package-manager/issues/8416,
            Windows: https://github.com/swiftlang/swift-build/issues/609
            """,
            isIntermittent: (ProcessInfo.hostOperatingSystem == .windows),
        ) {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                configuration: configuration,
                extraArgs: ["--enable-all-traits"],
                buildSystem: buildSystem,
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            let unusedDependencyRegex = try Regex("warning: '.*': dependency '.*' is not used by any target")
            #expect(!stderr.contains(unusedDependencyRegex))
            #expect(stdout == """
            Package1Library1 trait1 enabled
            Package2Library1 trait2 enabled
            Package3Library1 trait3 enabled
            Package4Library1 trait1 disabled
            Package5Library1 trait1 enabled
            Package6Library1 trait1 enabled
            Package7Library1 trait1 disabled
            Package10Library1 trait1 enabled
            Package10Library1 trait2 enabled
            Package10Library1 trait1 enabled
            Package10Library1 trait2 enabled
            DEFINE1 enabled
            DEFINE2 enabled
            DEFINE3 enabled

            """)
        }
        } when: {
            (ProcessInfo.hostOperatingSystem == .windows && (CiEnvironment.runningInSmokeTestPipeline || buildSystem == .swiftbuild))
            || (buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux && CiEnvironment.runningInSelfHostedPipeline)
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8511"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8602"),
        .IssueSwiftBuildLinuxRunnable,
        .IssueProductTypeForObjectLibraries,
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func traits_whenAllTraitsEnabled_andDefaultTraitsDisabled(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue(
            """
            Linux: https://github.com/swiftlang/swift-package-manager/issues/8416,
            Windows: https://github.com/swiftlang/swift-build/issues/609
            """,
            isIntermittent: (ProcessInfo.hostOperatingSystem == .windows)
        ) {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                configuration: configuration,
                extraArgs: [
                    "--enable-all-traits",
                    "--disable-default-traits",
                ],
                buildSystem: buildSystem,
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            let unusedDependencyRegex = try Regex("warning: '.*': dependency '.*' is not used by any target")
            #expect(!stderr.contains(unusedDependencyRegex))
            #expect(stdout == """
            Package1Library1 trait1 enabled
            Package2Library1 trait2 enabled
            Package3Library1 trait3 enabled
            Package4Library1 trait1 disabled
            Package5Library1 trait1 enabled
            Package6Library1 trait1 enabled
            Package7Library1 trait1 disabled
            Package10Library1 trait1 enabled
            Package10Library1 trait2 enabled
            Package10Library1 trait1 enabled
            Package10Library1 trait2 enabled
            DEFINE1 enabled
            DEFINE2 enabled
            DEFINE3 enabled

            """)
        }
        } when: {
            (ProcessInfo.hostOperatingSystem == .windows && (CiEnvironment.runningInSmokeTestPipeline || buildSystem == .swiftbuild))
            || (buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux && CiEnvironment.runningInSelfHostedPipeline)
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Package.DumpPackage,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func traits_dumpPackage(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await fixture(name: "Traits") { fixturePath in
            let packageRoot = fixturePath.appending("Example")
            let (dumpOutput, _) = try await executeSwiftPackage(
                packageRoot,
                configuration: configuration,
                extraArgs: ["dump-package"],
                buildSystem: buildSystem,
            )
            let json = try JSON(bytes: ByteString(encodingAsUTF8: dumpOutput))
            guard case .dictionary(let contents) = json else { Issue.record("unexpected result"); return }
            guard case .array(let traits)? = contents["traits"] else { Issue.record("unexpected result"); return }
            #expect(traits.count == 12)
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8511"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8602"),
        .tags(
            Tag.Feature.Command.Test,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func tests_whenNoFlagPassed(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, _) = try await executeSwiftTest(
                fixturePath.appending("Example"),
                configuration: configuration,
                buildSystem: buildSystem,
            )
            let expectedOut = """
            Package1Library1 trait1 enabled
            Package2Library1 trait2 enabled
            Package3Library1 trait3 enabled
            Package4Library1 trait1 disabled
            DEFINE1 enabled
            DEFINE2 disabled
            DEFINE3 disabled

            """
            #expect(stdout.contains(expectedOut))
        }
        } when: {
            (buildSystem == .swiftbuild && [.windows].contains(ProcessInfo.hostOperatingSystem))
        }
    }

    @Test(
        .IssueProductTypeForObjectLibraries,
        .tags(
            Tag.Feature.Command.Test,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func tests_whenAllTraitsEnabled_andDefaultTraitsDisabled(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue(
            """
            Windows: "https://github.com/swiftlang/swift-build/issues/609"
            """,
            isIntermittent: (ProcessInfo.hostOperatingSystem == .windows),
        ) {
            try await fixture(name: "Traits") { fixturePath in
                let (stdout, stderr) = try await executeSwiftTest(
                    fixturePath.appending("Example"),
                    configuration: configuration,
                    extraArgs: [
                        "--enable-all-traits",
                        "--disable-default-traits",
                    ],
                    buildSystem: buildSystem,
                )
                let expectedOut = """
                Package1Library1 trait1 enabled
                Package2Library1 trait2 enabled
                Package3Library1 trait3 enabled
                Package4Library1 trait1 disabled
                Package5Library1 trait1 enabled
                Package6Library1 trait1 enabled
                Package7Library1 trait1 disabled
                Package10Library1 trait1 enabled
                Package10Library1 trait2 enabled
                Package10Library1 trait1 enabled
                Package10Library1 trait2 enabled
                DEFINE1 enabled
                DEFINE2 enabled
                DEFINE3 enabled

                """
                #expect(stdout.contains(expectedOut), "got stdout: '\(stdout)'\nstderr: '\(stderr)'")
            }
        } when: {
            buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Package.DumpSymbolGraph,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func packageDumpSymbolGraph_enablesAllTraits(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue(isIntermittent: true, {
            try await fixture(name: "Traits") { fixturePath in
                let (stdout, _) = try await executeSwiftPackage(
                    fixturePath.appending("Package10"),
                    configuration: configuration,
                    extraArgs: ["dump-symbol-graph"],
                    buildSystem: buildSystem,
                )
                let optionalPath = stdout
                    .lazy
                    .split(whereSeparator: \.isNewline)
                    .first { String($0).hasPrefix("Files written to ") }?
                    .dropFirst(17)

                let path = try String(#require(optionalPath))
                let symbolGraph = try String(contentsOfFile: "\(path)/Package10Library1.symbols.json", encoding: .utf8)
                #expect(symbolGraph.contains("TypeGatedByPackage10Trait1"))
                #expect(symbolGraph.contains("TypeGatedByPackage10Trait2"))
            }
        }, when: {
            ProcessInfo.hostOperatingSystem == .windows
        })
    }

    @Test(
        .IssueProductTypeForObjectLibraries,
        .tags(
            Tag.Feature.Command.Package.Plugin,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func packagePluginGetSymbolGraph_enablesAllTraits(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
        ) async throws {
        try await fixture(name: "Traits") { fixturePath in
            // The swiftbuild build system doesn't yet have the ability for command plugins to request symbol graphs
             try await withKnownIssue(
                "https://github.com/swiftlang/swift-build/issues/609",
                isIntermittent: true,
            ) {
                let (stdout, _) = try await executeSwiftPackage(
                    fixturePath.appending("Package10"),
                    configuration: configuration,
                    extraArgs: ["plugin", "extract"],
                    buildSystem: buildSystem,
                )
                let path = String(stdout.split(whereSeparator: \.isNewline).first!)
                let symbolGraph = try String(contentsOfFile: "\(path)/Package10Library1.symbols.json", encoding: .utf8)
                #expect(symbolGraph.contains("TypeGatedByPackage10Trait1"))
                #expect(symbolGraph.contains("TypeGatedByPackage10Trait2"))
            } when: {
               buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows
            }
        }
    }

    @Test(
        .IssueSwiftBuildLinuxRunnable,
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func packageDisablingDefaultsTrait_whenNoTraits(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await fixture(name: "Traits") { fixturePath in
            try await withKnownIssue("""
            Linux: https://github.com/swiftlang/swift-package-manager/issues/8416,
            """,
            isIntermittent: true,
            ) {
                let error = await #expect(throws: SwiftPMError.self) {
                    try await executeSwiftRun(
                    fixturePath.appending("DisablingEmptyDefaultsExample"),
                        "DisablingEmptyDefaultsExample",
                        configuration: configuration,
                        buildSystem: buildSystem,
                    )
                }

                guard case SwiftPMError.executionFailure(_, _, let stderr) = try #require(error) else {
                    Issue.record("Incorrect error was raised.")
                    return
                }

                let expectedErr = """
                    error: Disabled default traits by package 'disablingemptydefaultsexample' (DisablingEmptyDefaultsExample) on package 'package11' (Package11) that declares no traits. This is prohibited to allow packages to adopt traits initially without causing an API break.

                    """
                #expect(stderr.contains(expectedErr))
            } when: {
                buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux
            }
        }
    }
}
