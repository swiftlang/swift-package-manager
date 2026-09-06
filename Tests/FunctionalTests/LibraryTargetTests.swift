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
struct LibraryTargetTests {
    @Test
    func sourceLibraryTargets() async throws {
        try await fixture(name: "Miscellaneous/LibraryTargets") { fixturePath in
            let (stdout, _) = try await executeSwiftBuild(
                fixturePath.appending("SourceLibraryTargets"),
                configuration: .debug,
                buildSystem: .swiftbuild,
            )
            #expect(stdout.contains("Build complete!"), "stdout:\n\(stdout)")
        }
    }

    @Test
    func aggregateLibraryTargets() async throws {
        try await fixture(name: "Miscellaneous/LibraryTargets") { fixturePath in
            let (stdout, _) = try await executeSwiftBuild(
                fixturePath.appending("AggregateLibraryTargets"),
                configuration: .debug,
                buildSystem: .swiftbuild,
            )
            #expect(stdout.contains("Build complete!"), "stdout:\n\(stdout)")
        }
    }

    @Test
    func libraryTargetsRejectedByNativeBuildSystem() async throws {
        try await fixture(name: "Miscellaneous/LibraryTargets") { fixturePath in
            await expectThrowsCommandExecutionError(
                try await executeSwiftBuild(
                    fixturePath.appending("SourceLibraryTargets"),
                    configuration: .debug,
                    buildSystem: .native,
                )
            ) { error in
                #expect(
                    error.stderr.contains(
                        "library target 'StaticLib' is only supported by the 'swiftbuild' build system"
                    ),
                    "stderr:\n\(error.stderr)"
                )
            }
        }
    }
}
