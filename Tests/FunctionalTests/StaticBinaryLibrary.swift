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

struct StaticBinaryLibraryTests {
    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8657")
    )
    func staticLibrary() async throws {

        try await withKnownIssue {
            try await fixture(name: "BinaryLibraries") { fixturePath in
                let (stdout, stderr) = try await executeSwiftRun(
                    fixturePath.appending("Static").appending("Package1"),
                    "Example",
                    extraArgs: ["--experimental-prune-unused-dependencies"],
                    buildSystem: .native,
                )
                #expect(stdout == """
                42
                42

                """)
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }
    }
}
