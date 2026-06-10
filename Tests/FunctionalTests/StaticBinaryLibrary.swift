//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation
import DriverSupport
import PackageModel
import TSCBasic
import Testing
import _InternalTestSupport
import struct SPMBuildCore.BuildSystemProvider

struct StaticBinaryLibraryTests {
    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8657", relationship: .defect),
        .tags(
            .TestSize.large,
            .Feature.Command.Run,
            .Feature.CommandLineArguments.Experimental.PruneUnusedDependencies,
            .Feature.TargetType.Library,
            .Feature.TargetType.BinaryTarget.ArtifactBundle,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func staticLibrary(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "BinaryLibraries") { fixturePath in
            let (stdout, _) = try await executeSwiftRun(
                fixturePath.appending("Static").appending("Package1"),
                "Example",
                configuration: .debug,
                extraArgs: ["--experimental-prune-unused-dependencies"],
                buildSystem: buildSystem,
            )
            #expect(stdout == """
            42
            42

            """)
        }
    }
}
