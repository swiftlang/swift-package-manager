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
#if compiler(>=6.0)
import DriverSupport
import SPMTestSupport
import PackageModel
import XCTest

final class TraitTests: XCTestCase {
    func testTraits_whenNoFlagPassed() throws {
        try fixture(name: "Traits") { fixturePath in
            let (stdout, _) = try executeSwiftRun(fixturePath.appending("Example"), "Example")
            XCTAssertEqual(stdout, """
            Package1Library1 trait1 enabled
            Package2Library1 trait2 enabled
            Package3Library1 trait3 enabled
            Package4Library1 trait1 disabled
            DEFINE1 enabled
            DEFINE2 disabled
            DEFINE3 disabled

            """)
        }
    }
}
#endif
