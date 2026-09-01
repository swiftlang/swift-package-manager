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
    .serializedIfOnWindows,
    .tags(
        .TestSize.large,
        .Feature.CTargets,
    ),
)
struct BridgingHeaderTests {
    /// A Swift executable that uses a bridging header.
    @Test
    func bridgingHeaderBasics() async throws {
        try await fixture(name: "Miscellaneous/BridgingHeader") { fixturePath in
            try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                buildSystem: .swiftbuild,
            )
        }
    }

    /// A bridging header that imports C++ code.
    @Test
    func bridgingHeaderImportingCxx() async throws {
        try await fixture(name: "Miscellaneous/BridgingHeaderCxx") { fixturePath in
            try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                buildSystem: .swiftbuild,
            )
        }
    }

    /// A mixed source target with both an underlying module and a bridging header.
    @Test
    func bridgingHeaderWithUnderlyingClangModule() async throws {
        try await fixture(name: "Miscellaneous/BridgingHeaderWithClangModule") { fixturePath in
            try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                buildSystem: .swiftbuild,
            )
        }
    }

    /// A mixed source target whose bridging header includes a header found via custom search paths.
    @Test
    func bridgingHeaderWithCustomHeaderSearchPaths() async throws {
        try await fixture(name: "Miscellaneous/BridgingHeaderSearchPaths") { fixturePath in
            try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                buildSystem: .swiftbuild,
            )
        }
    }

    @Test
    func bridgingHeaderRejectedByNativeBuildSystem() async throws {
        try await fixture(name: "Miscellaneous/BridgingHeader") { fixturePath in
            await expectThrowsCommandExecutionError(
                try await executeSwiftBuild(
                    fixturePath,
                    configuration: .debug,
                    buildSystem: .native,
                )
            ) { error in
                #expect(
                    error.consoleOutput.contains(
                        "bridging headers are not supported when using the native build system"
                    )
                )
            }
        }
    }
}
