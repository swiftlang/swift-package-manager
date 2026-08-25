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
        arguments: [BuildSystemProvider.Kind.swiftbuild],
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
    /// `swift build` invoked from inside a workspace member's
    /// directory should build ONLY that member's products and their
    /// transitive dependencies, not sibling members that the focused
    /// member doesn't depend on.
    ///
    /// Fixture layout:
    ///   - `packages/app` — executable, depends on local `external/some-lib`
    ///   - `packages/lib-a` — library, unrelated to `app`
    ///   - `external/some-lib` — directly-declared local dependency
    ///
    /// Invocation from inside `packages/app` (via `--package-path`) must
    /// build `app` (+ `SomeLib` transitively) but NOT `lib-a`.
    ///
    /// Restricted to the Swift Build build system: the workspace-member
    /// focus feature is only supported there. Native/XCBuild paths would
    /// be rejected by `SwiftCommandState` with a hard error.
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
}
