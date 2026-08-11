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

import Testing
import struct SPMBuildCore.BuildSystemProvider
import _InternalTestSupport
import var Basics.localFileSystem

@Suite(
    .tags(
        .TestSize.large,
        .Feature.SDK.Android,
    ),
    .requiresAndroidSwiftSDK,
)
struct AndroidSDKIntegrationTests {
    @Test(
        .requiresAndroidSwiftSDK,
        .requireAndroidNDK,
        arguments: androidTriplesUT,
    )
    func basicBuildAndroid(
        tripleUT: String
    ) async throws {
        let buildSystem = BuildSystemProvider.Kind.swiftbuild
        // GIVEN we have a sample package
        try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
            let (compilerPath, sdkID) = try #require(try await findCompilerAndSDKIDForTesting(for: .android))

            // WHEN we build for android using the specific target triple
            let buildOutput = try await executeSwiftBuild(
                fixturePath,
                extraArgs: ["--swift-sdk", sdkID, "--triple", tripleUT],
                // env: env,
                buildSystem: buildSystem,
            )

            // THEN we expect the build to be successful
            #expect(buildOutput.stdout.contains("Build complete"))

            let binary = try await getBinPath(
                fixturePath,
                extraArgs: ["--swift-sdk", sdkID, "--triple", tripleUT],
                buildSystem: buildSystem,
            ).appending(component: "ExecutableNew")

            // AND the binary to exist on the file system
            #expect(localFileSystem.exists(binary), "Expected binary at \(binary)")

        }
    }
}
