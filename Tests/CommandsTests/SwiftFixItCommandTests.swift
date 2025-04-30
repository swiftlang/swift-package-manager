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

import _InternalTestSupport
@testable
import Commands
import XCTest

final class FixItCommandTests: CommandsTestCase {
    func testHelp() async throws {
        let stdout = try await SwiftPM.fixit.execute(["-help"]).stdout

        XCTAssert(stdout.contains("USAGE: swift fixit"), stdout)
        XCTAssert(stdout.contains("-h, -help, --help"), stdout)
    }
}
