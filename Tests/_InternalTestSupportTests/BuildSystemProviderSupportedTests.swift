//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _InternalTestSupport
import Testing
import struct SPMBuildCore.BuildSystemProvider
import enum PackageModel.BuildConfiguration
import struct Basics.Environment

@Suite(
    .tags(
        .TestSize.small,
    )
)
struct BuildSystemProviderSupportedTests {

    @Test(
        .serialized,
        arguments: [
            [BuildSystemProvider.Kind.native],
            [BuildSystemProvider.Kind.native, .xcode],
            [BuildSystemProvider.Kind.native, .xcode, .swiftbuild],
        ], [true, false],
    )
    func getBuildDataReturnsExpectedTests(
        buildSystemsUT: [BuildSystemProvider.Kind],
        setEnvironmantVariable: Bool,
    ) async throws {
        let expectedCount: Int
        let customEnv: Environment

        if setEnvironmantVariable {
            expectedCount = buildSystemsUT.count
            customEnv = [TEST_ONLY_DEBUG_ENV_VAR : "true"]
        } else {
            expectedCount = buildSystemsUT.count * BuildConfiguration.allCases.count
            customEnv = [:]
        }

        try Environment.makeCustom(customEnv) {
            let actual = getBuildData(for: buildSystemsUT)

            #expect(actual.count == expectedCount)
        }

    }
}