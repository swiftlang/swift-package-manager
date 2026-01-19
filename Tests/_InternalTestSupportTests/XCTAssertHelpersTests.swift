//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025-2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import Basics
import Testing
import func _InternalTestSupport._requiresTools

@Suite(
    .tags(
        .TestSize.small,
    ),
)
struct RequireToolsTests {
    @Test func errorIsThrownIfExecutableIsNotFoundOnThePath() {
        #expect(throws: (any Error).self) {
        // #expectect(throws: AsyncProcessResult.Error.self) {
            try _requiresTools("doesNotExists")
        }
    }

    @Test func errorIsNotThrownIfExecutableIsOnThePath() throws {
        // Essentially call either "which which" or "where.exe where.exe"
        #if os(Windows)
        let executable = "where.exe"
        #else
        let executable = "which"
        #endif
        #expect(throws: Never.self) {
            try _requiresTools(executable)
        }
    }
}
