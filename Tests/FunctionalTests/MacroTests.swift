//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

import struct SPMBuildCore.BuildSystemProvider

import DriverSupport
import _InternalTestSupport
import PackageModel
import Testing

@Suite(
    .tags(
        Tag.TestSize.large
    ),
)
struct MacroTests {
    @Test(
        .requiresBuildingMacrosAsDylibs,
        .requiresFrontEndFlags(flags: ["load-plugin-library"]),
        .requiresSwiftTestingMacros,
        .tags(
            Tag.Feature.Command.Build
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func macrosBasic(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await fixture(name: "Macros") { fixturePath in
            let (stdout, _) = try await executeSwiftBuild(
                fixturePath.appending("MacroPackage"),
                configuration: configuration,
                buildSystem: buildSystem,
            )
            #expect(stdout.contains("@__swiftmacro_11MacroClient11fontLiteralfMf_.swift as Font"), "stdout:\n\(stdout)")
            #expect(stdout.contains("Build complete!"), "stdout:\n\(stdout)")
        }
    }
}
