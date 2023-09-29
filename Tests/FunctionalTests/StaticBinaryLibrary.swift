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
import DriverSupport
import PackageModel
import TSCBasic
import Testing
import _InternalTestSupport

@Suite
struct StaticBinaryLibraryTests {
    @Test
    func staticLibrary() async throws {
        try await fixture(name: "BinaryLibraries") { fixturePath in
            let (stdout, stderr) = try await executeSwiftRun(
                fixturePath.appending("Static").appending("Package1"),
                "Example",
                extraArgs: ["--experimental-prune-unused-dependencies"]
            )
            // We expect no warnings to be produced. Specifically no unused dependency warnings.
            #expect(!stderr.contains("warning:"))
            #expect(stdout ==  """
            42
            42

            """)
        }
    }
}
