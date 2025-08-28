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
    // .serialized, // to limit the number of swift executable running.
    .tags(
        Tag.TestSize.large,
        Tag.Feature.Traits,
    ),
)
struct TraitTests {
    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8511"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8602"),
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func traits_whenNoFlagPassed(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue("Does not fail in some pipelines", isIntermittent: (ProcessInfo.hostOperatingSystem == .linux)) {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                buildSystem: buildSystem,
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            #expect(!stderr.contains("warning:"))
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
            ProcessInfo.hostOperatingSystem == .windows && CiEnvironment.runningInSmokeTestPipeline
            || (buildSystem == .swiftbuild && [.windows, .linux].contains(ProcessInfo.hostOperatingSystem))
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8511"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8602"),
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func traits_whenTraitUnification(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                extraArgs: ["--traits", "default,Package9,Package10"],
                buildSystem: buildSystem,
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            #expect(!stderr.contains("warning:"))
            #expect(stdout == """
            Package1Library1 trait1 enabled
            Package2Library1 trait2 enabled
            Package3Library1 trait3 enabled
            Package4Library1 trait1 disabled
            Package10Library1 trait1 enabled
            Package10Library1 trait2 enabled
            Package10Library1 trait1 enabled
            Package10Library1 trait2 enabled
            Package10Library2 has been included.
            DEFINE1 enabled
            DEFINE2 disabled
            DEFINE3 disabled

            """)
        }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && CiEnvironment.runningInSmokeTestPipeline || (buildSystem == .swiftbuild && [.windows, .linux].contains(ProcessInfo.hostOperatingSystem))
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8511"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8602"),
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func traits_whenTraitUnification_whenSecondTraitNotEnabled(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                extraArgs: ["--traits", "default,Package9"],
                buildSystem: buildSystem,
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            #expect(!stderr.contains("warning:"))
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
            ProcessInfo.hostOperatingSystem == .windows && CiEnvironment.runningInSmokeTestPipeline || (buildSystem == .swiftbuild && [.windows, .linux].contains(ProcessInfo.hostOperatingSystem))
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8511"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8602"),
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func traits_whenIndividualTraitsEnabled_andDefaultTraits(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                extraArgs: [
                    "--traits",
                    "default,Package5,Package7,BuildCondition3",
                ],
                buildSystem: buildSystem,
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            #expect(!stderr.contains("warning:"))
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
            ProcessInfo.hostOperatingSystem == .windows && CiEnvironment.runningInSmokeTestPipeline || (buildSystem == .swiftbuild && [.windows, .linux].contains(ProcessInfo.hostOperatingSystem))
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8511"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8602"),
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func traits_whenDefaultTraitsDisabled(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                extraArgs: ["--disable-default-traits"],
                buildSystem: buildSystem,
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            #expect(!stderr.contains("warning:"))
            #expect(stdout == """
            DEFINE1 disabled
            DEFINE2 disabled
            DEFINE3 disabled

            """)
        }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && CiEnvironment.runningInSmokeTestPipeline || (buildSystem == .swiftbuild && [.windows, .linux].contains(ProcessInfo.hostOperatingSystem))
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8511"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8602"),
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func traits_whenIndividualTraitsEnabled_andDefaultTraitsDisabled(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                extraArgs: ["--traits", "Package5,Package7"],
                buildSystem: buildSystem,
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            #expect(!stderr.contains("warning:"))
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
            ProcessInfo.hostOperatingSystem == .windows && CiEnvironment.runningInSmokeTestPipeline || (buildSystem == .swiftbuild && [.windows, .linux].contains(ProcessInfo.hostOperatingSystem))
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8511"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8602"),
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func traits_whenAllTraitsEnabled(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                extraArgs: ["--enable-all-traits"],
                buildSystem: buildSystem,
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            #expect(!stderr.contains("warning:"))
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
            Package10Library2 has been included.
            Package10Library2 has been included.
            DEFINE1 enabled
            DEFINE2 enabled
            DEFINE3 enabled

            """)
        }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && CiEnvironment.runningInSmokeTestPipeline || (buildSystem == .swiftbuild && [.windows, .linux].contains(ProcessInfo.hostOperatingSystem))
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8511"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8602"),
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func traits_whenAllTraitsEnabled_andDefaultTraitsDisabled(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Example"),
                "Example",
                extraArgs: [
                    "--enable-all-traits",
                    "--disable-default-traits",
                ],
                buildSystem: buildSystem,
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            #expect(!stderr.contains("warning:"))
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
            Package10Library2 has been included.
            Package10Library2 has been included.
            DEFINE1 enabled
            DEFINE2 enabled
            DEFINE3 enabled

            """)
        }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && CiEnvironment.runningInSmokeTestPipeline || (buildSystem == .swiftbuild && [.windows, .linux].contains(ProcessInfo.hostOperatingSystem))
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Package.DumpPackage,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func traits_dumpPackage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Traits") { fixturePath in
            let packageRoot = fixturePath.appending("Example")
            let (dumpOutput, _) = try await executeSwiftPackage(packageRoot, extraArgs: ["dump-package"], buildSystem: buildSystem)
            let json = try JSON(bytes: ByteString(encodingAsUTF8: dumpOutput))
            guard case .dictionary(let contents) = json else { Issue.record("unexpected result"); return }
            guard case .array(let traits)? = contents["traits"] else { Issue.record("unexpected result"); return }
            #expect(traits.count == 13)
        }
    }

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8511"),
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8602"),
        .tags(
            Tag.Feature.Command.Test,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func tests_whenNoFlagPassed(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, _) = try await executeSwiftTest(
                fixturePath.appending("Example"),
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
            ProcessInfo.hostOperatingSystem == .windows && CiEnvironment.runningInSmokeTestPipeline
            || (buildSystem == .swiftbuild && [.windows, .linux].contains(ProcessInfo.hostOperatingSystem))
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Test,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func tests_whenAllTraitsEnabled_andDefaultTraitsDisabled(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withKnownIssue {
            try await fixture(name: "Traits") { fixturePath in
                let (stdout, _) = try await executeSwiftTest(
                    fixturePath.appending("Example"),
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
                #expect(stdout.contains(expectedOut))
            }
        } when: {
            (buildSystem == .swiftbuild && [.windows, .linux].contains(ProcessInfo.hostOperatingSystem))
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Package.DumpSymbolGraph,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func packageDumpSymbolGraph_enablesAllTraits(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, _) = try await executeSwiftPackage(
                fixturePath.appending("Package10"),
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
    }

    @Test(
        .tags(
            Tag.Feature.Command.Package.Plugin,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func packagePluginGetSymbolGraph_enablesAllTraits(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Traits") { fixturePath in
            let (stdout, _) = try await executeSwiftPackage(
                fixturePath.appending("Package10"),
                extraArgs: ["plugin", "extract"],
                buildSystem: buildSystem,
            )
            let path = String(stdout.split(whereSeparator: \.isNewline).first!)
            let symbolGraph = try String(contentsOfFile: "\(path)/Package10Library1.symbols.json", encoding: .utf8)
            #expect(symbolGraph.contains("TypeGatedByPackage10Trait1"))
            #expect(symbolGraph.contains("TypeGatedByPackage10Trait2"))
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func packageDisablingDefaultsTrait_whenNoTraits(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Traits") { fixturePath in
            let error = await #expect(throws: SwiftPMError.self) {
                try await executeSwiftRun(
                   fixturePath.appending("DisablingEmptyDefaultsExample"),
                    "DisablingEmptyDefaultsExample",
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
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments:
        SupportedBuildSystemOnAllPlatforms,
        getTraitCombinations(
            ("ExtraTrait",
            """
            Package10Library2 has been included.
            DEFINE1 disabled
            DEFINE2 disabled
            DEFINE3 disabled
            
            """
            ),
            ("Package10",
            """
            Package10Library1 trait1 disabled
            Package10Library1 trait2 enabled
            Package10Library2 has been included.
            DEFINE1 disabled
            DEFINE2 disabled
            DEFINE3 disabled
            
            """
            ),
            ("ExtraTrait,Package10",
            """
            Package10Library1 trait1 disabled
            Package10Library1 trait2 enabled
            Package10Library2 has been included.
            Package10Library2 has been included.
            DEFINE1 disabled
            DEFINE2 disabled
            DEFINE3 disabled
            
            """
            )
        )
    )
    func traits_whenManyTraitsEnableTargetDependency(
        buildSystem: BuildSystemProvider.Kind,
        traits: TraitArgumentData
    ) async throws {
        try await withKnownIssue(
            """
            Linux: https://github.com/swiftlang/swift-package-manager/issues/8416,
            Windows: https://github.com/swiftlang/swift-build/issues/609
            """,
            isIntermittent: (ProcessInfo.hostOperatingSystem == .windows),
        ) {
            try await fixture(name: "Traits") { fixturePath in
                // We expect no warnings to be produced. Specifically no unused dependency warnings.
                let unusedDependencyRegex = try Regex("warning: '.*': dependency '.*' is not used by any target")

                let (stdout, stderr) = try await executeSwiftRun(
                    fixturePath.appending("Example"),
                    "Example",
                    extraArgs: ["--traits", traits.traitsArgument],
                    buildSystem: buildSystem,
                )
                #expect(!stderr.contains(unusedDependencyRegex))
                #expect(stdout == traits.expectedOutput)
            }
        } when: {
            (ProcessInfo.hostOperatingSystem == .windows && (CiEnvironment.runningInSmokeTestPipeline || buildSystem == .swiftbuild))
            || (buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux && CiEnvironment.runningInSelfHostedPipeline)
        }
    }
}
