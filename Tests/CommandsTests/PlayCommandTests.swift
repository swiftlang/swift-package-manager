//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

import Basics
import Commands
import struct SPMBuildCore.BuildSystemProvider
import enum PackageModel.BuildConfiguration
import _InternalTestSupport
import Testing

@Suite(
    .serialized,  // to limit the number of swift executables running.
    .tags(
        Tag.TestSize.large,
        Tag.Feature.Command.Play,
    )
)
struct PlayCommandTests {

    private func execute(
        _ args: [String],
        packagePath: AbsolutePath? = nil,
        configuration: BuildConfiguration = .debug,
        buildSystem: BuildSystemProvider.Kind,
        throwIfCommandFails: Bool = true
    ) async throws -> (stdout: String, stderr: String) {
        try await executeSwiftPlay(
            packagePath,
            configuration: configuration,
            extraArgs: args,
            throwIfCommandFails: throwIfCommandFails,
            buildSystem: buildSystem,
        )
    }

    @Test(
        .tags(
            Tag.Feature.Command.Play,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func swiftPlayUsage(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        let stdout = try await execute(
            ["-help"],
            configuration: configuration,
            buildSystem: buildSystem,
        ).stdout
        #expect(stdout.contains("USAGE: swift play"), "got stdout:\n\(stdout)")
    }

    @Test(
        .tags(
            Tag.Feature.Command.Play,
        ),
        // TODO: SupportedBuildSystemOnAllPlatforms
        arguments: [BuildSystemProvider.Kind.native], BuildConfiguration.allCases,
    )
    func swiftPlayList(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await fixture(name: "Miscellaneous/Playgrounds/Simple") { fixturePath in
            let (stdout, stderr) = try await execute(
                ["--list"],
                packagePath: fixturePath,
                configuration: configuration,
                buildSystem: buildSystem,
            )
            // build was run
            #expect(stderr.contains("Build of product 'Simple__Playgrounds' complete!"))

            // getting the lists
            #expect(stdout.contains("* Simple/Simple.swift:11 (unnamed)"))
            #expect(stdout.contains("* Simple/Simple.swift:16 Simple.b"))
            #expect(stdout.contains("* Simple/Simple.swift:21 Upper"))
        }
    }

}

