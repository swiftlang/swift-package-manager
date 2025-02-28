//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import _InternalTestSupport
import XCTest

final class LibraryDependencyTests: XCTestCase {
    func testClientPackage() async throws {
        // The test package is set up to support Ubuntu 24.04 (x86_64) for ease of development,
        // but due to the environment-dependent nature of the test, we can only guarantee that
        // it works on macOS.
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif

        try await fixture(name: "LibraryDependencies/KrustyKrab") { fixturePath in
            let (output, _) = try await executeSwiftRun(fixturePath, "KrustyKrab")
            XCTAssertTrue(output.contains("Latest Krabby Patty formula version: v3"), output)
        }
    }
}
