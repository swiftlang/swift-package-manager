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
import Testing
import _InternalTestSupport
import struct PackageModel.PackageIdentity

@_spi(SwiftPMInternal) import CoreCommands
@_spi(SwiftPMInternal) import SPMBuildCore
import struct SPMBuildCore.BuildSystemProvider

@Suite(
    .serializedIfOnWindows,
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
}
