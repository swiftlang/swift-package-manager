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

import Foundation

import Basics
import _InternalTestSupport
import Testing

@Suite(
    .tags(
        .TestSize.large,
        .Feature.Command.Build,
    ),
)
struct TargetVisibilityTests {
    @Test
    func dependencyOnPublicTargetsInAnotherPackage() async throws {
        try await fixture(name: "Miscellaneous/PublicTargets") { fixturePath in
            let (stdout, _) = try await executeSwiftBuild(
                fixturePath.appending("Root"),
                configuration: .debug,
                buildSystem: .swiftbuild,
            )
            #expect(stdout.contains("Build complete!"), "stdout:\n\(stdout)")
        }
    }

    @Test
    func dependencyOnPackageVisibleTargetInAnotherPackageIsRejected() async throws {
        try await fixture(name: "Miscellaneous/PublicTargets") { fixturePath in
            await expectThrowsCommandExecutionError(
                try await executeSwiftBuild(
                    fixturePath.appending("PackageVisibleRoot"),
                    configuration: .debug,
                    buildSystem: .swiftbuild,
                )
            ) { error in
                #expect(error.stderr.contains("target 'PackageOnly' required by target 'Tool' not found in package 'Dep'"), "stderr:\n\(error.stderr)")
            }
        }
    }
}
