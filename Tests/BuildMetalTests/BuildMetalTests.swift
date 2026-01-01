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

import _InternalTestSupport
import Testing
import Basics
import Foundation
import struct SPMBuildCore.BuildSystemProvider
import enum PackageModel.BuildConfiguration
#if os(macOS)
import Metal
#endif

@Suite(
    .tags(
        .FunctionalArea.Metal,
    )
)
struct BuildMetalTests {

    @Test(
        .disabled("Require downloadable Metal toolchain"),
        .tags(
            .TestSize.large,
        ),
        .requireHostOS(.macOS),
        arguments: BuildConfiguration.allCases,
    )
    func simpleLibrary(
        config: BuildConfiguration,
    ) async throws {
        let buildSystem = BuildSystemProvider.Kind.swiftbuild
        let configuration = config

        try await fixture(name: "Metal/SimpleLibrary") { fixturePath in

            // Build the package
            let (_, _) = try await executeSwiftBuild(
                fixturePath,
                configuration: configuration,
                buildSystem: buildSystem,
                throwIfCommandFails: true
            )

            // Get the bin path
            let (binPathOutput, _) = try await executeSwiftBuild(
                fixturePath,
                configuration: configuration,
                extraArgs: ["--show-bin-path"],
                buildSystem: buildSystem,
                throwIfCommandFails: true
            )

            let binPath = try AbsolutePath(validating: binPathOutput.trimmingCharacters(in: .whitespacesAndNewlines))

            // Check that default.metallib exists
            let metallibPath = binPath.appending(components:["MyRenderer_MyRenderer.bundle", "Contents", "Resources", "default.metallib"])
            #expect(
                localFileSystem.exists(metallibPath),
                "Expected default.metallib to exist at \(metallibPath)"
            )

#if os(macOS)
            // Verify we can load the metal library
            let device = try #require(MTLCreateSystemDefaultDevice())
            let library = try device.makeLibrary(URL: URL(fileURLWithPath: metallibPath.pathString))

            #expect(library.functionNames.contains("simpleVertexShader"))
#endif
        }
    }
}
