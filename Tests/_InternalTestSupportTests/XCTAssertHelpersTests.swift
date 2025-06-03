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

import Basics
import XCTest
import func _InternalTestSupport.XCTAssertThrows
import func _InternalTestSupport._requiresTools

final class TestRequiresTool: XCTestCase {
    func testErrorIsThrownIfExecutableIsNotFoundOnThePath() throws {
        XCTAssertThrows(
            try _requiresTools("doesNotExists")
        ) { (error: AsyncProcessResult.Error) in
            return true
        }
    }

    func testErrorIsNotThrownIfExecutableIsOnThePath() throws {
        // Essentially call either "which which" or "where.exe where.exe"
        #if os(Windows)
        let executable = "where.exe"
        #else
        let executable = "which"
        #endif
        XCTAssertNoThrow(
            try _requiresTools(executable)
        )
    }
}