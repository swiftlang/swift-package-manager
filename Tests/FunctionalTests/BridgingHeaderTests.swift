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
    @Test(
        .requiresBridgingHeaderManifestSupport,
        .issue("https://github.com/swiftlang/swift-package-manager/issues/10708", relationship: .verifies),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/10723", relationship: .defect),
    )
    func bridgingHeaderBasics() async throws {
        try await withKnownIssue(
            "https://github.com/swiftlang/swift-package-manager/issues/10723",
            isIntermittent: true,
        ) {
        try await fixture(name: "Miscellaneous/BridgingHeader") { fixturePath in
            _ = try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                buildSystem: .swiftbuild,
            )
        }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }
    }

    /// A bridging header that imports C++ code.
    @Test(
        .requiresBridgingHeaderManifestSupport,
        .issue("https://github.com/swiftlang/swift-package-manager/issues/10708", relationship: .verifies),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/10723", relationship: .defect),
    )
    func bridgingHeaderImportingCxx() async throws {
        try await withKnownIssue(
            "https://github.com/swiftlang/swift-package-manager/issues/10723",
            isIntermittent: true,
        ) {
        try await fixture(name: "Miscellaneous/BridgingHeaderCxx") { fixturePath in
            _ = try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                buildSystem: .swiftbuild,
            )
        }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }
    }

    /// A mixed source target with both an underlying module and a bridging header.
    @Test(
        .requiresGeneratedHeaderUnderlyingModuleIncludeBase,
        .requiresBridgingHeaderManifestSupport,
    )
    func bridgingHeaderWithUnderlyingClangModule() async throws {
        try await fixture(name: "Miscellaneous/BridgingHeaderWithClangModule") { fixturePath in
            _ = try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                buildSystem: .swiftbuild,
            )
        }
    }

    /// A mixed source target whose bridging header includes a header found via custom search paths.
    @Test(
        .requiresBridgingHeaderManifestSupport,
        .issue("https://github.com/swiftlang/swift-package-manager/issues/10708", relationship: .verifies),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/10723", relationship: .defect),
    )
    func bridgingHeaderWithCustomHeaderSearchPaths() async throws {
        try await withKnownIssue(
            "https://github.com/swiftlang/swift-package-manager/issues/10723",
            isIntermittent: true,
        ) {
        try await fixture(name: "Miscellaneous/BridgingHeaderSearchPaths") { fixturePath in
            _ = try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                buildSystem: .swiftbuild,
            )
        }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(
        .requiresBridgingHeaderManifestSupport,
        .issue("https://github.com/swiftlang/swift-package-manager/issues/10708", relationship: .verifies),
    )
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
