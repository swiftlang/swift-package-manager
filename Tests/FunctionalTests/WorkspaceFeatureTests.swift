//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import PackageLoading
import SourceControl
import Testing
import _InternalTestSupport
import enum PackageModel.BuildConfiguration
import struct PackageModel.PackageIdentity

@_spi(SwiftPMInternal) import Commands
@_spi(SwiftPMInternal) import CoreCommands
@_spi(SwiftPMInternal) import SPMBuildCore
import struct SPMBuildCore.BuildSystemProvider

@Suite(
    .tags(
        .TestSize.large,
        .FunctionalArea.WorkspaceManiest,
    ),
)
struct WorkspaceFeatureTests {
    @Test(
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func s01_minimalTwoMembersBuildsAtRoot(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S01_MinimalTwoMembers") { fixturePath in
            try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                buildSystem: buildSystem,
            )

            let binPath = try await getBinPath(
                fixturePath,
                configuration: .debug,
                buildSystem: buildSystem,
            )

            let libAModule: AbsolutePath
            let libBModule: AbsolutePath
            switch buildSystem {
            case .native:
                libAModule = binPath.appending(components: "Modules", "LibA.swiftmodule")
                libBModule = binPath.appending(components: "Modules", "LibB.swiftmodule")
            case .swiftbuild, .xcode:
                libAModule = binPath.appending("LibA.swiftmodule")
                libBModule = binPath.appending("LibB.swiftmodule")
            }
            expectFileExists(at: libAModule)
            expectFileExists(at: libBModule)
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func s02_memberToMemberDependencyBuildsAndRuns(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S02_MemberToMemberDep") { fixturePath in
            try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                buildSystem: buildSystem,
            )

            let binPath = try await getBinPath(
                fixturePath,
                configuration: .debug,
                buildSystem: buildSystem,
            )
            let appBinary = binPath.appending("app")
            expectFileExists(at: appBinary)

            let output = try await AsyncProcess.checkNonZeroExit(
                args: appBinary.pathString,
            ).withSwiftLineEnding
            #expect(output == "Hello from lib-a\n")
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func s03_inheritedExternalDepBuildsAndRuns(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S03_InheritedExternalDep") { fixturePath in
            let (_, stderr) = try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                buildSystem: buildSystem,
            )

            // Bug A regression: `some-lib` IS inherited by lib-a via
            // `.package(workspaceInherited:)`, so the workspace audit
            // must not report it as unused. Prior to the augmentation
            // approach, the audit ran post-rewrite and saw no
            // `.workspaceInherited` entries — falsely flagging every
            // workspace-level dep as unused.
            #expect(
                !stderr.contains("workspace dependency 'some-lib' is declared in Workspace.swift but not inherited"),
                "spurious 'unused workspace dependency' warning for 'some-lib': \(stderr)",
            )

            let binPath = try await getBinPath(
                fixturePath,
                configuration: .debug,
                buildSystem: buildSystem,
            )
            let appBinary = binPath.appending("app")
            expectFileExists(at: appBinary)

            let output = try await AsyncProcess.checkNonZeroExit(
                args: appBinary.pathString,
            ).withSwiftLineEnding
            #expect(output == "app says: Hello from some-lib\n")
        }
    }

    /// `swift build` invoked from inside a workspace member's
    /// directory should build ONLY that member's products and their
    /// transitive dependencies, not sibling members that the focused
    /// member doesn't depend on.
    ///
    /// Fixture layout:
    ///   - `packages/app` — executable, inherits `some-lib` from workspace
    ///   - `packages/lib-a` — library, unrelated to `app`
    ///   - `external/some-lib` — workspace-declared external dependency
    ///
    /// Invocation from inside `packages/app` (via `--package-path`) must
    /// build `app` (+ `SomeLib` transitively) but NOT `lib-a`.
    ///
    /// Restricted to the Swift Build build system: the workspace-member
    /// focus feature is only supported there. Native/XCBuild paths would
    /// be rejected by `SwiftCommandState` with a hard error.
    ///
    /// TODO(Slice 5): add a nested-`.workspaceInherited` variant where
    /// `app` depends on a sibling member `lib-a` via `.workspaceMember`,
    /// and `lib-a` itself inherits `some-lib` via `.workspaceInherited`.
    /// This exercises the container-side rewrite for a *transitive*
    /// workspace member (not just the roots that go through
    /// `loadRootManifests`). The unit test
    /// `fileSystemContainer_forWorkspaceMember_rewritesInheritedDep`
    /// already pins the behavior; the missing piece is the end-to-end
    /// combined case. Slice 5 (`--package <identity>`) will naturally
    /// extend the fixture into a two-tier dep chain.
    @Test(
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s04_buildFromInsideMemberBuildsOnlyThatMember(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S04_CwdInsideMember") { fixturePath in
            let workspaceRoot = fixturePath
            let memberPath = workspaceRoot.appending(components: "packages", "app")

            try await executeSwiftBuild(
                memberPath,
                configuration: .debug,
                buildSystem: buildSystem,
            )

            // The workspace's `.build/` lives at the workspace root
            // (not inside the member the command was invoked from), so
            // all members share one dep cache and one Package.resolved.
            expectDirectoryExists(at: workspaceRoot.appending(".build"))
            // Swift Build's separate indexer step may still deposit an
            // `index-build/` subdirectory inside the member — that's an
            // orthogonal concern to workspace scratch-directory routing
            // and not part of the workspace `.build/` layout. Guarded
            // against here so the assertion tracks compilation output,
            // not indexing artefacts.
            let memberBuildOutputs = memberPath.appending(components: ".build", "out")
            expectDirectoryDoesNotExist(at: memberBuildOutputs)

            let binPath = try await getBinPath(
                memberPath,
                configuration: .debug,
                buildSystem: buildSystem,
            )

            // `binPath` points inside the workspace-root `.build/`.
            // On macOS the temp directory is symlinked (`/var/folders`
            // → `/private/var/folders`); the fixture path and the
            // build system report paths through different symlink
            // sides, so compare after resolving both to their real
            // canonical form.
            let resolvedBinPath = try resolveSymlinks(binPath)
            let resolvedWorkspaceBuild = try resolveSymlinks(
                workspaceRoot.appending(".build"),
            )
            #expect(
                resolvedBinPath.pathString.hasPrefix(resolvedWorkspaceBuild.pathString),
                "expected bin path under workspace root .build, got \(binPath) (resolved: \(resolvedBinPath)), workspace root .build resolved: \(resolvedWorkspaceBuild)",
            )

            // `app` was built.
            expectFileExists(at: binPath.appending("app"))

            // `lib-a` is unrelated to `app` — its swiftmodule must NOT
            // be produced when focus narrows the build to the app
            // member.
            expectFileDoesNotExist(at: binPath.appending("LibA.swiftmodule"))
        }
    }

    /// `--package X` from the workspace root builds only member X's
    /// products (and its transitive deps), even when the caller isn't
    /// inside any member. This is the "explicit selector, no CWD-based
    /// focus" path.
    @Test(
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s05_packageSelectorFromRoot_buildsSelectedMemberOnly(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S05_PackageSelector") { fixturePath in
            try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                extraArgs: ["--package", "lib-b"],
                buildSystem: buildSystem,
            )

            let binPath = try await getBinPath(
                fixturePath,
                configuration: .debug,
                extraArgs: ["--package", "lib-b"],
                buildSystem: buildSystem,
            )

            expectFileExists(at: binPath.appending("LibB.swiftmodule"))
            // Unrelated members did not build.
            expectFileDoesNotExist(at: binPath.appending("app"))
            expectFileDoesNotExist(at: binPath.appending("LibA.swiftmodule"))
        }
    }

    /// `--package X --product Y` builds product `Y` scoped to member
    /// `X`. Exercises the composition path where the selector narrows
    /// which member's product namespace `--product` resolves against —
    /// the case that motivates supporting both flags together rather
    /// than treating them as mutually exclusive.
    ///
    /// `lib-b` exposes two products (`LibB` + `LibBExtra`); asserting
    /// that only `LibB.swiftmodule` is produced proves `--product`
    /// narrows WITHIN the selected member, not just across members.
    @Test(
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s05_packageSelectorWithProduct_buildsSelectedProductFromSelectedMember(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S05_PackageSelector") { fixturePath in
            try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                extraArgs: ["--package", "lib-b", "--product", "LibB"],
                buildSystem: buildSystem,
            )

            let binPath = try await getBinPath(
                fixturePath,
                configuration: .debug,
                extraArgs: ["--package", "lib-b", "--product", "LibB"],
                buildSystem: buildSystem,
            )

            expectFileExists(at: binPath.appending("LibB.swiftmodule"))
            // Sibling products in the same member must not be built.
            expectFileDoesNotExist(at: binPath.appending("LibBExtra.swiftmodule"))
            // Sibling members' products must not be built.
            expectFileDoesNotExist(at: binPath.appending("app"))
            expectFileDoesNotExist(at: binPath.appending("LibA.swiftmodule"))
        }
    }

    /// `--package X --product Y` where member `X` exists but product
    /// `Y` doesn't emits the `unknownProductInMember` diagnostic
    /// listing the member's known products. Guards the SwiftBuild
    /// dispatch path from silently falling through to an opaque
    /// downstream failure.
    @Test(
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s05_packageSelectorWithInvalidProduct_errorsWithHelpfulMessage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S05_PackageSelector") { fixturePath in
            let (_, stderr) = try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                extraArgs: ["--package", "lib-b", "--product", "DoesNotExist"],
                buildSystem: buildSystem,
                throwIfCommandFails: false,
            )

            let expected = Basics.Diagnostic.unknownProductInMember(
                requested: "DoesNotExist",
                package: .plain("lib-b"),
                known: [.plain("LibB"), .plain("LibBExtra")],
            )
            #expect(
                stderr.contains(expected.message),
                "expected unknown-product-in-member diagnostic; got: \(stderr)",
            )
        }
    }

    /// `--package X --target Y` builds target `Y` scoped to member `X`.
    /// Mirrors the `--product` composition path for target selection.
    @Test(
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s05_packageSelectorWithTarget_buildsSelectedTargetFromSelectedMember(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S05_PackageSelector") { fixturePath in
            try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                extraArgs: ["--package", "lib-b", "--target", "LibB"],
                buildSystem: buildSystem,
            )

            let binPath = try await getBinPath(
                fixturePath,
                configuration: .debug,
                extraArgs: ["--package", "lib-b", "--target", "LibB"],
                buildSystem: buildSystem,
            )

            expectFileExists(at: binPath.appending("LibB.swiftmodule"))
            // Sibling targets in the same member must not be built.
            expectFileDoesNotExist(at: binPath.appending("LibBExtra.swiftmodule"))
            // Sibling members' products must not be built.
            expectFileDoesNotExist(at: binPath.appending("app"))
            expectFileDoesNotExist(at: binPath.appending("LibA.swiftmodule"))
        }
    }

    /// `--package X --target Y` where member `X` exists but target `Y`
    /// doesn't emits the `unknownTargetInMember` diagnostic listing the
    /// member's known targets.
    @Test(
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s05_packageSelectorWithInvalidTarget_errorsWithHelpfulMessage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S05_PackageSelector") { fixturePath in
            let (_, stderr) = try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                extraArgs: ["--package", "lib-b", "--target", "DoesNotExist"],
                buildSystem: buildSystem,
                throwIfCommandFails: false,
            )

            let expected = Basics.Diagnostic.unknownTargetInMember(
                requested: "DoesNotExist",
                package: .plain("lib-b"),
                known: [.plain("LibB"), .plain("LibBExtra")],
            )
            #expect(
                stderr.contains(expected.message),
                "expected unknown-target-in-member diagnostic; got: \(stderr)",
            )
        }
    }

    /// `--package X` supplied from inside a DIFFERENT member `Y`
    /// overrides the CWD-derived focus on `Y`. The selector wins; only
    /// `X`'s products are built. This is the cross-member escape valve.
    ///
    /// Also exercises the deferred-from-Slice-4 nested-`.workspaceInherited`
    /// chain: `app` uses `.package(workspaceMember: "lib-a")` and
    /// `lib-a` uses `.package(workspaceInherited: "some-lib")`. Focus
    /// on `app` must pull `lib-a` in transitively and resolve `lib-a`'s
    /// inherited dep against the workspace's `some-lib` — exercising
    /// the container-side rewrite (from Slice 3) for a NON-root member
    /// manifest.
    @Test(
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s05_packageSelectorFromInsideAnotherMember_buildsSelectedMemberAndTransitiveDeps(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S05_PackageSelector") { fixturePath in
            let libBPath = fixturePath.appending(components: "packages", "lib-b")

            // Invoke from inside `lib-b`, but select `--package app`.
            // Slice 5 semantics: `--package` wins over CWD focus, so
            // `app` builds even though CWD's focus is `lib-b`.
            try await executeSwiftBuild(
                libBPath,
                configuration: .debug,
                extraArgs: ["--package", "app"],
                buildSystem: buildSystem,
            )

            let binPath = try await getBinPath(
                libBPath,
                configuration: .debug,
                extraArgs: ["--package", "app"],
                buildSystem: buildSystem,
            )

            // `app` was built via the selector.
            expectFileExists(at: binPath.appending("app"))
            // `lib-a` (transitive workspace-member dep of `app`) was
            // built too — and its `.workspaceInherited("some-lib")`
            // was resolved through the container-side rewrite.
            expectFileExists(at: binPath.appending("LibA.swiftmodule"))
            // `SomeLib` (transitive workspace-inherited dep of `lib-a`
            // via `app`) was built.
            expectFileExists(at: binPath.appending("SomeLib.swiftmodule"))
            // `lib-b` (the CWD's enclosing member, NOT a dep of `app`)
            // was NOT built — proves the selector overrides focus and
            // doesn't pull in the CWD member.
            expectFileDoesNotExist(at: binPath.appending("LibB.swiftmodule"))
        }
    }

    /// `--package invalid` where `invalid` isn't a declared workspace
    /// member yields a non-zero exit and stderr naming the unknown
    /// identity AND listing the known identities.
    @Test(
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s05_packageSelectorWithUnknownIdentity_errorsWithHelpfulMessage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S05_PackageSelector") { fixturePath in
            let (_, stderr) = try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                extraArgs: ["--package", "does-not-exist"],
                buildSystem: buildSystem,
                throwIfCommandFails: false,
            )

            let knownPackageIds = Set(["app", "lib-a", "lib-b"].map { PackageIdentity.plain($0) })
            let expectedDiagnostic = Basics.Diagnostic.unknownWorkspaceMember(
                requested: "does-not-exist",
                known: knownPackageIds,
            )
            #expect(
                stderr.contains(expectedDiagnostic.message),
                "expected unknown workspace member diagnostic; got: \(stderr)",
            )
        }
    }

    /// `--package X` outside a workspace (a single-package fixture,
    /// no `Workspace.swift` in scope) errors with a "requires a
    /// Workspace.swift" diagnostic. Reuses S01 with a member as the
    /// CWD — S01's `packages/lib-a` has no enclosing workspace when
    /// isolated (we run swift-build INSIDE the member to break the
    /// workspace discovery walk-up).
    @Test(
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s05_packageSelectorOutsideWorkspace_errorsWithRequiresWorkspaceDiagnostic(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Miscellaneous/Simple") { fixturePath in
            let  requestedPackageName = "anything"
            let (_, stderr) = try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                extraArgs: ["--package", requestedPackageName],
                buildSystem: buildSystem,
                throwIfCommandFails: false,
            )

            let packageId = PackageIdentity.plain(requestedPackageName)
            let expectedDiagnostic = Basics.Diagnostic.packageSelectorRequiresWorkspace(requested: packageId)

            #expect(
                stderr.contains(expectedDiagnostic.message),
                "expected requires-Workspace.swift diagnostic; got: \(stderr)",
            )
        }
    }

    /// `swift test` at workspace root runs the test suites of ALL
    /// members. S06 has `lib-a` and `lib-b`, each with a single test
    /// target — both should execute.
    ///
    /// Restricted to the Swift Build build system: workspace-scoped
    /// `swift test` execution is only supported there in this slice.
    @Test(
        .tags(
            Tag.Feature.Command.Test,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s06_swiftTestRunsAllMembersFromRoot(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S06_SwiftTest") { fixturePath in
            let (stdout, stderr) = try await executeSwiftTest(
                fixturePath,
                configuration: .debug,
                buildSystem: buildSystem,
            )

            let combined = stdout + stderr
            // Swift Testing test cases (LibATests / LibBTests).
            #expect(
                combined.contains("libAGreeting_returnsExpected"),
                "expected lib-a's Swift Testing case to run; got stdout=\(stdout) stderr=\(stderr)",
            )
            #expect(
                combined.contains("libBGreeting_returnsExpected"),
                "expected lib-b's Swift Testing case to run; got stdout=\(stdout) stderr=\(stderr)",
            )
            // XCTest cases (LibAXCTests / LibBXCTests). Each member also
            // has an XCTest-based target so the merger has to aggregate
            // two products per member; both cases must execute at root.
            #expect(
                combined.contains("testLibAGreeting"),
                "expected lib-a's XCTest case to run; got stdout=\(stdout) stderr=\(stderr)",
            )
            #expect(
                combined.contains("testLibBGreeting"),
                "expected lib-b's XCTest case to run; got stdout=\(stdout) stderr=\(stderr)",
            )
        }
    }

    /// `swift test --package lib-a` at workspace root narrows execution
    /// to ONLY `lib-a`'s tests. `lib-b`'s tests must not be built or
    /// executed. Applies to both the Swift Testing and XCTest targets
    /// each member owns.
    @Test(
        .tags(
            Tag.Feature.Command.Test,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s06_swiftTestPackageSelectorRunsOnlySelectedMember(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S06_SwiftTest") { fixturePath in
            let (stdout, stderr) = try await executeSwiftTest(
                fixturePath,
                configuration: .debug,
                extraArgs: ["--package", "lib-a"],
                buildSystem: buildSystem,
            )

            let combined = stdout + stderr
            // lib-a's cases (both libraries) execute.
            #expect(
                combined.contains("libAGreeting_returnsExpected"),
                "expected lib-a's Swift Testing case to run; got stdout=\(stdout) stderr=\(stderr)",
            )
            #expect(
                combined.contains("testLibAGreeting"),
                "expected lib-a's XCTest case to run; got stdout=\(stdout) stderr=\(stderr)",
            )
            // lib-b's cases (both libraries) do NOT execute.
            #expect(
                combined.contains("libBGreeting_returnsExpected") == false,
                "expected lib-b's Swift Testing case to NOT run when --package lib-a; got stdout=\(stdout) stderr=\(stderr)",
            )
            #expect(
                combined.contains("testLibBGreeting") == false,
                "expected lib-b's XCTest case to NOT run when --package lib-a; got stdout=\(stdout) stderr=\(stderr)",
            )
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Test,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s06_swiftTestFromWithinAMemberRunsOnlySelectedMember(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S06_SwiftTest") { fixturePath in
            let (stdout, stderr) = try await executeSwiftTest(
                fixturePath.appending(components: ["packages", "lib-a"]),
                configuration: .debug,
                // extraArgs: ["--package", "lib-a"],
                buildSystem: buildSystem,
            )

            let combined = stdout + stderr
            // lib-a's cases (both libraries) execute.
            #expect(
                combined.contains("libAGreeting_returnsExpected"),
                "expected lib-a's Swift Testing case to run; got stdout=\(stdout) stderr=\(stderr)",
            )
            #expect(
                combined.contains("testLibAGreeting"),
                "expected lib-a's XCTest case to run; got stdout=\(stdout) stderr=\(stderr)",
            )
            // lib-b's cases (both libraries) do NOT execute.
            #expect(
                combined.contains("libBGreeting_returnsExpected") == false,
                "expected lib-b's Swift Testing case to NOT run when --package lib-a; got stdout=\(stdout) stderr=\(stderr)",
            )
            #expect(
                combined.contains("testLibBGreeting") == false,
                "expected lib-b's XCTest case to NOT run when --package lib-a; got stdout=\(stdout) stderr=\(stderr)",
            )
        }
    }

    /// The merged xUnit report emitted at workspace root carries a
    /// `<properties><property name="package" value="<identity>"/></properties>`
    /// entry on every `<testsuite>` so downstream consumers can
    /// attribute each suite to its owning workspace member.
    ///
    /// Both xUnit files (Swift Testing's `xunit-swift-testing.xml` via
    /// the per-product merger and XCTest's `xunit.xml` via
    /// `XUnitGenerator`'s per-package grouping) must carry `package`
    /// properties for each workspace member represented in the run.
    @Test(
        .tags(
            Tag.Feature.Command.Test,
            Tag.Feature.CommandLineArguments.TestOutputXunit,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s06_xunitReportContainsPackageProperty(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S06_SwiftTest") { fixturePath in
            let xctestXUnit = fixturePath.appending("xunit.xml")
            // `--parallel` is required for XCTest to emit an xUnit file
            // — SwiftPM's non-parallel XCTest path skips the generator.
            // Swift Testing writes its own xUnit regardless.
            _ = try await executeSwiftTest(
                fixturePath,
                configuration: .debug,
                extraArgs: [
                    "--parallel",
                    "--xunit-output", xctestXUnit.pathString,
                    "--experimental-xunit-message-failure",
                ],
                buildSystem: buildSystem,
            )

            // SwiftPM writes Swift Testing's xUnit output to
            // `<basename>-swift-testing.<ext>` and XCTest's to the
            // requested `<basename>.<ext>` so the two libraries don't
            // stomp on each other's file. Both must be present and
            // both must carry per-suite `package` properties.
            let swiftTestingXUnit = fixturePath.appending("xunit-swift-testing.xml")
            expectFileExists(at: swiftTestingXUnit)
            expectFileExists(at: xctestXUnit)

            for reportPath in [swiftTestingXUnit, xctestXUnit] {
                let contents: String = try localFileSystem.readFileContents(reportPath)
                #expect(
                    contents.contains("name=\"package\"") && contents.contains("value=\"lib-a\""),
                    "expected <property name=\"package\" value=\"lib-a\"> in \(reportPath.basename):\n\(contents)",
                )
                #expect(
                    contents.contains("value=\"lib-b\""),
                    "expected <property name=\"package\" value=\"lib-b\"> in \(reportPath.basename):\n\(contents)",
                )
            }
        }
    }

    /// `swift test list` at workspace root lists the test specifiers of
    /// every member — for BOTH testing libraries. S06 has `lib-a` and
    /// `lib-b`, each with a Swift Testing target and an XCTest target,
    /// so all four kinds of specifiers must appear.
    @Test(
        .tags(
            Tag.Feature.Command.Test,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s06_swiftTestListFromRoot_listsAllMembersTests(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S06_SwiftTest") { fixturePath in
            let (stdout, stderr) = try await executeSwiftTest(
                fixturePath,
                configuration: .debug,
                extraArgs: ["list"],
                buildSystem: buildSystem,
            )

            // XCTest specifiers (LibAXCTests / LibBXCTests classes).
            #expect(
                stdout.contains("LibAXCTests"),
                "expected lib-a's XCTest specifier in list output; got stdout=\(stdout) stderr=\(stderr)",
            )
            #expect(
                stdout.contains("LibBXCTests"),
                "expected lib-b's XCTest specifier in list output; got stdout=\(stdout) stderr=\(stderr)",
            )
            // Swift Testing specifiers (@Test function names).
            #expect(
                stdout.contains("libAGreeting_returnsExpected"),
                "expected lib-a's Swift Testing specifier in list output; got stdout=\(stdout) stderr=\(stderr)",
            )
            #expect(
                stdout.contains("libBGreeting_returnsExpected"),
                "expected lib-b's Swift Testing specifier in list output; got stdout=\(stdout) stderr=\(stderr)",
            )
        }
    }

    /// `swift test list --package lib-a` at workspace root narrows the
    /// listing to ONLY `lib-a`'s test specifiers, across both testing
    /// libraries. `lib-b`'s specifiers (of either kind) must not appear.
    @Test(
        .tags(
            Tag.Feature.Command.Test,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s06_swiftTestListPackageSelector_listsOnlySelectedMemberTests(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S06_SwiftTest") { fixturePath in
            let (stdout, stderr) = try await executeSwiftTest(
                fixturePath,
                configuration: .debug,
                extraArgs: ["list", "--package", "lib-a"],
                buildSystem: buildSystem,
            )

            // lib-a's specifiers (both libraries) appear.
            #expect(
                stdout.contains("LibAXCTests"),
                "expected lib-a's XCTest specifier in list output; got stdout=\(stdout) stderr=\(stderr)",
            )
            #expect(
                stdout.contains("libAGreeting_returnsExpected"),
                "expected lib-a's Swift Testing specifier in list output; got stdout=\(stdout) stderr=\(stderr)",
            )
            // lib-b's specifiers (both libraries) do NOT appear.
            #expect(
                stdout.contains("LibBXCTests") == false,
                "expected lib-b's XCTest specifier to NOT appear when --package lib-a; got stdout=\(stdout) stderr=\(stderr)",
            )
            #expect(
                stdout.contains("libBGreeting_returnsExpected") == false,
                "expected lib-b's Swift Testing specifier to NOT appear when --package lib-a; got stdout=\(stdout) stderr=\(stderr)",
            )
        }
    }

    /// `swift test --package <unknown>` (and `swift test list --package
    /// <unknown>`) at a workspace root emit the "unknown workspace
    /// member" diagnostic listing the known member identities. Both
    /// invocation forms share the same underlying decision logic —
    /// parameterizing over the subcommand prefix keeps that symmetry
    /// visible.
    @Test(
        .tags(
            Tag.Feature.Command.Test,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
        [
            SwiftTestInvocation(subcommand: [], label: "swift test"),
            SwiftTestInvocation(subcommand: ["list"], label: "swift test list"),
        ],
    )
    func s06_swiftTestWithUnknownIdentity_errorsWithHelpfulMessage(
        buildSystem: BuildSystemProvider.Kind,
        invocation: SwiftTestInvocation,
    ) async throws {
        try await fixture(name: "Workspaces/S06_SwiftTest") { fixturePath in
            let (_, stderr) = try await executeSwiftTest(
                fixturePath,
                configuration: .debug,
                extraArgs: invocation.subcommand + ["--package", "does-not-exist"],
                buildSystem: buildSystem,
            )

            let knownPackageIds = Set(["lib-a", "lib-b"].map { PackageIdentity.plain($0) })
            let expectedDiagnostic = Basics.Diagnostic.unknownWorkspaceMember(
                requested: "does-not-exist",
                known: knownPackageIds,
            )
            #expect(
                stderr.contains(expectedDiagnostic.message),
                "\(invocation.label): expected unknown workspace member diagnostic; got: \(stderr)",
            )
        }
    }

    /// `swift test --package X` (and `swift test list --package X`)
    /// invoked outside a workspace emit the "requires a Workspace.swift"
    /// diagnostic. Parameterized over the subcommand prefix.
    @Test(
        .tags(
            Tag.Feature.Command.Test,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
        [
            SwiftTestInvocation(subcommand: [], label: "swift test"),
            SwiftTestInvocation(subcommand: ["list"], label: "swift test list"),
        ],
    )
    func s06_swiftTestOutsideWorkspace_errorsWithRequiresWorkspaceDiagnostic(
        buildSystem: BuildSystemProvider.Kind,
        invocation: SwiftTestInvocation,
    ) async throws {
        try await fixture(name: "Miscellaneous/Simple") { fixturePath in
            let requestedPackageName = "anything"
            let (_, stderr) = try await executeSwiftTest(
                fixturePath,
                configuration: .debug,
                extraArgs: invocation.subcommand + ["--package", requestedPackageName],
                buildSystem: buildSystem,
            )

            let packageId = PackageIdentity.plain(requestedPackageName)
            let expectedDiagnostic = Basics.Diagnostic.packageSelectorRequiresWorkspace(requested: packageId)

            #expect(
                stderr.contains(expectedDiagnostic.message),
                "\(invocation.label): expected requires-Workspace.swift diagnostic; got: \(stderr)",
            )
        }
    }

    // MARK: - Slice 7: `swift run` collisions

    /// `swift run hello` at workspace root with two members both
    /// declaring an executable `hello` errors with the
    /// `ambiguousExecutable` diagnostic and lists both member+product
    /// candidates.
    @Test(
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s07_ambiguousExecutableErrorsWithCandidates(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S07_RunAmbiguity") { fixturePath in
            let (_, stderr) = try await executeSwiftRun(
                fixturePath,
                "hello",
                configuration: .debug,
                buildSystem: buildSystem,
                throwIfCommandFails: false,
            )

            let expected = Basics.Diagnostic.ambiguousExecutable(
                requested: "hello",
                candidates: [
                    (member: .plain("member-a"), product: "hello"),
                    (member: .plain("member-b"), product: "hello"),
                ],
            )
            #expect(
                stderr.contains(expected.message),
                "expected ambiguous-executable diagnostic; got: \(stderr)",
            )
        }
    }

    /// `swift run --package member-a hello` at workspace root
    /// disambiguates the collision and runs member-a's `hello`
    /// executable. Ambiguity resolved by the selector.
    @Test(
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s07_packageSelectorResolvesAmbiguity(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S07_RunAmbiguity") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath,
                "hello",
                configuration: .debug,
                extraArgs: ["--package", "member-a"],
                buildSystem: buildSystem,
            )

            #expect(
                stdout.contains("hello from member-a"),
                "expected member-a's hello output; got stdout=\(stdout) stderr=\(stderr)",
            )
            #expect(
                stdout.contains("hello from member-b") == false,
                "did not expect member-b's hello output; got stdout=\(stdout)",
            )
        }
    }

    /// From inside `member-a`, `swift run hello` scopes to member-a's
    /// `hello` — no ambiguity, no error — even though member-b also
    /// declares `hello`. Exercises the CWD-inside-member (Case A)
    /// workspace focus.
    @Test(
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s07_runFromInsideMemberScopedToMember(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S07_RunAmbiguity") { fixturePath in
            let memberPath = fixturePath.appending(components: "packages", "member-a")

            let (stdout, stderr) = try await executeSwiftRun(
                memberPath,
                "hello",
                configuration: .debug,
                buildSystem: buildSystem,
            )

            #expect(
                stdout.contains("hello from member-a"),
                "expected member-a's hello output; got stdout=\(stdout) stderr=\(stderr)",
            )
        }
    }

    /// From inside `member-a`, `swift run unique` (member-c's
    /// executable) must NOT be silently found via cross-member search.
    /// Emit `executableNotFoundInMember` listing member-a's known
    /// executables and fail.
    @Test(
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s07_runFromInsideMemberDoesNotFindCrossMemberExecutable(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S07_RunAmbiguity") { fixturePath in
            let memberPath = fixturePath.appending(components: "packages", "member-a")

            let (_, stderr) = try await executeSwiftRun(
                memberPath,
                "unique",
                configuration: .debug,
                buildSystem: buildSystem,
                throwIfCommandFails: false,
            )

            let expected = Basics.Diagnostic.executableNotFoundInMember(
                requested: "unique",
                package: .plain("member-a"),
                known: [.plain("hello")],
            )
            #expect(
                stderr.contains(expected.message),
                "expected executable-not-found-in-member diagnostic; got: \(stderr)",
            )
        }
    }

    /// `--package X hello` supplied from inside a DIFFERENT member
    /// (member-a) runs member-b's `hello`. Confirms that `--package`
    /// wins over the CWD-derived focus at the e2e level, matching the
    /// mid-tier `resolveRunTarget_selectedPackageOverridesFocus_...`
    /// unit test.
    @Test(
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s07_packageSelectorFromInsideAnotherMember_invokesSelectedMemberExecutable(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S07_RunAmbiguity") { fixturePath in
            let memberPath = fixturePath.appending(components: "packages", "member-a")

            let (stdout, stderr) = try await executeSwiftRun(
                memberPath,
                "hello",
                configuration: .debug,
                extraArgs: ["--package", "member-b"],
                buildSystem: buildSystem,
            )

            #expect(
                stdout.contains("hello from member-b"),
                "expected member-b's hello output; got stdout=\(stdout) stderr=\(stderr)",
            )
            #expect(
                stdout.contains("hello from member-a") == false,
                "did not expect member-a's hello output; got stdout=\(stdout)",
            )
        }
    }

    /// `swift run` at the workspace root of a workspace whose members
    /// declare no executables errors with the
    /// `noExecutableFoundInWorkspace` diagnostic.
    @Test(
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s07_runAtRootWithNoExecutables_errorsWithNoExecutableFoundDiagnostic(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S07_NoExecutables") { fixturePath in
            let (_, stderr) = try await executeSwiftRun(
                fixturePath,
                nil,
                configuration: .debug,
                buildSystem: buildSystem,
                throwIfCommandFails: false,
            )

            let expected = Basics.Diagnostic.noExecutableFoundInWorkspace()
            #expect(
                stderr.contains(expected.message),
                "expected no-executable-found-in-workspace diagnostic; got: \(stderr)",
            )
        }
    }

    /// `swift run --package X` at workspace root where member `X`
    /// declares no executables emits the scoped
    /// `noExecutableFoundInMember(X)` diagnostic (not the workspace-
    /// wide variant), because the selector narrowed the search to X.
    @Test(
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s07_runWithPackageSelectorAndNoExecutablesInMember_errorsWithScopedDiagnostic(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S07_NoExecutables") { fixturePath in
            let (_, stderr) = try await executeSwiftRun(
                fixturePath,
                nil,
                configuration: .debug,
                extraArgs: ["--package", "lib-a"],
                buildSystem: buildSystem,
                throwIfCommandFails: false,
            )

            let expected = Basics.Diagnostic.noExecutableFoundInMember(
                package: .plain("lib-a"),
            )
            #expect(
                stderr.contains(expected.message),
                "expected no-executable-found-in-member diagnostic; got: \(stderr)",
            )
        }
    }

    /// From inside library-only member `lib-only`, `swift run` (no
    /// name) emits `noExecutableFoundInMember(lib-only)` — the Case A
    /// focus scopes the search, and cross-member executables are not
    /// silently reached.
    @Test(
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s07_runFromInsideLibOnlyMember_errorsWithScopedDiagnostic(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S07_RunAmbiguity") { fixturePath in
            let memberPath = fixturePath.appending(components: "packages", "lib-only")

            let (_, stderr) = try await executeSwiftRun(
                memberPath,
                nil,
                configuration: .debug,
                buildSystem: buildSystem,
                throwIfCommandFails: false,
            )

            let expected = Basics.Diagnostic.noExecutableFoundInMember(
                package: .plain("lib-only"),
            )
            #expect(
                stderr.contains(expected.message),
                "expected no-executable-found-in-member diagnostic; got: \(stderr)",
            )
        }
    }

    /// From inside library-only member `lib-only`, `swift run --package
    /// member-a hello` invokes member-a's `hello` — `--package`
    /// provides an escape hatch from a member with no executables.
    @Test(
        .tags(
            Tag.Feature.Command.Run,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s07_packageSelectorFromLibOnlyMember_invokesSelectedMemberExecutable(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S07_RunAmbiguity") { fixturePath in
            let memberPath = fixturePath.appending(components: "packages", "lib-only")

            let (stdout, stderr) = try await executeSwiftRun(
                memberPath,
                "hello",
                configuration: .debug,
                extraArgs: ["--package", "member-a"],
                buildSystem: buildSystem,
            )

            #expect(
                stdout.contains("hello from member-a"),
                "expected member-a's hello output; got stdout=\(stdout) stderr=\(stderr)",
            )
        }
    }

    // MARK: - Slice 8: `swift package resolve` at workspace root

    /// `swift package resolve` at the workspace root writes
    /// `Package.resolved` at the workspace root — not at any member's
    /// package root. All members share this single resolution file so
    /// the workspace is the sole owner of dependency-resolution state.
    @Test(
        .tags(
            .Feature.Command.Package.Resolve,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s08_packageResolvedWrittenAtWorkspaceRoot(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S08_ResolveAndWarnings") { fixturePath in
            let gitRepoPath = fixturePath.appending(components: "external", "some-lib")
            try requireDirectoryExists(at: gitRepoPath)
            try Self.initializeExternalRepo(at: gitRepoPath)

            _ = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["resolve"],
                buildSystem: buildSystem,
            )

            expectFileExists(at: fixturePath.appending("Package.resolved"))
            for member in ["app", "lib-a", "lib-b"] {
                expectFileDoesNotExist(
                    at: fixturePath.appending(components: "packages", member, "Package.resolved"),
                )
            }
        }
    }

    /// A workspace member with its own `.build/` and `Package.resolved`
    /// on disk triggers a trailing warning at the end of the command.
    /// The workspace root owns the authoritative state; per-member
    /// state is detected but ignored. The warning tells the user
    /// which members carry stale local state that could be deleted or
    /// promoted to the workspace root.
    @Test(
        .tags(
            .Feature.Command.Package.Resolve,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s08_memberStateFilesTriggerTrailingWarning(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S08_ResolveAndWarnings") { fixturePath in
            let gitRepoPath = fixturePath.appending(components: "external", "some-lib")
            try requireDirectoryExists(at: gitRepoPath)
            try Self.initializeExternalRepo(at: gitRepoPath)

            let libAPath = fixturePath.appending(components: "packages", "lib-a")
            try localFileSystem.createDirectory(libAPath.appending(".build"), recursive: true)
            try localFileSystem.writeFileContents(libAPath.appending("Package.resolved"), string: "{}")

            let (_, stderr) = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["resolve"],
                buildSystem: buildSystem,
            )

            #expect(
                stderr.contains("workspace members have ignored state:"),
                "expected trailing warning header; got stderr=\(stderr)",
            )
            #expect(
                stderr.contains("lib-a: .build/, Package.resolved"),
                "expected lib-a's detected state kinds to be listed; got stderr=\(stderr)",
            )
            #expect(
                stderr.contains("Only workspace-root state is used."),
                "expected the trailing warning epilogue; got stderr=\(stderr)",
            )
        }
    }

    /// A member whose `Workspace.swift` entry declares
    /// `ignoredStateDirectories: [.build]` must be omitted from the
    /// trailing warning even when `.build/` is present on disk. The
    /// suppression is a per-member opt-out for state kinds that are
    /// legitimately allowed to live at the member level. Other
    /// members without the suppression still surface normally.
    @Test(
        .tags(
            .Feature.Command.Package.Resolve,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s08_ignoredStateDirectoriesSuppressesWarning(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S08_ResolveAndWarnings") { fixturePath in
            let gitRepoPath = fixturePath.appending(components: "external", "some-lib")
            try requireDirectoryExists(at: gitRepoPath)
            try Self.initializeExternalRepo(at: gitRepoPath)

            let libAPath = fixturePath.appending(components: "packages", "lib-a")
            let libBPath = fixturePath.appending(components: "packages", "lib-b")
            try localFileSystem.createDirectory(libAPath.appending(".build"), recursive: true)
            try localFileSystem.createDirectory(libBPath.appending(".build"), recursive: true)

            let (_, stderr) = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["resolve"],
                buildSystem: buildSystem,
            )

            #expect(
                stderr.contains("lib-a: .build/"),
                "expected lib-a's .build/ to be reported; got stderr=\(stderr)",
            )
            #expect(
                stderr.contains("lib-b:") == false,
                "expected lib-b to be suppressed via ignoredStateDirectories; got stderr=\(stderr)",
            )
        }
    }

    /// Workspace-level dependencies contribute to the resolved-file
    /// `originHash`: two resolves whose member manifests are
    /// identical but whose `Workspace.swift` `dependencies:` clauses
    /// differ must produce different origin hashes. This is what lets
    /// SwiftPM correctly invalidate a stale `Package.resolved` when a
    /// workspace-level dep is added, removed, or changed — without
    /// this, workspace-scope dependency edits would silently skip
    /// re-resolution.
    @Test(
        .tags(
            .Feature.Command.Package.Resolve,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s08_originHashUnionsMembersAndWorkspaceDeps(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S08_ResolveAndWarnings") { fixturePath in
            try Self.initializeExternalRepo(at: fixturePath.appending(components: "external", "some-lib"))
            try Self.initializeExternalRepo(at: fixturePath.appending(components: "external", "other-lib"))

            _ = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["resolve"],
                buildSystem: buildSystem,
            )
            let hashBefore = try Self.readOriginHash(
                from: fixturePath.appending("Package.resolved"),
            )

            let workspaceManifestPath = fixturePath.appending("Workspace.swift")
            let augmentedManifest = """
                // swift-tools-version: 999.0
                import PackageDescription

                let workspace = Workspace(
                    members: [
                        "packages/app",
                        "packages/lib-a",
                        .member(
                            path: "packages/lib-b",
                            ignoredStateDirectories: [.build],
                        ),
                    ],
                    dependencies: [
                        .package(url: "external/some-lib", from: "1.0.0"),
                        .package(url: "external/other-lib", from: "1.0.0"),
                    ],
                )
                """
            try localFileSystem.writeFileContents(workspaceManifestPath, string: augmentedManifest)

            _ = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["resolve"],
                buildSystem: buildSystem,
            )
            let hashAfter = try Self.readOriginHash(
                from: fixturePath.appending("Package.resolved"),
            )

            #expect(
                hashBefore != hashAfter,
                "originHash must change when a workspace-level dep is added; got \(hashBefore) both times",
            )
        }
    }

    // MARK: - Slice 9: workspace dependency overrides

    /// `.swiftpm/configuration/workspace-overrides.json` redirects a workspace-
    /// declared source-control dependency to a local filesystem
    /// checkout. The declared source-control URL is never contacted
    /// — the override is applied at workspace-manifest load time,
    /// before the resolver runs. Verifies the end-to-end flow: file
    /// discovery, parse, apply, and downstream build against the
    /// substituted dep.
    @Test(
        .tags(
            .Feature.Command.Package.Resolve,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s08_b_workspaceOverrideRedirectsToLocalCheckout(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S08_WorkspaceOverrides") { fixturePath in
            let (_, stderr) = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["resolve", "--verbose"],
                buildSystem: buildSystem,
            )

            #expect(
                stderr.contains("applying 1 workspace dependency override(s) from"),
                "expected info diagnostic listing the applied override; got stderr=\(stderr)",
            )
            #expect(
                stderr.contains("some-lib:"),
                "expected the override entry to name the target identity; got stderr=\(stderr)",
            )

            try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                buildSystem: buildSystem,
            )
            let binPath = try await getBinPath(
                fixturePath,
                configuration: .debug,
                buildSystem: buildSystem,
            )
            let appBinary = binPath.appending("app")
            expectFileExists(at: appBinary)
            let output = try await AsyncProcess.checkNonZeroExit(
                args: appBinary.pathString,
            ).withSwiftLineEnding
            #expect(
                output == "app says: hello from LOCAL some-lib\n",
                "expected the LOCAL some-lib greeting (override target), got: \(output)",
            )
        }
    }

    // MARK: - Slice 10: `swift workspace override` subcommand

    /// `swift workspace override list` invoked in a workspace
    /// with no overrides file emits the "no overrides declared" hint
    /// and exits successfully. Verifies the empty-state UX before any
    /// mutation happens.
    @Test(
        .tags(
            .Feature.Command.Package.Resolve,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s08_c_workspaceOverrideList_empty(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S08_WorkspaceOverrides") { fixturePath in
            let overridesFile = fixturePath.appending(
                components: ".swiftpm", "configuration", "workspace-overrides.json",
            )
            try localFileSystem.removeFileTree(overridesFile)

            let (stdout, _) = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: ["override", "list"],
                buildSystem: buildSystem,
            )

            #expect(
                stdout.contains("(no overrides declared)"),
                "expected empty-state hint; got stdout=\(stdout)",
            )
        }
    }

    /// `swift workspace override add <identity> --project-path <path>`
    /// writes the override to `.swiftpm/configuration/workspace-overrides.json`
    /// and a subsequent `swift build` picks up the redirect — the
    /// built binary prints the LOCAL greeting instead of contacting
    /// the declared source-control URL.
    @Test(
        .tags(
            .Feature.Command.Package.Resolve,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s08_c_workspaceOverrideAdd_thenBuildUsesRedirect(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S08_WorkspaceOverrides") { fixturePath in
            let overridesFile = fixturePath.appending(
                components: ".swiftpm", "configuration", "workspace-overrides.json",
            )
            try localFileSystem.removeFileTree(overridesFile)

            _ = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: [
                    "override", "add", "path",
                    "some-lib", "external/local-some-lib",
                ],
                buildSystem: buildSystem,
            )
            expectFileExists(at: overridesFile)

            try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                buildSystem: buildSystem,
            )
            let binPath = try await getBinPath(
                fixturePath,
                configuration: .debug,
                buildSystem: buildSystem,
            )
            let output = try await AsyncProcess.checkNonZeroExit(
                args: binPath.appending("app").pathString,
            ).withSwiftLineEnding
            #expect(
                output == "app says: hello from LOCAL some-lib\n",
                "expected the LOCAL some-lib greeting after CLI-added override; got: \(output)",
            )
        }
    }

    /// `swift workspace override add url <identity> <url>
    /// --exact <version>` writes a source-control override to
    /// `.swiftpm/configuration/workspace-overrides.json`. Verified
    /// via a follow-up `override list` so the assertion exercises
    /// the read side of the same JSON file that `add url` wrote.
    @Test(
        .tags(
            .Feature.Command.Package.Resolve,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s08_c_workspaceOverrideAddUrl_writesSourceControlEntry(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S08_WorkspaceOverrides") { fixturePath in
            let overridesFile = fixturePath.appending(
                components: ".swiftpm", "configuration", "workspace-overrides.json",
            )
            try localFileSystem.removeFileTree(overridesFile)
            let redirectURL = "https://github.com/apple/example-some-lib.git"

            _ = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: [
                    "override", "add", "url",
                    "some-lib", redirectURL,
                    "--exact", "1.0.0",
                ],
                buildSystem: buildSystem,
            )
            expectFileExists(at: overridesFile)

            let (stdout, _) = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: ["override", "list"],
                buildSystem: buildSystem,
            )
            #expect(
                stdout.contains("some-lib"),
                "expected `some-lib` identity in list output; got stdout=\(stdout)",
            )
            #expect(
                stdout.contains("kind: url"),
                "expected `kind: url` line for source-control override; got stdout=\(stdout)",
            )
            #expect(
                stdout.contains("location: \(redirectURL)"),
                "expected `location: \(redirectURL)` line; got stdout=\(stdout)",
            )
            #expect(
                stdout.contains("requirement: exact 1.0.0"),
                "expected `requirement: exact 1.0.0` line; got stdout=\(stdout)",
            )
        }
    }

    /// `swift workspace override add registry <identity>
    /// --exact <version>` writes a registry override to
    /// `.swiftpm/configuration/workspace-overrides.json`. The
    /// identity plays a dual role — it names the declared dep to
    /// redirect AND the registry identity to resolve against — so
    /// the follow-up `override list` prints `<identity>: <identity>`
    /// (the display target for `.registry` overrides is the registry
    /// identity, and the parser reconstructs it as the override's own
    /// identity).
    @Test(
        .tags(
            .Feature.Command.Package.Resolve,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s08_c_workspaceOverrideAddRegistry_writesRegistryEntry(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S08_WorkspaceOverrides") { fixturePath in
            let overridesFile = fixturePath.appending(
                components: ".swiftpm", "configuration", "workspace-overrides.json",
            )
            try localFileSystem.removeFileTree(overridesFile)

            _ = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: [
                    "override", "add", "registry",
                    "some-lib",
                    "--exact", "1.0.0",
                ],
                buildSystem: buildSystem,
            )
            expectFileExists(at: overridesFile)

            let (stdout, _) = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: ["override", "list"],
                buildSystem: buildSystem,
            )
            #expect(
                stdout.contains("some-lib"),
                "expected `some-lib` identity in list output; got stdout=\(stdout)",
            )
            #expect(
                stdout.contains("kind: registry"),
                "expected `kind: registry` line for registry override; got stdout=\(stdout)",
            )
            #expect(
                stdout.contains("location: some-lib"),
                "expected `location: some-lib` line (the registry identity mirrors the override identity); got stdout=\(stdout)",
            )
            #expect(
                stdout.contains("requirement: exact 1.0.0"),
                "expected `requirement: exact 1.0.0` line; got stdout=\(stdout)",
            )
        }
    }

    /// After adding an override via the CLI, `list` shows the entry
    /// in the expected `identity: target` format.
    @Test(
        .tags(
            .Feature.Command.Package.Resolve,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s08_c_workspaceOverrideList_showsAddedEntry(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S08_WorkspaceOverrides") { fixturePath in
            let overridesFile = fixturePath.appending(
                components: ".swiftpm", "configuration", "workspace-overrides.json",
            )
            try localFileSystem.removeFileTree(overridesFile)

            _ = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: [
                    "override", "add", "path",
                    "some-lib", "external/local-some-lib",
                ],
                buildSystem: buildSystem,
            )
            let (stdout, _) = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: ["override", "list"],
                buildSystem: buildSystem,
            )

            #expect(
                stdout.contains("some-lib"),
                "expected `some-lib` identity in list output; got stdout=\(stdout)",
            )
            #expect(
                stdout.contains("kind: path"),
                "expected `kind: path` line for filesystem override; got stdout=\(stdout)",
            )
            #expect(
                stdout.contains("external/local-some-lib"),
                "expected the redirected path in list output; got stdout=\(stdout)",
            )
        }
    }

    /// `swift workspace override remove <identity>` deletes
    /// JSON array of per-override records. The array parses cleanly
    /// with `JSONSerialization` and each element carries `identity`,
    /// `kind`, and `location` fields so downstream tooling can consume
    /// the list without regex'ing the human-readable text output.
    @Test(
        .tags(
            .Feature.Command.Package.Resolve,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s08_c_workspaceOverrideList_jsonFormat(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S08_WorkspaceOverrides") { fixturePath in
            let overridesFile = fixturePath.appending(
                components: ".swiftpm", "configuration", "workspace-overrides.json",
            )
            try localFileSystem.removeFileTree(overridesFile)

            _ = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: [
                    "override", "add", "path",
                    "some-lib", "external/local-some-lib",
                ],
                buildSystem: buildSystem,
            )

            let (stdout, _) = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: ["override", "list", "--format", "json"],
                buildSystem: buildSystem,
            )

            let data = try #require(stdout.data(using: .utf8))
            let array = try JSONDecoder().decode([ListEntryJSON].self, from: data)
            try #require(array.count == 1)
            let entry = array[0]
            #expect(
                entry.identity == "some-lib",
                "expected identity `some-lib`; got \(entry.identity)",
            )
            #expect(
                entry.kind == "path",
                "expected kind `path`; got \(entry.kind)",
            )
            #expect(
                entry.location.contains("external/local-some-lib"),
                "expected location to contain `external/local-some-lib`; got \(entry.location)",
            )
        }
    }

    /// `swift workspace override remove <identity>` deletes
    /// the entry; when it was the only entry, the file itself is
    /// removed. A subsequent `list` reverts to the empty-state hint.
    @Test(
        .tags(
            .Feature.Command.Package.Resolve,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s08_c_workspaceOverrideRemove_lastEntry_deletesFileAndListsEmpty(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S08_WorkspaceOverrides") { fixturePath in
            let overridesFile = fixturePath.appending(
                components: ".swiftpm", "configuration", "workspace-overrides.json",
            )
            try localFileSystem.removeFileTree(overridesFile)

            _ = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: [
                    "override", "add", "path",
                    "some-lib", "external/local-some-lib",
                ],
                buildSystem: buildSystem,
            )
            _ = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: ["override", "remove", "some-lib"],
                buildSystem: buildSystem,
            )
            expectFileDoesNotExist(at: overridesFile)

            let (stdout, _) = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: ["override", "list"],
                buildSystem: buildSystem,
            )
            #expect(
                stdout.contains("(no overrides declared)"),
                "expected empty-state hint after remove; got stdout=\(stdout)",
            )
        }
    }

    // MARK: - Slice 12b: member-declared dep override — E2E

    /// `swift package workspace override add path` on a dep declared in a
    /// *member* `Package.swift` (not in `Workspace.swift`) redirects it to
    /// a local filesystem path, so `swift build` succeeds without contacting
    /// the nonexistent source-control URL. This exercises the extended override
    /// scope introduced in Phase 8D: the override pipeline must scan each
    /// member's direct dependencies, not only workspace-level ones.
    @Test(
        .tags(
            .Feature.Command.Package.Resolve,
        ),
    )
    func s08_d_memberDepOverride_buildSucceedsWithoutFetch() async throws {
        let buildSystem = BuildSystemProvider.Kind.swiftbuild
        try await fixture(name: "Workspaces/S08_MemberDepOverride") { testPath in
            let fixturePath = testPath.appending("workspace")
            let newOverridePath = testPath.appending(components: "external","some-dep")
            // Arrange: add the override pointing to the local checkout.
            // Path is relative to the workspace root (per the override
            // JSON parser's resolveOverride semantics) and points UP out
            // of the workspace directory into the sibling external tree.
            _ = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: [
                    "override",
                    "add",
                    "path",
                    "some-dep",
                    newOverridePath.pathString,
                ],
                buildSystem: buildSystem,
            )

            // Act: verify the overrides file was written, then build
            let overridesFile = fixturePath.appending(
                components: ".swiftpm", "configuration", "workspace-overrides.json",
            )
            try requireFileExists(at: overridesFile)

            try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                buildSystem: buildSystem,
            )

            // Assert: the binary prints the local greeting (not the nonexistent URL's)
            let binPath = try await getBinPath(
                fixturePath,
                configuration: .debug,
                buildSystem: buildSystem,
            )
            let output = try await AsyncProcess.checkNonZeroExit(
                args: binPath.appending("app").pathString,
            ).withSwiftLineEnding
            #expect(
                output == "hello from local some-dep\n",
                "expected local some-dep greeting after member-dep override; got: \(output)",
            )
        }
    }

    // MARK: - Slice 12a: help-text contract

    /// Each `swift package workspace override add` help page must not
    /// mention "workspace-level" — overrides now apply to both
    /// workspace-declared and member-declared direct dependencies, so
    /// the old qualifier is misleading. Parameterized over four help
    /// invocations: the `add` group itself plus its three leaf
    /// subcommands (`path`, `url`, `registry`), because ArgumentParser
    /// surfaces each command's `abstract:` and `@Argument(help:)`
    /// independently on their own `--help` page.
    @Test(
        .tags(
            .Feature.Command.Package.Resolve,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
        [
            WorkspaceOverrideHelpCase(
                label: "add --help",
                extraArgs: ["override", "add", "--help"],
            ),
            WorkspaceOverrideHelpCase(
                label: "add path --help",
                extraArgs: ["override", "add", "path", "--help"],
            ),
            WorkspaceOverrideHelpCase(
                label: "add url --help",
                extraArgs: ["override", "add", "url", "--help"],
            ),
            WorkspaceOverrideHelpCase(
                label: "add registry --help",
                extraArgs: ["override", "add", "registry", "--help"],
            ),
        ],
    )
    func workspace_override_add_helpText_doesNotMentionWorkspaceLevel(
        buildSystem: BuildSystemProvider.Kind,
        testCase: WorkspaceOverrideHelpCase,
    ) async throws {
        try await fixture(name: "Workspaces/S08_WorkspaceOverrides") { fixturePath in
            let (stdout, _) = try await executeSwiftWorkspace(
                fixturePath,
                extraArgs: testCase.extraArgs,
                buildSystem: buildSystem,
            )
            #expect(
                stdout.contains("workspace-level") == false,
                "'\(testCase.label)' should not mention 'workspace-level' — overrides now cover member deps too; got stdout=\(stdout)",
            )
        }
    }

    /// `swift package workspace init` (bare, no `--members`) creates
    /// a `Workspace.swift` file in the current working directory with
    /// an empty `members: []` list. Verifies the happy-path scaffold
    /// of the CLI.
    @Test(
        .tags(
            .Feature.Command.Package.Init,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s09_workspaceInit_bareInit_scaffoldsEmptyManifest(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await testWithTemporaryDirectory { tempDir in
            _ = try await executeSwiftWorkspace(
                tempDir,
                configuration: .debug,
                extraArgs: ["init"],
                buildSystem: buildSystem,
            )

            let manifestPath = tempDir.appending("Workspace.swift")
            expectFileExists(at: manifestPath)
            let manifestContent: String = try localFileSystem.readFileContents(manifestPath)
            #expect(
                manifestContent.contains("members: []"),
                "expected empty members list; got manifest=\(manifestContent)",
            )
        }
    }

    /// `swift package workspace init --members packages/lib-a
    /// --members packages/app` scaffolds both member directories with
    /// their `Package.swift` files and lists them in the
    /// `Workspace.swift` manifest.
    @Test(
        .tags(
            .Feature.Command.Package.Init,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s09_workspaceInit_scaffoldsWorkspaceManifestAndMembers(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await testWithTemporaryDirectory { tempDir in
            _ = try await executeSwiftWorkspace(
                tempDir,
                configuration: .debug,
                extraArgs: [
                    "init",
                    "--members", "packages/lib-a", "packages/app",
                ],
                buildSystem: buildSystem,
            )

            let workspaceManifest = tempDir.appending("Workspace.swift")
            expectFileExists(at: workspaceManifest)
            let manifestContent: String = try localFileSystem.readFileContents(workspaceManifest)
            #expect(
                manifestContent.contains("\"packages/lib-a\""),
                "expected lib-a in members list; got manifest=\(manifestContent)",
            )
            #expect(
                manifestContent.contains("\"packages/app\""),
                "expected app in members list; got manifest=\(manifestContent)",
            )

            expectFileExists(
                at: tempDir.appending(try RelativePath(validating: "packages/lib-a/Package.swift")),
            )
            expectFileExists(
                at: tempDir.appending(try RelativePath(validating: "packages/app/Package.swift")),
            )
        }
    }

    /// `swift package workspace init` refuses to overwrite an existing
    /// `Workspace.swift` — users must remove the existing file
    /// themselves. Guards against destroying in-progress workspace
    /// authoring by an accidental re-run.
    @Test(
        .tags(
            .Feature.Command.Package.Init,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s09_workspaceInit_whenWorkspaceManifestExists_fails(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await testWithTemporaryDirectory { tempDir in
            try localFileSystem.writeFileContents(
                tempDir.appending("Workspace.swift"),
                string: "// pre-existing\n",
            )

            await #expect(throws: (any Error).self) {
                try await executeSwiftWorkspace(
                    tempDir,
                    configuration: .debug,
                    extraArgs: ["init"],
                    buildSystem: buildSystem,
                )
            }

            let manifestContent: String = try localFileSystem.readFileContents(
                tempDir.appending("Workspace.swift"),
            )
            #expect(
                manifestContent == "// pre-existing\n",
                "pre-existing Workspace.swift must not be overwritten; got \(manifestContent)",
            )
        }
    }

    /// `swift package workspace init --package-path <dir>` scaffolds
    /// into `<dir>` rather than the caller's current working directory.
    /// Creates `<dir>` if it doesn't exist (matches `swift package
    /// init` behaviour for the same flag). Locks in that the workspace
    /// init CLI honors the global `--package-path` option.
    @Test(
        .tags(
            .Feature.Command.Package.Init,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s09_workspaceInit_respectsPackagePath(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await testWithTemporaryDirectory { tempDir in
            let nested = tempDir.appending("nested-workspace")

            _ = try await executeSwiftWorkspace(
                tempDir,
                configuration: .debug,
                extraArgs: [
                    "--package-path", nested.pathString,
                    "init",
                    "--members", "packages/lib-a",
                ],
                buildSystem: buildSystem,
            )

            expectFileExists(at: nested.appending("Workspace.swift"))
            expectFileExists(
                at: nested.appending(try RelativePath(validating: "packages/lib-a/Package.swift")),
            )
            expectFileDoesNotExist(at: tempDir.appending("Workspace.swift"))
        }
    }

    // MARK: - Slice 10: `swift package show-dependencies` workspace awareness

    /// `swift package show-dependencies --format text` at the workspace
    /// root must include every workspace member — the pre-workspaces
    /// implementation picked the arbitrary "first" root package via
    /// `graph.rootPackages.startIndex`, silently dropping every other
    /// member. Uses S02 (two members with a member-to-member dep) so
    /// we can assert both members' trees are rendered.
    ///
    /// In workspace context, each member's tree is preceded by a
    /// `--- <identity> ---` header so the sections are visually
    /// distinguishable in the concatenated output.
    @Test(
        .tags(
            .Feature.Command.Package.ShowDependencies,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s10_showDependenciesTextIncludesAllMembersWithHeaders(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S10_ShowDependencies") { fixturePath in
            let (stdout, _) = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["show-dependencies", "--format", "text"],
                buildSystem: buildSystem,
            )

            #expect(
                stdout.contains("--- app ---"),
                "expected 'app' section header; got stdout=\(stdout)",
            )
            #expect(
                stdout.contains("--- lib-a ---"),
                "expected 'lib-a' section header; got stdout=\(stdout)",
            )
        }
    }

    /// In workspace context, a dep that resolves to another workspace
    /// member (via `.package(workspaceMember:)`) gets a trailing
    /// ` [workspace member]` tag so a reader can tell at a glance which
    /// entries live in the workspace vs. come from source control /
    /// registry / filesystem. S02's app→lib-a edge is exactly this
    /// case. Non-workspace-member deps carry no tag.
    @Test(
        .tags(
            .Feature.Command.Package.ShowDependencies,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s10_showDependenciesTextTagsWorkspaceMemberDeps(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S10_ShowDependencies") { fixturePath in
            let (stdout, _) = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["show-dependencies", "--format", "text"],
                buildSystem: buildSystem,
            )

            #expect(
                stdout.contains("lib-a") && stdout.contains("[workspace member]"),
                "expected workspace-member tag on lib-a in app's dep tree; got stdout=\(stdout)",
            )
        }
    }

    /// `show-dependencies` invoked from inside a workspace member
    /// directory scopes output to that member's dep tree only — mirrors
    /// Slice 4's Case A behaviour for `swift build`. Uses S04 (two
    /// members; only `app` depends on `some-lib`) and runs from
    /// `packages/app`. Expect only `app`'s section, no `--- lib-a ---`
    /// header.
    @Test(
        .tags(
            .Feature.Command.Package.ShowDependencies,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s10_showDependenciesInsideMemberScopedToMember(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S10_ShowDependencies") { fixturePath in
            let memberPath = fixturePath.appending(components: "packages", "app")

            let (stdout, _) = try await executeSwiftPackage(
                memberPath,
                configuration: .debug,
                extraArgs: ["show-dependencies", "--format", "text"],
                buildSystem: buildSystem,
            )

            #expect(
                stdout.contains("some-lib"),
                "expected app's dep `some-lib` in output; got stdout=\(stdout)",
            )
            #expect(
                stdout.contains("--- lib-a ---") == false,
                "expected NO `lib-a` header (scoped to app); got stdout=\(stdout)",
            )
        }
    }

    /// `swift package show-dependencies --package <identity>` restricts
    /// output to the named workspace member from anywhere — overrides
    /// both the workspace-root all-members default AND any Case A CWD
    /// focus. Mirrors Slice 5's `--package` selector for `swift build`.
    /// S02 has both `app` and `lib-a` as members; selecting `lib-a`
    /// yields only its tree.
    @Test(
        .tags(
            .Feature.Command.Package.ShowDependencies,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s10_showDependenciesWithPackageSelector(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S10_ShowDependencies") { fixturePath in
            let (stdout, _) = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: [
                    "show-dependencies",
                    "--format", "text",
                    "--package", "lib-a",
                ],
                buildSystem: buildSystem,
            )

            #expect(
                stdout.contains("--- app ---") == false,
                "expected NO `app` header (scoped to lib-a via --package); got stdout=\(stdout)",
            )
        }
    }

    /// `show-dependencies --format flatlist` at the workspace root
    /// emits a deduplicated union of every in-scope member's
    /// transitive dep identities. Uses S03 (both `app` and `lib-a`
    /// inherit the same `some-lib`) so a naive walk that concatenates
    /// each root's tree without dedup would emit `some-lib` twice —
    /// the assertion pins the emitted line count to prove dedup is
    /// applied.
    @Test(
        .tags(
            .Feature.Command.Package.ShowDependencies,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s10_showDependenciesFlatListIsDeduplicatedUnion(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S10_ShowDependencies") { fixturePath in
            let (stdout, _) = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["show-dependencies", "--format", "flatlist"],
                buildSystem: buildSystem,
            )

            let lines = stdout
                .split(whereSeparator: { $0.isNewline })
                .map(String.init)
            let someLibCount = lines.filter { $0 == "some-lib" }.count
            #expect(
                someLibCount == 1,
                "expected `some-lib` to appear exactly once in the deduplicated flatlist; got count=\(someLibCount) lines=\(lines)",
            )
        }
    }

    /// `show-dependencies --format dot` at the workspace root wraps
    /// each member in a `subgraph cluster_<sanitized_identity> { ... }`
    /// block inside the outer `digraph`. The plan calls this out as
    /// the visible marker of multi-root Dot output; the unit test
    /// `showDependencies_dot_multipleRoots_emitsSubgraphClusters`
    /// covers the same behaviour at the dumper level, and this e2e
    /// pins it end-to-end through the CLI.
    @Test(
        .tags(
            .Feature.Command.Package.ShowDependencies,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s10_showDependenciesDotEmitsSubgraphClusters(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S10_ShowDependencies") { fixturePath in
            let (stdout, _) = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["show-dependencies", "--format", "dot"],
                buildSystem: buildSystem,
            )

            #expect(
                stdout.contains("digraph DependenciesGraph"),
                "expected outer `digraph DependenciesGraph` wrapper; got stdout=\(stdout)",
            )
            #expect(
                stdout.contains("subgraph cluster_app"),
                "expected `subgraph cluster_app` block for the app member; got stdout=\(stdout)",
            )
            #expect(
                stdout.contains("subgraph cluster_lib_a"),
                "expected `subgraph cluster_lib_a` block for the lib-a member (hyphen sanitized to underscore); got stdout=\(stdout)",
            )
        }
    }

    /// Non-workspace-member deps must NOT carry the `[workspace
    /// member]` tag in text output — the tag is reserved for entries
    /// that resolve to another declared member of the same workspace.
    /// S10's `some-lib` is a file-system path dep declared at the
    /// workspace level and inherited into each member's tree; every
    /// line containing `some-lib` must be tag-free.
    @Test(
        .tags(
            .Feature.Command.Package.ShowDependencies,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s10_showDependenciesNonMemberPathDepsHaveNoWorkspaceMemberTag(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S10_ShowDependencies") { fixturePath in
            let (stdout, _) = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["show-dependencies", "--format", "text"],
                buildSystem: buildSystem,
            )

            let someLibLines = stdout
                .split(whereSeparator: { $0.isNewline })
                .map(String.init)
                .filter { $0.contains("some-lib") }
            try #require(!someLibLines.isEmpty)
            #expect(
                someLibLines.allSatisfy { !$0.contains("[workspace member]") },
                "expected NO `[workspace member]` tag on `some-lib` (a file-system, non-member dep); got lines=\(someLibLines)",
            )
        }
    }

    // MARK: - Slice 11: `swift package update` workspace awareness

    /// `swift package update` invoked at a workspace root writes
    /// `Package.resolved` at the workspace root (not per-member) and
    /// resolves every workspace-level dependency. This is the smoke
    /// test for Phase 11 — Slice 8 already routed
    /// `getResolvedVersionsFile()` to the workspace root, so the
    /// update command should surface the workspace-scoped
    /// `Package.resolved` out of the box.
    @Test(
        .tags(
            .Feature.Command.Package.Resolve,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s11_updateWorkspaceUpdatesAllMembers(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S08_ResolveAndWarnings") { fixturePath in
            try Self.initializeExternalRepo(at: fixturePath.appending(components: "external", "some-lib"))

            _ = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["update"],
                buildSystem: buildSystem,
            )

            let workspaceResolved = fixturePath.appending("Package.resolved")
            expectFileExists(at: workspaceResolved)
            let contents: String = try localFileSystem.readFileContents(workspaceResolved)
            #expect(
                contents.contains("some-lib"),
                "expected `some-lib` pin in workspace Package.resolved; got contents=\(contents)",
            )

            // No per-member Package.resolved leaks out — the workspace
            // is the single source of truth after Slice 8's routing.
            for member in ["app", "lib-a", "lib-b"] {
                let memberResolved = fixturePath.appending(
                    try RelativePath(validating: "packages/\(member)/Package.resolved"),
                )
                expectFileDoesNotExist(at: memberResolved)
            }
        }
    }

    /// `swift package update --package app` runs cleanly through the
    /// CLI's `--package` selector on the S11 fixture (two members
    /// with distinct workspace-inherited deps: `app` → `some-lib`,
    /// `lib-a` → `other-lib`). Both pins land in the workspace-root
    /// `Package.resolved` — the subtree-restricted update does not
    /// drop the sibling member's pin. Full semantic verification of
    /// scope restriction lives in `UpdateSubsetSelectionTests`; this
    /// e2e proves the CLI end-to-end plumbing (graph load →
    /// transitive-dep walk → `packages: [String]` translation) runs
    /// without regressions.
    @Test(
        .tags(
            .Feature.Command.Package.Resolve,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s11_updateWithPackageSelectorRestrictsToMemberSubtree(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S11_Update") { fixturePath in
            try Self.initializeExternalRepo(at: fixturePath.appending(components: "external", "some-lib"))
            try Self.initializeExternalRepo(at: fixturePath.appending(components: "external", "other-lib"))

            _ = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["update", "--package", "app"],
                buildSystem: buildSystem,
            )

            let workspaceResolved = fixturePath.appending("Package.resolved")
            expectFileExists(at: workspaceResolved)
            let contents: String = try localFileSystem.readFileContents(workspaceResolved)
            #expect(
                contents.contains("some-lib"),
                "expected `some-lib` pin (app's inherited dep) after --package app update; got contents=\(contents)",
            )
            #expect(
                contents.contains("other-lib"),
                "expected `other-lib` pin (lib-a's inherited dep) to remain in workspace Package.resolved after --package app update; got contents=\(contents)",
            )
        }
    }

    /// `swift package update` invoked from inside a workspace member
    /// picks up the CWD focus (Slice 4) and applies the same subtree
    /// restriction as `--package app`. Uses the same S11 fixture as
    /// `s11_updateWithPackageSelectorRestrictsToMemberSubtree`; runs
    /// from `packages/app` instead of passing `--package`. Since 11b's
    /// pure decision fn accepts both `selectedPackage` and
    /// `workspaceMemberFocus` as peer inputs, no additional CLI code
    /// is needed for 11c — only the observable end-to-end assertion.
    @Test(
        .tags(
            .Feature.Command.Package.Resolve,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s11_updateFromInsideMemberScopedToMember(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S11_Update") { fixturePath in
            try Self.initializeExternalRepo(at: fixturePath.appending(components: "external", "some-lib"))
            try Self.initializeExternalRepo(at: fixturePath.appending(components: "external", "other-lib"))
            let appPath = fixturePath.appending(components: "packages", "app")

            _ = try await executeSwiftPackage(
                appPath,
                configuration: .debug,
                extraArgs: ["update"],
                buildSystem: buildSystem,
            )

            let workspaceResolved = fixturePath.appending("Package.resolved")
            expectFileExists(at: workspaceResolved)
            let contents: String = try localFileSystem.readFileContents(workspaceResolved)
            #expect(
                contents.contains("some-lib"),
                "expected `some-lib` pin (app's inherited dep) after CWD-inside-app update; got contents=\(contents)",
            )
            #expect(
                contents.contains("other-lib"),
                "expected `other-lib` pin (lib-a's inherited dep) to remain after CWD-inside-app update; got contents=\(contents)",
            )
        }
    }

    // MARK: - Slice 12: `swift package clean` workspace awareness

    /// `swift package clean` invoked at a workspace root removes the
    /// workspace-scoped `<workspace-root>/.build/` directory that
    /// every member shares. Slice 4 routed the build output to the
    /// workspace root and Slice 8 routed `Package.resolved` there;
    /// this smoke test verifies `clean` sees the same location.
    /// Should pass without any Clean.swift changes.
    @Test(
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s12_cleanRemovesWorkspaceBuildDirectory(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S01_MinimalTwoMembers") { fixturePath in
            let configuration = BuildConfiguration.debug
            let workspaceBuildDir = fixturePath.appending(".build")
            try requireDirectoryDoesNotExist(at: workspaceBuildDir)
            try await executeSwiftBuild(
                fixturePath,
                configuration: configuration,
                extraArgs: [
                    "--scratch-path",
                    workspaceBuildDir.pathString
                ],
                buildSystem: buildSystem,
            )
            expectDirectoryExists(at: workspaceBuildDir)

            _ = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["clean"],
                buildSystem: buildSystem,
            )

            // Get the bin path
            let binPath = try await getBinPath(
                fixturePath,
                configuration: configuration,
                buildSystem: buildSystem,
            )
            expectDirectoryDoesNotExist(at: binPath)
        }
    }

    /// `swift package clean` invoked from inside a workspace member
    /// emits an explicit "cleaning workspace build directory: <path>"
    /// info line pointing at the shared workspace-root `.build/`. Users
    /// working out of a member subdirectory otherwise see no signal of
    /// what got removed since the workspace scratch location isn't
    /// visible from there.
    @Test(
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s12_cleanFromInsideMemberEmitsExplicitPath(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S01_MinimalTwoMembers") { fixturePath in
            let memberPath = fixturePath.appending(components: "packages", "lib-a")

            let (_, stderr) = try await executeSwiftPackage(
                memberPath,
                configuration: .debug,
                extraArgs: [
                    "--verbose",
                    "clean",
                ],
                buildSystem: buildSystem,
            )

            // The path segment in the diagnostic message goes through
            // macOS's `/private/var` symlink resolution en route to
            // stderr, while `fixturePath` here still points at the
            // unresolved `/var` prefix. Assert on the prefix (which
            // pins the message shape) and on the workspace-root
            // basename + `.build` (which pins the path is the
            // workspace-root one, not a member's).
            let expectedPrefix = "cleaning workspace build directory:"
            #expect(
                stderr.contains(expectedPrefix),
                "expected `\(expectedPrefix)` in stderr; got stderr=\(stderr)",
            )
            #expect(
                stderr.contains("\(fixturePath.basename)/.build"),
                "expected workspace-root `.build/` segment in stderr; got stderr=\(stderr)",
            )
        }
    }

    /// `swift package clean --package <identity>` under a workspace
    /// emits an info line explaining the flag is a no-op (the shared
    /// `.build/` is cleaned regardless) and still exits 0. Info, not
    /// warning/error — the request is benign and the CLI does the
    /// right thing (clean everything) either way.
    @Test(
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s12_cleanWithPackageSelectorEmitsInfoLineButSucceeds(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S01_MinimalTwoMembers") { fixturePath in
            let configuration = BuildConfiguration.debug
            let workspaceBuildDir = fixturePath.appending(".build")
            try requireDirectoryDoesNotExist(at: workspaceBuildDir)
            try await executeSwiftBuild(
                fixturePath,
                configuration: configuration,
                extraArgs: [
                    "--scratch-path",
                    workspaceBuildDir.pathString,
                ],
                buildSystem: buildSystem,
            )
            expectDirectoryExists(at: workspaceBuildDir)

            let (_, stderr) = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: [
                    "--verbose",
                    "clean",
                    "--package", "lib-a",
                ],
                buildSystem: buildSystem,
            )

            let expectedDiagnostic = Basics.Diagnostic.packageSelectorHasNoEffectForClean()
            #expect(
                stderr.contains(expectedDiagnostic.message),
                "expected `--package has no effect for 'clean'` info line in stderr; got stderr=\(stderr)",
            )
            // Get the bin path
            let binPath = try await getBinPath(
                fixturePath,
                configuration: configuration,
                buildSystem: buildSystem,
            )
            expectDirectoryDoesNotExist(at: binPath)
        }
    }

    // MARK: - Slice 13: `swift package describe` workspace awareness

    /// `swift package describe` at a workspace root emits a
    /// description block per in-scope member, each preceded by a
    /// `--- <identity> ---` header. Fixes the pre-Slice-13 behaviour
    /// where `Describe.run()` picked `getWorkspaceRoot().packages.first`
    /// and dropped every other member.
    @Test(
        .tags(
            Tag.Feature.Command.Package.Describe,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s13_describeWorkspaceEmitsAllMembers(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S13_Describe") { fixturePath in
            let (stdout, _) = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["describe"],
                buildSystem: buildSystem,
            )

            #expect(
                stdout.contains("--- app ---"),
                "expected `app` header; got stdout=\(stdout)",
            )
            #expect(
                stdout.contains("--- lib-a ---"),
                "expected `liba` header (identity strips the dash from `lib-a`); got stdout=\(stdout)",
            )
        }
    }

    /// `swift package describe` invoked from inside a workspace
    /// member scopes to that member alone — no header (single-root
    /// output is unwrapped) and no sibling-member content.
    @Test(
        .tags(
            Tag.Feature.Command.Package.Describe,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s13_describeInsideMemberScopedToMember(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S13_Describe") { fixturePath in
            let memberPath = fixturePath.appending(components: "packages", "app")

            let (stdout, _) = try await executeSwiftPackage(
                memberPath,
                configuration: .debug,
                extraArgs: ["describe"],
                buildSystem: buildSystem,
            )

            #expect(
                stdout.contains("--- liba ---") == false,
                "expected NO `liba` header (scoped to app); got stdout=\(stdout)",
            )
            #expect(
                stdout.contains("--- app ---") == false,
                "expected NO `app` header on single-root output; got stdout=\(stdout)",
            )
            #expect(
                stdout.contains("Name: app"),
                "expected app's description in stdout; got stdout=\(stdout)",
            )
        }
    }

    /// `swift package describe --package <identity>` restricts output
    /// to that member from anywhere. Overrides an implicit CWD focus.
    @Test(
        .tags(
            Tag.Feature.Command.Package.Describe,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s13_describeWithPackageSelector(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S13_Describe") { fixturePath in
            let (stdout, _) = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["describe", "--package", "lib-a"],
                buildSystem: buildSystem,
            )

            #expect(
                stdout.contains("--- app ---") == false,
                "expected NO `app` header (scoped to liba via --package); got stdout=\(stdout)",
            )
            #expect(
                stdout.contains("Name: lib-a"),
                "expected lib-a's description in stdout; got stdout=\(stdout)",
            )
        }
    }

    /// `swift package describe --type json` at a workspace root emits
    /// a JSON array of per-member `DescribedPackage` objects. Single-
    /// package output remains a top-level object — that regression is
    /// covered by the existing `describe()` / `describeJson()` tests
    /// in `PackageCommandTests`.
    @Test(
        .tags(
            Tag.Feature.Command.Package.Describe,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s13_describeJsonMultipleMembers_emitsArrayOfPerMemberObjects(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S13_Describe") { fixturePath in
            let (stdout, _) = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["describe", "--type", "json"],
                buildSystem: buildSystem,
            )

            let data = try #require(stdout.data(using: .utf8))
            let parsed = try JSONSerialization.jsonObject(with: data)
            let array = try #require(parsed as? [[String: Any]])
            try #require(array.count == 2)
            let names = Set(array.compactMap { $0["name"] as? String })
            #expect(
                names == ["app", "lib-a"],
                "expected `app` and `lib-a` names in JSON array; got names=\(names)",
            )
        }
    }

    /// `swift package describe --type mermaid` at a workspace root
    /// emits each member's diagram concatenated with a blank-line
    /// separator. Mermaid has no per-diagram header convention, so
    /// consumers use the diagram bodies themselves to identify
    /// members (each rendered graph names its package).
    @Test(
        .tags(
            Tag.Feature.Command.Package.Describe,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s13_describeMermaidMultipleMembers_concatsPerMember(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S13_Describe") { fixturePath in
            let (stdout, _) = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["describe", "--type", "mermaid"],
                buildSystem: buildSystem,
            )

            #expect(
                stdout.contains("app"),
                "expected `app` mentioned in concatenated mermaid diagrams; got stdout=\(stdout)",
            )
            #expect(
                stdout.contains("lib-a"),
                "expected `lib-a` mentioned in concatenated mermaid diagrams; got stdout=\(stdout)",
            )
        }
    }

    /// `swift package dump-package` invoked at a workspace root with
    /// more than one member and no `--package` selector is ambiguous:
    /// `dump-package` emits exactly one manifest per invocation. The
    /// command must fail with a diagnostic listing the known member
    /// identities so the user can re-run with `--package <identity>`.
    @Test(
        .tags(
            .Feature.Command.Package.DumpPackage,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s14_dumpPackageAtWorkspaceRootWithoutSelectorErrors(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S14_DumpPackage") { fixturePath in
            await #expect(throws: (any Error).self) {
                try await executeSwiftPackage(
                    fixturePath,
                    configuration: .debug,
                    extraArgs: ["dump-package"],
                    buildSystem: buildSystem,
                )
            }
        }
    }

    /// `swift package dump-package --package <identity>` at a
    /// workspace root selects that member's manifest and dumps its
    /// parsed JSON. Locks in that the CLI selector wins over CWD.
    @Test(
        .tags(
            .Feature.Command.Package.DumpPackage,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s14_dumpPackageWithSelectorOutputsMemberManifest(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S14_DumpPackage") { fixturePath in
            let (stdout, _) = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["dump-package", "--package", "lib-a"],
                buildSystem: buildSystem,
            )

            let data = try #require(stdout.data(using: .utf8))
            let parsed = try JSONSerialization.jsonObject(with: data)
            let object = try #require(parsed as? [String: Any])
            let name = try #require(object["name"] as? String)
            #expect(
                name == "lib-a",
                "expected `lib-a` manifest; got name=\(name)",
            )
        }
    }

    /// `swift package dump-package` invoked from inside a workspace
    /// member auto-selects that member via the Slice 4 CWD focus —
    /// no `--package` flag needed. Verifies the CWD-focus path.
    @Test(
        .tags(
            .Feature.Command.Package.DumpPackage,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s14_dumpPackageFromInsideMemberAutoSelects(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S14_DumpPackage") { fixturePath in
            let memberPath = fixturePath.appending(components: "packages", "app")

            let (stdout, _) = try await executeSwiftPackage(
                memberPath,
                configuration: .debug,
                extraArgs: ["dump-package"],
                buildSystem: buildSystem,
            )

            let data = try #require(stdout.data(using: .utf8))
            let parsed = try JSONSerialization.jsonObject(with: data)
            let object = try #require(parsed as? [String: Any])
            let name = try #require(object["name"] as? String)
            #expect(
                name == "app",
                "expected `app` manifest (auto-selected from CWD); got name=\(name)",
            )
        }
    }

    /// `swift package dump-package` at a workspace root that has a
    /// single member auto-selects that member — no `--package` flag
    /// required. Locks in that the ambiguity-error path only fires
    /// when the workspace has 2+ members, matching the pre-workspaces
    /// (non-workspace) invocation shape.
    @Test(
        .tags(
            .Feature.Command.Package.DumpPackage,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s14_dumpPackageAtSingleMemberWorkspaceRootAutoSelects(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S14_DumpPackageSingle") { fixturePath in
            let (stdout, _) = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["dump-package"],
                buildSystem: buildSystem,
            )

            let data = try #require(stdout.data(using: .utf8))
            let parsed = try JSONSerialization.jsonObject(with: data)
            let object = try #require(parsed as? [String: Any])
            let name = try #require(object["name"] as? String)
            #expect(
                name == "app",
                "expected the sole member `app` to be auto-selected; got name=\(name)",
            )
        }
    }

    /// `swift package workspace dump-workspace` prints the parsed
    /// `Workspace.swift` as JSON regardless of where inside the
    /// workspace tree it's invoked from. The top-level object exposes
    /// `path`, `toolsVersion`, `members`, and `dependencies`; each
    /// member entry carries `identity` and `path`.
    ///
    /// Parameterized across three invocation sites:
    /// 1. **workspace root** — canonical location.
    /// 2. **workspace non-member subdirectory** (`packages/`) — inside
    ///    the workspace tree but not inside any member. Verifies that
    ///    workspace discovery walks up correctly from a non-member CWD.
    /// 3. **member root** (`packages/app/`) — verifies that CWD-inside-
    ///    a-member (Slice 4 focus) doesn't change what `dump-workspace`
    ///    prints; the workspace manifest is the same everywhere.
    @Test(
        .tags(
            .Feature.Command.Package.DumpPackage,
        ),
        arguments: [
            ("workspace root", [String]()),
            ("workspace non-member", ["packages"]),
            ("member root", ["packages", "app"]),
        ],
    )
    func s14_dumpWorkspace_emitsWorkspaceManifestAsJson(
        invocationSite: (name: String, cwdComponents: [String]),
    ) async throws {
        let buildSystem = BuildSystemProvider.Kind.swiftbuild
        try await fixture(name: "Workspaces/S14_DumpPackage") { fixturePath in
            let cwd: AbsolutePath
            if invocationSite.cwdComponents.isEmpty {
                cwd = fixturePath
            } else {
                cwd = fixturePath.appending(components: invocationSite.cwdComponents)
            }

            let (stdout, _) = try await executeSwiftWorkspace(
                cwd,
                configuration: .debug,
                extraArgs: ["dump-workspace"],
                buildSystem: buildSystem,
            )

            let data = try #require(stdout.data(using: .utf8))
            let parsed = try JSONSerialization.jsonObject(with: data)
            let object = try #require(parsed as? [String: Any])
            let members = try #require(object["members"] as? [[String: Any]])
            try #require(
                members.count == 2,
                "expected 2 members from invocation site \(invocationSite.name); got \(members.count)",
            )
            let identities = Set(members.compactMap { $0["identity"] as? String })
            #expect(
                identities == ["app", "lib-a"],
                "expected workspace member identities `app` and `lib-a` from invocation site \(invocationSite.name); got identities=\(identities)",
            )
        }
    }

    /// `swift package workspace dump-workspace` invoked outside of
    /// any workspace (no `Workspace.swift` discoverable up the tree)
    /// fails with a user-actionable error. Mirrors the other
    /// `swift package workspace <sub>` commands.
    @Test(
        .tags(
            .Feature.Command.Package.DumpPackage,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s14_dumpWorkspace_outsideWorkspaceFails(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await testWithTemporaryDirectory { tempDir in
            await #expect(throws: (any Error).self) {
                try await executeSwiftWorkspace(
                    tempDir,
                    configuration: .debug,
                    extraArgs: ["dump-workspace"],
                    buildSystem: buildSystem,
                )
            }
        }
    }

    /// `swift package workspace` exposes the workspace-aware
    /// commands from the top-level `swift package` tree without
    /// duplicating the implementation. `resolve`, `update`, `clean`,
    /// and `reset` are registered in both parent lists — this test
    /// walks each command and asserts that `swift workspace <sub>`
    /// succeeds against the S14 fixture, mirroring the behaviour of
    /// `swift package <sub>`. Locks in the reuse: if a future refactor
    /// moves the struct or changes its registration, the workspace-scoped
    /// path fails visibly.
    @Test(
        .tags(
            .Feature.Command.Package.General,
        ),
        arguments: [
            "resolve",
            "update",
            "clean",
            "reset",
            "show-dependencies",
            "config",
        ],
    )
    func workspace_reusesTopLevelPackageSubcommand(
        subcommand: String,
    ) async throws {
        let buildSystem = BuildSystemProvider.Kind.swiftbuild
        try await fixture(name: "Workspaces/S14_DumpPackage") { fixturePath in
            _ = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: [subcommand],
                buildSystem: buildSystem,
            )
        }
    }

    /// `swift package config set-mirror` under a workspace must
    /// anchor the mirror to the workspace root's
    /// `.swiftpm/configuration/mirrors.json` — a single shared file
    /// every member reads. Before workspace-aware routing landed the
    /// command threw at a workspace root because there is no
    /// `Package.swift`, and from inside a member it wrote to
    /// `<member>/.swiftpm/configuration/mirrors.json` where the
    /// sibling members (and workspace-root resolution) would never
    /// see it.
    ///
    /// Parameterized across two invocation sites so a stray CWD-
    /// specific fallback would fail visibly:
    /// 1. **workspace root** — canonical location.
    /// 2. **member root** (`packages/app/`) — verifies that a mirror
    ///    set from inside a member is still routed to the workspace
    ///    root, not to the member's `.swiftpm/`.
    @Test(
        .tags(
            .Feature.Command.Package.General,
        ),
        arguments: [
            ("workspace root", [String]()),
            ("member root", ["packages", "app"]),
        ],
    )
    func workspace_configSetMirror_writesToWorkspaceRoot(
        invocationSite: (name: String, cwdComponents: [String]),
    ) async throws {
        let buildSystem = BuildSystemProvider.Kind.swiftbuild
        try await fixture(name: "Workspaces/S14_DumpPackage") { fixturePath in
            let cwd: AbsolutePath
            if invocationSite.cwdComponents.isEmpty {
                cwd = fixturePath
            } else {
                cwd = fixturePath.appending(components: invocationSite.cwdComponents)
            }

            _ = try await executeSwiftPackage(
                cwd,
                configuration: .debug,
                extraArgs: [
                    "config",
                    "set-mirror",
                    "--original",
                    "https://github.com/example/original",
                    "--mirror",
                    "https://github.com/example/mirror",
                ],
                buildSystem: buildSystem,
            )

            let workspaceMirrors = fixturePath.appending(
                components: ".swiftpm", "configuration", "mirrors.json",
            )
            expectFileExists(
                at: workspaceMirrors,
                "workspace-root mirrors file missing from invocation site \(invocationSite.name)",
            )
            // Guard against per-member fallback: a mirror set from
            // inside a member must NOT be written to that member's
            // own `.swiftpm/configuration/mirrors.json`.
            if invocationSite.cwdComponents.isEmpty == false {
                let memberMirrors = cwd.appending(
                    components: ".swiftpm", "configuration", "mirrors.json",
                )
                expectFileDoesNotExist(
                    at: memberMirrors,
                    "mirror leaked into member's `.swiftpm/` for invocation site \(invocationSite.name)",
                )
            }
        }
    }

    /// Round-trip test — the write and read paths both anchor to the
    /// workspace root, so a mirror set from anywhere in the workspace
    /// is visible from anywhere else. Sets from the workspace root
    /// then reads back from inside a member; expects `get-mirror` to
    /// print the mirror URL on stdout. Locks in that `get-mirror`
    /// doesn't fall back to a member-scoped `.swiftpm/`.
    @Test(
        .tags(
            .Feature.Command.Package.General,
        ),
    )
    func workspace_configGetMirror_fromMember_readsWorkspaceRootMirror() async throws {
        let buildSystem = BuildSystemProvider.Kind.swiftbuild
        try await fixture(name: "Workspaces/S14_DumpPackage") { fixturePath in
            let original = "https://github.com/example/original"
            let mirror = "https://github.com/example/mirror"

            _ = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: [
                    "config", "set-mirror",
                    "--original", original,
                    "--mirror", mirror,
                ],
                buildSystem: buildSystem,
            )

            let memberPath = fixturePath.appending(components: "packages", "app")
            let (stdout, _) = try await executeSwiftPackage(
                memberPath,
                configuration: .debug,
                extraArgs: [
                    "config", "get-mirror",
                    "--original", original,
                ],
                buildSystem: buildSystem,
            )

            #expect(
                stdout.contains(mirror),
                "expected mirror URL on stdout from `get-mirror` inside a member; got stdout=\(stdout)",
            )
        }
    }

    /// `swift package config unset-mirror` under a workspace also
    /// operates on the workspace-root mirrors file. Set a mirror
    /// from the workspace root, unset it, then verify `get-mirror`
    /// no longer finds it. Closes the config-command family (set /
    /// get / unset) by proving the write and delete anchors are the
    /// same — a stale per-member fallback would leave the mirror in
    /// place under the member's `.swiftpm/` and `get-mirror` would
    /// still find it.
    @Test(
        .tags(
            .Feature.Command.Package.General,
        ),
    )
    func workspace_configUnsetMirror_removesWorkspaceRootMirror() async throws {
        let buildSystem = BuildSystemProvider.Kind.swiftbuild
        try await fixture(name: "Workspaces/S14_DumpPackage") { fixturePath in
            let original = "https://github.com/example/original"
            let mirror = "https://github.com/example/mirror"

            _ = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: [
                    "config", "set-mirror",
                    "--original", original,
                    "--mirror", mirror,
                ],
                buildSystem: buildSystem,
            )

            _ = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: [
                    "config", "unset-mirror",
                    "--original", original,
                ],
                buildSystem: buildSystem,
            )

            // `get-mirror` exits non-zero when the mirror is not found.
            await #expect(throws: (any Error).self) {
                try await executeSwiftPackage(
                    fixturePath,
                    configuration: .debug,
                    extraArgs: [
                        "config", "get-mirror",
                        "--original", original,
                    ],
                    buildSystem: buildSystem,
                )
            }
        }
    }

    /// End-to-end proof that mirror configuration written to the
    /// workspace-root `.swiftpm/configuration/mirrors.json` is
    /// actually consulted at dependency-resolution time. The
    /// workspace declares an external dep on an intentionally
    /// unreachable URL (`https://example.invalid/some-lib.git`);
    /// without a mirror, `update` would fail trying to fetch it. The
    /// test scaffolds a real local git repo at `external/some-lib`
    /// with a `1.0.0` tag and sets a mirror redirecting the bogus
    /// URL to that local repo.
    ///
    /// What proves the mirror was applied: `update` succeeds AND
    /// stderr shows `Fetching file:///…external/some-lib` (the
    /// mirror target). If the mirror was NOT applied, stderr would
    /// show `Fetching https://example.invalid/some-lib.git` followed
    /// by a git-clone failure. `Package.resolved` is intentionally
    /// NOT asserted against the mirror path — SwiftPM's design
    /// records the *original* URL in the lockfile (mirrors apply at
    /// fetch time, not at persistence time) so removing the mirror
    /// later still points at the source-of-truth URL.
    @Test(
        .tags(
            .Feature.Command.Package.Update,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func workspace_update_appliesWorkspaceRootMirror(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S16_MirrorsUpdate") { fixturePath in
            let mirrorRepoPath = fixturePath.appending(components: "external", "some-lib")
            let workspacePath = fixturePath.appending(component: "workspace")
            try requireDirectoryExists(at: mirrorRepoPath)
            try Self.initializeExternalRepo(at: mirrorRepoPath)

            let bogusURL = "https://example.invalid/some-lib.git"
            // `file://` URL is the standard git-clone-able form for a
            // local repository — a bare filesystem path is not always
            // accepted as a source-control URL by SwiftPM's resolver.
            let mirrorURL = "file://\(mirrorRepoPath.pathString)"

            _ = try await executeSwiftPackage(
                workspacePath,
                configuration: .debug,
                extraArgs: [
                    "config", "set-mirror",
                    "--original", bogusURL,
                    "--mirror", mirrorURL,
                ],
                buildSystem: buildSystem,
            )

            let (_, stderr) = try await executeSwiftWorkspace(
                workspacePath,
                configuration: .debug,
                extraArgs: [ "update"],
                buildSystem: buildSystem,
            )

            // Mirror was consulted: the resolver fetched the local
            // mirror target rather than the unreachable bogus URL.
            #expect(
                stderr.contains(mirrorURL) == true,
                "expected stderr to show a fetch against the mirror URL `\(mirrorURL)`; got stderr=\(stderr)",
            )
            // Mirror was actually followed (not merely read): the
            // bogus URL was never fetched. If mirror substitution
            // had failed, stderr would contain
            // `Fetching https://example.invalid/…` followed by a
            // git-clone error.
            #expect(
                stderr.contains(bogusURL) == false,
                "bogus URL leaked into stderr — mirror substitution missing. stderr=\(stderr)",
            )

            // Package.resolved must exist (successful resolution).
            // Its `location` field intentionally records the
            // ORIGINAL URL — SwiftPM's design bakes mirrors into
            // the fetch path only, not the lockfile. Asserting
            // presence, not URL content.
            let resolved = workspacePath.appending("Package.resolved")
            expectFileExists(at: resolved)
        }
    }

    // MARK: - Slice 15a/15b: `Workspace.swift` load-time validation errors

    /// A `Workspace.swift` with `members: []` must fail at load
    /// time with the `emptyMembers` error's user-actionable message.
    /// Proves the `validateWorkspace` orchestrator is wired into
    /// the real `loadWorkspaceManifest` code path.
    @Test(
        .tags(
            Tag.Feature.Command.Package.General,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s15_errorPath_emptyMembers_failsWithActionableMessage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S15_ErrorPaths/EmptyMembers") { fixturePath in
            await expectThrowsCommandExecutionError(
                try await executeSwiftPackage(
                    fixturePath,
                    configuration: .debug,
                    extraArgs: ["describe"],
                    buildSystem: buildSystem,
                ),
            ) { error in
                let expected = WorkspaceManifestParseError.emptyMembers
                #expect(
                    error.stderr.contains(String(describing: expected)),
                    "expected the emptyMembers actionable message on stderr; got stderr=\(error.stderr)",
                )
            }
        }
    }

    /// A member directory that has no `Package.swift` must fail at
    /// load time with a message naming both the identity and the
    /// member's path. Proves `validateMembers` fires from the
    /// orchestrator.
    @Test(
        .tags(
            Tag.Feature.Command.Package.General,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s15_errorPath_memberWithoutPackageSwift_failsWithActionableMessage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S15_ErrorPaths/MemberWithoutPackageSwift") { fixturePath in
            await expectThrowsCommandExecutionError(
                try await executeSwiftPackage(
                    fixturePath,
                    configuration: .debug,
                    extraArgs: ["describe"],
                    buildSystem: buildSystem,
                ),
            ) { error in
                #expect(
                    error.stderr.contains("'lib-a'"),
                    "expected member identity 'lib-a' on stderr; got stderr=\(error.stderr)",
                )
                #expect(
                    error.stderr.contains("Package.swift"),
                    "expected mention of Package.swift on stderr; got stderr=\(error.stderr)",
                )
            }
        }
    }

    /// A workspace whose member directory contains its OWN
    /// `Workspace.swift` must fail with the
    /// `nestedWorkspaceInMember` message identifying the offending
    /// member. Proves the downward scan fires from the
    /// orchestrator.
    @Test(
        .tags(
            Tag.Feature.Command.Package.General,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s15_errorPath_nestedWorkspaceInMember_failsWithActionableMessage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S15_ErrorPaths/NestedWorkspaceInMember") { fixturePath in
            await expectThrowsCommandExecutionError(
                try await executeSwiftPackage(
                    fixturePath,
                    configuration: .debug,
                    extraArgs: ["describe"],
                    buildSystem: buildSystem,
                ),
            ) { error in
                #expect(
                    error.stderr.contains("nested workspaces"),
                    "expected nested-workspaces phrasing on stderr; got stderr=\(error.stderr)",
                )
                #expect(
                    error.stderr.contains("'lib-a'"),
                    "expected offending member identity 'lib-a' on stderr; got stderr=\(error.stderr)",
                )
            }
        }
    }

    /// A `Workspace.swift` invoked from a directory whose parent
    /// tree ALSO contains a `Workspace.swift` must fail with the
    /// `nestedWorkspaceInAncestor` message. Proves the upward walk
    /// in `checkNestedWorkspaceInAncestors` fires against the real
    /// discovery path.
    @Test(
        .tags(
            Tag.Feature.Command.Package.General,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s15_errorPath_nestedWorkspaceInAncestor_failsWithActionableMessage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S15_ErrorPaths/NestedWorkspaceInAncestor") { fixturePath in
            let innerPath = fixturePath.appending("inner")
            await expectThrowsCommandExecutionError(
                try await executeSwiftPackage(
                    innerPath,
                    configuration: .debug,
                    extraArgs: ["describe"],
                    buildSystem: buildSystem,
                ),
            ) { error in
                #expect(
                    error.stderr.contains("nested workspaces"),
                    "expected nested-workspaces phrasing on stderr; got stderr=\(error.stderr)",
                )
                #expect(
                    error.stderr.contains(innerPath.pathString),
                    "expected inner workspace path on stderr; got stderr=\(error.stderr)",
                )
                #expect(
                    error.stderr.contains(fixturePath.pathString),
                    "expected outer workspace path on stderr; got stderr=\(error.stderr)",
                )
            }
        }
    }

    /// `swift package workspace add-member <path>` writes the new
    /// member into `Workspace.swift` — a follow-up `list-members`
    /// reports the added entry alongside the pre-existing ones.
    /// Without `--scaffold`, no `Package.swift` is created for the
    /// new member; the user brings their own package.
    @Test(
        .tags(
            .Feature.Command.Package.ShowDependencies,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func workspace_addMember_editsManifestOnly(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S02_MemberToMemberDep") { fixturePath in
            _ = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: ["add-member", "packages/lib-b"],
                buildSystem: buildSystem,
            )

            let manifest: String = try localFileSystem.readFileContents(
                fixturePath.appending("Workspace.swift"),
            )
            #expect(
                manifest.contains("\"packages/lib-b\""),
                "expected new member entry in Workspace.swift; got manifest=\(manifest)",
            )
            expectFileDoesNotExist(
                at: fixturePath.appending(try RelativePath(validating: "packages/lib-b/Package.swift")),
            )
        }
    }

    /// `swift workspace add-dependency url <url> --from <version>`
    /// appends the workspace-level source-control dependency to
    /// `Workspace.swift`. Members inherit it via
    /// `.package(workspaceInherited: <identity>)`; this test only
    /// verifies the manifest edit (the resolver side is exercised
    /// by the Phase 3 `.workspaceInherited` tests).
    @Test(
        .tags(
            .Feature.Command.Package.General,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func workspace_addDependency_url_appendsToWorkspaceManifest(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S02_MemberToMemberDep") { fixturePath in
            _ = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: [
                    "add-dependency",
                    "url",
                    "https://github.com/apple/swift-nio",
                    "--from", "2.0.0",
                ],
                buildSystem: buildSystem,
            )

            let manifest: String = try localFileSystem.readFileContents(
                fixturePath.appending("Workspace.swift"),
            )
            #expect(
                manifest.contains("swift-nio"),
                "expected new workspace dependency in Workspace.swift; got manifest=\(manifest)",
            )
            #expect(
                manifest.contains("from: \"2.0.0\""),
                "expected `from: \"2.0.0\"` requirement in Workspace.swift; got manifest=\(manifest)",
            )
        }
    }

    /// `swift workspace add-dependency path <path>` appends the
    /// workspace-level filesystem dependency to `Workspace.swift`.
    @Test(
        .tags(
            .Feature.Command.Package.General,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func workspace_addDependency_path_appendsToWorkspaceManifest(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S02_MemberToMemberDep") { fixturePath in
            _ = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: [
                    "add-dependency",
                    "path",
                    "../shared-lib",
                ],
                buildSystem: buildSystem,
            )

            let manifest: String = try localFileSystem.readFileContents(
                fixturePath.appending("Workspace.swift"),
            )
            #expect(
                manifest.contains("path: \"../shared-lib\""),
                "expected `.package(path: \"../shared-lib\")` in Workspace.swift; got manifest=\(manifest)",
            )
        }
    }

    /// `swift workspace add-dependency registry <identity> --from <version>`
    /// appends the workspace-level registry dependency to
    /// `Workspace.swift`.
    @Test(
        .tags(
            .Feature.Command.Package.General,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func workspace_addDependency_registry_appendsToWorkspaceManifest(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S02_MemberToMemberDep") { fixturePath in
            _ = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: [
                    "add-dependency",
                    "registry",
                    "apple.swift-nio",
                    "--from", "2.0.0",
                ],
                buildSystem: buildSystem,
            )

            let manifest: String = try localFileSystem.readFileContents(
                fixturePath.appending("Workspace.swift"),
            )
            #expect(
                manifest.contains("id: \"apple.swift-nio\""),
                "expected `.package(id: \"apple.swift-nio\", ...)` in Workspace.swift; got manifest=\(manifest)",
            )
            #expect(
                manifest.contains("from: \"2.0.0\""),
                "expected `from: \"2.0.0\"` requirement in Workspace.swift; got manifest=\(manifest)",
            )
        }
    }

    /// `swift workspace add-dependency <sub>` must refuse to run when
    /// there is no enclosing `Workspace.swift` — each subcommand
    /// (`path`, `url`, `registry`) surfaces the shared
    /// `requireWorkspaceRoot` diagnostic naming its own display path
    /// so the user knows exactly which invocation was rejected.
    /// Exercised from a single-package fixture (no `Workspace.swift`).
    @Test(
        .tags(
            .Feature.Command.Package.General,
        ),
        arguments: [
            WorkspaceAddDependencyNoWorkspaceCase(
                label: "add-dependency path",
                extraArgs: ["add-dependency", "path", "../shared-lib"],
            ),
            WorkspaceAddDependencyNoWorkspaceCase(
                label: "add-dependency url",
                extraArgs: [
                    "add-dependency",
                    "url",
                    "https://github.com/apple/swift-nio",
                    "--from", "2.0.0",
                ],
            ),
            WorkspaceAddDependencyNoWorkspaceCase(
                label: "add-dependency registry",
                extraArgs: [
                    "add-dependency",
                    "registry",
                    "apple.swift-nio",
                    "--from", "2.0.0",
                ],
            ),
        ],
    )
    func workspace_addDependency_outsideWorkspace_errorsWithRequiresWorkspaceDiagnostic(
        testCase: WorkspaceAddDependencyNoWorkspaceCase,
    ) async throws {
        let buildSystem = BuildSystemProvider.Kind.swiftbuild
        try await fixture(name: "Miscellaneous/Simple") { fixturePath in
            await expectThrowsCommandExecutionError(
                try await executeSwiftWorkspace(
                    fixturePath,
                    configuration: .debug,
                    extraArgs: testCase.extraArgs,
                    buildSystem: buildSystem,
                ),
            ) { error in
                #expect(
                    error.stderr.contains("no Workspace.swift found"),
                    "expected no-Workspace.swift diagnostic for `\(testCase.label)`; got stderr=\(error.stderr)",
                )
            }
        }
    }

    /// `swift package workspace add-member <path> --scaffold <type>`
    /// writes the new member into `Workspace.swift` AND scaffolds a
    /// `Package.swift` for the new member using the given package
    /// type — matches the composition of `swift package workspace
    /// init --members <path>:<type>`.
    @Test(
        .tags(
            .Feature.Command.Package.ShowDependencies,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func workspace_addMember_withScaffold_createsPackageManifest(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await withTemporaryDirectory { tmpDir in
            let fixturePath = tmpDir.appending("workspace")

            _ = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: ["init", "--package-path", fixturePath.pathString],
                buildSystem: buildSystem,
            )

            _ = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: ["add-member", "packages/lib-b", "--scaffold", "library"],
                buildSystem: buildSystem,
            )

            let manifest: String = try localFileSystem.readFileContents(
                fixturePath.appending("Workspace.swift"),
            )
            #expect(
                manifest.contains("\"packages/lib-b\""),
                "expected new member entry in Workspace.swift; got manifest=\(manifest)",
            )
            expectFileExists(
                at: fixturePath.appending(try RelativePath(validating: "packages/lib-b/Package.swift")),
            )
        }
    }


    @Test(
        .tags(
            .Feature.Command.Package.ShowDependencies,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func workspace_addMemberExisting_withScaffold_diagnosticIsEmitted(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S02_MemberToMemberDep") { fixturePath in
            let existingMemberPath = "packages/lib-b"
            // Pre-seed the target member so the CLI hits the
            // "Package.swift already exists" branch and emits the
            // diagnostic instead of scaffolding.
            let memberDir = fixturePath.appending(try RelativePath(validating: existingMemberPath))
            try localFileSystem.createDirectory(memberDir, recursive: true)
            try localFileSystem.writeFileContents(
                memberDir.appending("Package.swift"),
                string: "// pre-existing\n",
            )

            let (stdout, stderr) = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: ["add-member", existingMemberPath, "--scaffold", "library"],
                buildSystem: buildSystem,
            )

            let expectedDiagnostic = Basics.Diagnostic.scaffoldIgnoredMemberAlreadyExists(memberPath: existingMemberPath)
            #expect(
                stderr.contains(expectedDiagnostic.message),
                "expected diagnotcis to be emitted, stdout=\(stdout), stderr=\(stderr)",
            )
        }
    }


    /// When `--scaffold <type>` is supplied but the target member's
    /// `Package.swift` already exists, the CLI emits a warning
    /// diagnostic and leaves the existing file byte-identical. The
    /// manifest edit still happens (the entry is added to
    /// `Workspace.swift` if missing) — only the scaffolding is
    /// skipped, matching the warning-not-error framing.
    @Test(
        .tags(
            .Feature.Command.Package.ShowDependencies,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func workspace_addMember_withScaffold_whenPackageExists_warnsAndPreservesFile(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S02_MemberToMemberDep") { fixturePath in
            // `packages/lib-a` already has a Package.swift shipped by the fixture.
            let existingManifestPath = fixturePath.appending(
                try RelativePath(validating: "packages/lib-a/Package.swift"),
            )
            let beforeContent: String = try localFileSystem.readFileContents(existingManifestPath)

            let (_, stderr) = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: ["add-member", "packages/lib-a", "--scaffold", "library"],
                buildSystem: buildSystem,
            )

            #expect(
                stderr.contains("--scaffold") && stderr.contains("already exists"),
                "expected scaffold-ignored warning in stderr; got stderr=\(stderr)",
            )
            let afterContent: String = try localFileSystem.readFileContents(existingManifestPath)
            #expect(
                afterContent == beforeContent,
                "pre-existing member Package.swift must not be overwritten",
            )
        }
    }

    /// `swift package workspace remove-member <path>` drops the entry
    /// from `Workspace.swift`; a follow-up `list-members` no longer
    /// reports it. On-disk directory + `Package.swift` for the removed
    /// member are left untouched — the manifest edit is the sole
    /// action.
    @Test(
        .tags(
            .Feature.Command.Package.ShowDependencies,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func workspace_removeMember_dropsEntryFromManifest(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S02_MemberToMemberDep") { fixturePath in
            _ = try await executeSwiftWorkspace(
                fixturePath,
                configuration: .debug,
                extraArgs: ["remove-member", "packages/lib-a"],
                buildSystem: buildSystem,
            )

            let manifest: String = try localFileSystem.readFileContents(
                fixturePath.appending("Workspace.swift"),
            )
            #expect(
                manifest.contains("\"packages/lib-a\"") == false,
                "expected `packages/lib-a` entry to be removed; got manifest=\(manifest)",
            )
            // The on-disk lib-a directory is left in place — removing
            // a member entry from Workspace.swift only edits the
            // manifest; users decide whether to also delete the tree.
            expectFileExists(
                at: fixturePath.appending(try RelativePath(validating: "packages/lib-a/Package.swift")),
            )
        }
    }

    /// `swift package workspace remove-member <path>` on a non-declared
    /// member fails and leaves `Workspace.swift` byte-identical —
    /// mirrors `swift package workspace override remove` behaviour so
    /// mistyped paths surface loudly rather than silently no-op.
    @Test(
        .tags(
            .Feature.Command.Package.ShowDependencies,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func workspace_removeMember_whenAbsent_fails(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S02_MemberToMemberDep") { fixturePath in
            let manifestPath = fixturePath.appending("Workspace.swift")
            let beforeContent: String = try localFileSystem.readFileContents(manifestPath)

            await #expect(throws: (any Error).self) {
                try await executeSwiftWorkspace(
                    fixturePath,
                    configuration: .debug,
                    extraArgs: ["remove-member", "packages/ghost"],
                    buildSystem: buildSystem,
                )
            }

            let afterContent: String = try localFileSystem.readFileContents(manifestPath)
            #expect(
                afterContent == beforeContent,
                "manifest must not be modified when removing a non-declared member",
            )
        }
    }

    // MARK: - Slice 15c: CLI conflicts + flag surface

    /// `--multiroot-data-file` (Xcode workspace mode) supplied
    /// alongside a discoverable `Workspace.swift` (SwiftPM
    /// workspace mode) must hard-error at init. The two mechanisms
    /// target incompatible layouts; silently preferring one over
    /// the other would leak `.build/` / `Package.resolved` state
    /// to the wrong root. The message must name BOTH paths so the
    /// user can tell where each mode is anchored.
    @Test(
        .tags(
            .Feature.Command.Package.General,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s15_multirootDataFile_conflictsWithDiscoveredWorkspace(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S14_DumpPackage") { fixturePath in
            let bogusMultiroot = fixturePath.appending("bogus.xcworkspace")
            await expectThrowsCommandExecutionError(
                try await executeSwiftPackage(
                    fixturePath,
                    configuration: .debug,
                    extraArgs: [
                        "--multiroot-data-file", bogusMultiroot.pathString,
                        "describe",
                    ],
                    buildSystem: buildSystem,
                ),
            ) { error in
                #expect(
                    error.stderr.contains("cannot be used together") == true,
                    "expected the conflict phrasing on stderr; got stderr=\(error.stderr)",
                )
                #expect(
                    error.stderr.contains(bogusMultiroot.pathString) == true,
                    "expected multiroot path on stderr; got stderr=\(error.stderr)",
                )
                #expect(
                    error.stderr.contains(fixturePath.pathString) == true,
                    "expected workspace root on stderr; got stderr=\(error.stderr)",
                )
            }
        }
    }

    // /// `--project-path <workspace>` alone is the canonical spelling —
    // /// the workspace loads normally with no deprecation noise on
    // /// stderr. Regression guard against the aliased `@Option`
    // /// accidentally firing the deprecation for the new name.
    // @Test(
    //     .tags(
    //         .Feature.Command.Package.General,
    //     ),
    //     arguments: [BuildSystemProvider.Kind.swiftbuild],
    // )
    // func s15_pathFlag_alone_worksWithoutDeprecationWarning(
    //     buildSystem: BuildSystemProvider.Kind,
    // ) async throws {
    //     try await fixture(name: "Workspaces/S14_DumpPackage") { fixturePath in
    //         let (_, stderr) = try await executeSwiftPackage(
    //             fixturePath,
    //             configuration: .debug,
    //             extraArgs: ["workspace", "dump-workspace"],
    //             buildSystem: buildSystem,
    //         )
    //         let deprecation = Basics.Diagnostic.argumentDeprecated(
    //             flag: "--package-path",
    //             renamed: "--project-path",
    //         )
    //         #expect(
    //             stderr.contains(deprecation.message) == false,
    //             "unexpected deprecation warning for the canonical `--project-path` invocation; got stderr=\(stderr)",
    //         )
    //     }
    // }

    // /// `--package-path <workspace>` alone still works — the flag
    // /// is deprecated, not removed — and the deprecation warning
    // /// fires so scripts still on the old spelling see the migration
    // /// path.
    // @Test(
    //     .tags(
    //         .Feature.Command.Package.General,
    //     ),
    //     arguments: [BuildSystemProvider.Kind.swiftbuild],
    // )
    // func s15_packagePathFlag_alone_worksAndWarns(
    //     buildSystem: BuildSystemProvider.Kind,
    // ) async throws {
    //     try await testWithTemporaryDirectory { tempDir in
    //         let (_, stderr) = try await executeSwiftPackage(
    //             nil,
    //             configuration: .debug,
    //             extraArgs: [
    //                 "--package-path", tempDir.pathString,
    //                 "workspace", "init",
    //             ],
    //             buildSystem: buildSystem,
    //         )
    //         let deprecation = Basics.Diagnostic.argumentDeprecated(
    //             flag: "--package-path",
    //             renamed: "--project-path",
    //         )
    //         #expect(
    //             stderr.contains(deprecation.message) == true,
    //             "expected the --package-path deprecation warning on stderr; got stderr=\(stderr)",
    //         )
    //         expectFileExists(at: tempDir.appending("Workspace.swift"))
    //     }
    // }

    // /// Both `--project-path <A>` and `--package-path <B>` set: last-wins
    // /// semantics — whichever appears LAST on the command line
    // /// wins. Verified by asserting `--package-path <B>` (typed
    // /// last) beats an earlier `--project-path <A>`. Locks in the aliased
    // /// `@Option` last-wins behaviour and that the deprecation
    // /// still fires because the old spelling was typed.
    // @Test(
    //     .tags(
    //         .Feature.Command.Package.General,
    //     ),
    //     arguments: [BuildSystemProvider.Kind.swiftbuild],
    // )
    // func s15_bothPathFlags_lastWinsAndWarns(
    //     buildSystem: BuildSystemProvider.Kind,
    // ) async throws {
    //     try await testWithTemporaryDirectory { tempDir in
    //         let earlyTarget = tempDir.appending("early-target")
    //         let lateTarget = tempDir.appending("late-target")

    //         let (_, stderr) = try await executeSwiftPackage(
    //             nil,
    //             configuration: .debug,
    //             extraArgs: [
    //                 "--project-path", earlyTarget.pathString,
    //                 "--package-path", lateTarget.pathString,
    //                 "workspace", "init",
    //             ],
    //             buildSystem: buildSystem,
    //         )

    //         // last-wins: `--package-path` was typed last, so the
    //         // workspace scaffolds into `lateTarget`, not `earlyTarget`.
    //         expectFileExists(at: lateTarget.appending("Workspace.swift"))
    //         expectFileDoesNotExist(at: earlyTarget.appending("Workspace.swift"))

    //         // Deprecation fires because `--package-path` was used
    //         // at least once.
    //         let deprecation = Basics.Diagnostic.argumentDeprecated(
    //             flag: "--package-path",
    //             renamed: "--project-path",
    //         )
    //         #expect(
    //             stderr.contains(deprecation.message) == true,
    //             "expected the --package-path deprecation warning on stderr; got stderr=\(stderr)",
    //         )
    //     }
    // }


    // MARK: - Slice 15d: `swift package edit` / `unedit` deferred under a workspace

    /// `swift package edit` under a SwiftPM workspace must fail
    /// with an actionable message that points the user at
    /// `swift package workspace override` (the workspace-scoped
    /// replacement for the "redirect a dep to a local checkout"
    /// use case). The user must never see the generic
    /// "will be addressed in a follow-up" placeholder — they need
    /// a concrete next step.
    @Test(
        .tags(
            .Feature.Command.Package.General,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s15_edit_underWorkspace_hardErrorsPointingAtWorkspaceOverride(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S14_DumpPackage") { fixturePath in
            await expectThrowsCommandExecutionError(
                try await executeSwiftPackage(
                    fixturePath,
                    configuration: .debug,
                    extraArgs: ["edit", "some-lib"],
                    buildSystem: buildSystem,
                ),
            ) { error in
                #expect(
                    error.stderr.contains("swift package edit is not supported") == true,
                    "expected the deferred-feature phrasing on stderr; got stderr=\(error.stderr)",
                )
                #expect(
                    error.stderr.contains("swift package workspace override") == true,
                    "expected the workspace-override redirect on stderr; got stderr=\(error.stderr)",
                )
                #expect(
                    error.stderr.contains(fixturePath.pathString) == true,
                    "expected the workspace root on stderr; got stderr=\(error.stderr)",
                )
                #expect(
                    error.stderr.contains("follow-up") == false,
                    "unexpected placeholder wording on stderr; got stderr=\(error.stderr)",
                )
            }
        }
    }

    /// Parity coverage for `swift package unedit` under a workspace
    /// — same rejection, same actionable redirect at
    /// `swift package workspace override remove`.
    @Test(
        .tags(
            .Feature.Command.Package.General,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s15_unedit_underWorkspace_hardErrorsPointingAtWorkspaceOverride(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S14_DumpPackage") { fixturePath in
            await expectThrowsCommandExecutionError(
                try await executeSwiftPackage(
                    fixturePath,
                    configuration: .debug,
                    extraArgs: ["unedit", "some-lib"],
                    buildSystem: buildSystem,
                ),
            ) { error in
                #expect(
                    error.stderr.contains("swift package unedit is not supported") == true,
                    "expected the deferred-feature phrasing on stderr; got stderr=\(error.stderr)",
                )
                #expect(
                    error.stderr.contains("swift package workspace override") == true,
                    "expected the workspace-override redirect on stderr; got stderr=\(error.stderr)",
                )
                #expect(
                    error.stderr.contains(fixturePath.pathString) == true,
                    "expected the workspace root on stderr; got stderr=\(error.stderr)",
                )
                #expect(
                    error.stderr.contains("follow-up") == false,
                    "unexpected placeholder wording on stderr; got stderr=\(error.stderr)",
                )
            }
        }
    }

    /// A standalone `Package.swift` (no `Workspace.swift` in any
    /// ancestor) that uses `.package(workspaceMember:)` must fail
    /// at load time — the DSL entry is workspace-only and has no
    /// meaning outside a workspace context. Locks in the
    /// `workspaceMemberUsedOutsideWorkspace` rejection at the CLI
    /// boundary. Unit-level coverage of the same rejection lives in
    /// `WorkspaceResolveTests`.
    @Test(
        .tags(
            .Feature.Command.Package.General,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s15_workspaceMember_outsideWorkspace_hardErrors(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(
            name: "Workspaces/S15_ErrorPaths/WorkspaceMemberUsedOutsideWorkspace",
        ) { fixturePath in
            await expectThrowsCommandExecutionError(
                try await executeSwiftPackage(
                    fixturePath,
                    configuration: .debug,
                    extraArgs: ["describe"],
                    buildSystem: buildSystem,
                ),
            ) { error in
                #expect(
                    error.stderr.contains(".package(workspaceMember:)"),
                    "expected `.package(workspaceMember:)` mention on stderr; got stderr=\(error.stderr)",
                )
                #expect(
                    error.stderr.contains("Workspace.swift"),
                    "expected the Workspace.swift precondition on stderr; got stderr=\(error.stderr)",
                )
            }
        }
    }

    /// Parity coverage for `.package(workspaceInherited:)` outside
    /// a workspace: same rejection with the identity-only variant
    /// of the DSL.
    @Test(
        .tags(
            .Feature.Command.Package.General,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s15_workspaceInherited_outsideWorkspace_hardErrors(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(
            name: "Workspaces/S15_ErrorPaths/WorkspaceInheritedUsedOutsideWorkspace",
        ) { fixturePath in
            await expectThrowsCommandExecutionError(
                try await executeSwiftPackage(
                    fixturePath,
                    configuration: .debug,
                    extraArgs: ["describe"],
                    buildSystem: buildSystem,
                ),
            ) { error in
                #expect(
                    error.stderr.contains(".package(workspaceInherited:)"),
                    "expected `.package(workspaceInherited:)` mention on stderr; got stderr=\(error.stderr)",
                )
                #expect(
                    error.stderr.contains("Workspace.swift"),
                    "expected the Workspace.swift precondition on stderr; got stderr=\(error.stderr)",
                )
            }
        }
    }

    /// A workspace declares two members (`app`, `lib-a`) and one
    /// workspace-level dependency `traited-lib` with traits
    /// `["core"]`. Each member inherits `traited-lib` via
    /// `.package(workspaceInherited:)` but layers a DIFFERENT
    /// additional trait — `app` requests `["core", "extras"]`,
    /// `lib-a` requests `["core", "perf"]`. Locks in that
    /// per-member trait sets on `.workspaceInherited` are
    /// resolved independently and the whole workspace graph
    /// loads + builds successfully end-to-end. Unit-level per-call
    /// isolation of `resolveInherited` is exercised in
    /// `WorkspaceResolveTests`.
    @Test(
        .tags(
            .Feature.Command.Package.General,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s15_workspaceInheritedTraits_perMemberIsolation_workspaceLoadsAndBuilds(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S15_InheritedTraits") { fixturePath in
            // `describe` triggers the full manifest-load pipeline
            // (including `resolveInherited` per member) without
            // needing a network fetch — `traited-lib` is a local
            // file-system dep. If per-member trait sets were
            // cross-contaminated or the merge policy misbehaved,
            // manifest load would surface a WorkspaceResolveError
            // on stderr and the command would exit non-zero.
            let (_, stderr) = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["describe"],
                buildSystem: buildSystem,
            )
            #expect(
                stderr.contains("error:") == false,
                "expected no error on stderr for a well-formed multi-member trait-inheriting workspace; got stderr=\(stderr)",
            )
            #expect(
                stderr.contains("WorkspaceResolveError") == false,
                "unexpected WorkspaceResolveError on stderr; got stderr=\(stderr)",
            )
        }
    }

    /// A workspace declares three members (`app`, `lib-a`, `lib-b`).
    /// Both `app` and `lib-b` depend on the sibling workspace member
    /// `lib-a` via `.package(workspaceMember:)` but with DIFFERENT
    /// per-consumer trait sets — `app` requests `["core", "extras"]`,
    /// `lib-b` requests `["core", "perf"]`. Locks in that per-member
    /// trait sets on `.workspaceMember` are preserved verbatim (no
    /// merge, no cross-contamination) and the whole workspace graph
    /// loads successfully end-to-end. Unit-level per-call isolation
    /// is exercised in `WorkspaceResolveTests`.
    @Test(
        .tags(
            .Feature.Command.Package.General,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s15_workspaceMemberTraits_perMemberIsolation_workspaceLoadsAndBuilds(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S15_MemberTraits") { fixturePath in
            // `describe` triggers the full manifest-load pipeline
            // (including `resolveWorkspaceMemberPaths` per member).
            // If the per-consumer trait sets on `.workspaceMember`
            // were merged or dropped, manifest load would either
            // surface a WorkspaceResolveError or fail with an
            // unexpected exit code.
            let (_, stderr) = try await executeSwiftPackage(
                fixturePath,
                configuration: .debug,
                extraArgs: ["describe"],
                buildSystem: buildSystem,
            )
            #expect(
                stderr.contains("error:") == false,
                "expected no error on stderr for a well-formed multi-member trait-bearing workspaceMember graph; got stderr=\(stderr)",
            )
            #expect(
                stderr.contains("WorkspaceResolveError") == false,
                "unexpected WorkspaceResolveError on stderr; got stderr=\(stderr)",
            )
        }
    }

    /// Two workspace members that each depend on the other via
    /// `.package(workspaceMember:)` + `.product()` at the target
    /// level form a target cycle (LibA -> LibB -> LibA). Graph load
    /// must reject the workspace with a `cyclic dependency
    /// declaration` diagnostic. Locks in that `.workspaceMember`
    /// edges participate in cross-package cycle detection.
    @Test(
        .tags(
            .Feature.Command.Package.General,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s15_workspaceMemberCycle_hardErrors(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S15_WorkspaceMemberCycle") { fixturePath in
            await expectThrowsCommandExecutionError(
                try await executeSwiftPackage(
                    fixturePath,
                    configuration: .debug,
                    extraArgs: ["describe"],
                    buildSystem: buildSystem,
                ),
            ) { error in
                #expect(
                    error.stderr.contains("cyclic dependency declaration"),
                    "expected cyclic dependency diagnostic on stderr; got stderr=\(error.stderr)",
                )
                // Both members must appear in the reported cycle
                // path so the diagnostic is actionable.
                #expect(
                    error.stderr.contains("LibA"),
                    "expected 'LibA' in the cycle path on stderr; got stderr=\(error.stderr)",
                )
                #expect(
                    error.stderr.contains("LibB"),
                    "expected 'LibB' in the cycle path on stderr; got stderr=\(error.stderr)",
                )
            }
        }
    }

    /// A workspace member inherits an external workspace-level dep
    /// via `.package(workspaceInherited:)`, and the external dep
    /// declares a `.package(path:)` back-reference to that same
    /// member. The mutual product edges (LibA imports LibX in the
    /// member; LibX imports LibA in the external) form a target
    /// cycle at graph load. Locks in that `.workspaceInherited`
    /// edges participate in cycle detection through the concrete
    /// kind they resolve to (here, `.fileSystem`).
    @Test(
        .tags(
            .Feature.Command.Package.General,
        ),
        arguments: [BuildSystemProvider.Kind.swiftbuild],
    )
    func s15_workspaceInheritedCycle_hardErrors(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S15_WorkspaceInheritedCycle") { fixturePath in
            await expectThrowsCommandExecutionError(
                try await executeSwiftPackage(
                    fixturePath,
                    configuration: .debug,
                    extraArgs: ["describe"],
                    buildSystem: buildSystem,
                ),
            ) { error in
                #expect(
                    error.stderr.contains("cyclic dependency declaration"),
                    "expected cyclic dependency diagnostic on stderr; got stderr=\(error.stderr)",
                )
                #expect(
                    error.stderr.contains("LibA"),
                    "expected 'LibA' in the cycle path on stderr; got stderr=\(error.stderr)",
                )
                #expect(
                    error.stderr.contains("LibX"),
                    "expected 'LibX' in the cycle path on stderr; got stderr=\(error.stderr)",
                )
            }
        }
    }

    /// Initializes an external-dependency directory in the S08
    /// fixture as a git repository tagged `1.0.0`. The fixture ships
    /// each `external/*` directory without a `.git/` folder (nothing
    /// to commit); each test that exercises `swift package resolve`
    /// calls this helper first so source-control dependencies
    /// declared in `Workspace.swift` become resolvable.
    private static func initializeExternalRepo(at fixturePath: AbsolutePath) throws {
        let repo = GitRepository(path: fixturePath)
        try repo.create()
        try repo.stageEverything()
        try repo.commit(message: "Initial commit at \(fixturePath.basename)")
        try repo.tag(name: "1.0.0")
    }

    /// Reads a `Package.resolved` file and returns its `originHash`
    /// field. The `Package.resolved` v3 schema serializes the hash as
    /// a top-level `originHash` string; `nil` when the file predates
    /// v3 or the hash wasn't recorded.
    private static func readOriginHash(from resolvedFile: AbsolutePath) throws -> String? {
        let contents: String = try localFileSystem.readFileContents(resolvedFile)
        let json = try JSONSerialization.jsonObject(with: Data(contents.utf8)) as? [String: Any]
        return json?["originHash"] as? String
    }
}

/// A single `swift test` invocation flavor for parameterizing tests
/// that assert behavior common to both `swift test` and
/// `swift test list`. The `subcommand` is prepended to `extraArgs`;
/// the `label` distinguishes the two cases in assertion failure text.
struct SwiftTestInvocation: Sendable, CustomTestStringConvertible {
    let subcommand: [String]
    let label: String

    var testDescription: String { label }
}

/// A single `swift workspace add-dependency <sub>` invocation for
/// parameterizing the no-`Workspace.swift` error contract test. The
/// `label` names the case in assertion failure text; `extraArgs` is
/// forwarded directly to `executeSwiftWorkspace`.
struct WorkspaceAddDependencyNoWorkspaceCase: Sendable, CustomTestStringConvertible {
    let label: String
    let extraArgs: [String]

    var testDescription: String { label }
}

/// A single `swift package workspace override add` help-page invocation
/// for parameterizing the no-`workspace-level` contract test. The
/// `label` names the case in assertion failure text; `extraArgs` is
/// forwarded directly to `executeSwiftPackage`.
struct WorkspaceOverrideHelpCase: Sendable, CustomTestStringConvertible {
    let label: String
    let extraArgs: [String]

    var testDescription: String { label }
}
