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

import Testing
import enum PackageModel.Sanitizer

@Suite(
    .tags(
        .TestSize.small,
        .FunctionalArea.Sanitizer,
    ),
)
struct SanitizerExtensionTests {
    @Test(
        arguments: Sanitizer.allCases
    )
    func creatingSanitizers(sanitizer: Sanitizer) throws {
            #expect(sanitizer == Sanitizer(argument: sanitizer.shortName))
    }

    @Test
    func invalidSanitizer() throws {
        #expect(Sanitizer(argument: "invalid") == nil)
    }
}
