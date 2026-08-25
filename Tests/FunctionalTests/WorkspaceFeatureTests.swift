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
}
