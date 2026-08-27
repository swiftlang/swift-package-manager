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
import SourceControl
import Testing
import _InternalTestSupport
import struct PackageModel.PackageIdentity

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
    func s09_workspaceOverrideRedirectsToLocalCheckout(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S09_WorkspaceOverrides") { fixturePath in
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
