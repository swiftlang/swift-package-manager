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

import XCTest

final class CategoryTests: XCTestCase {
    func testCategoryFiltering() throws {
        // Check that the fix-it gets ignored because category doesn't match
        try testAPI1File(categories: ["Test"]) { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "var x = 1"),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        fixIts: [
                            .init(
                                start: .init(filename: filename, line: 1, column: 1, offset: 0),
                                end: .init(filename: filename, line: 1, column: 4, offset: 0),
                                text: "let"
                            ),
                        ]
                    ),
                ]
            )
        }

        // Check that the fix-it gets ignored because category doesn't match
        try testAPI1File(categories: ["Test"]) { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "var x = 1"),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        category: "Other",
                        fixIts: [
                            .init(
                                start: .init(filename: filename, line: 1, column: 1, offset: 0),
                                end: .init(filename: filename, line: 1, column: 4, offset: 0),
                                text: "let"
                            ),
                        ]
                    ),
                ]
            )
        }

        try testAPI1File(categories: ["Other", "Test"]) { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "let _ = 1"),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        category: "Test",
                        fixIts: [
                            .init(
                                start: .init(filename: filename, line: 1, column: 1, offset: 0),
                                end: .init(filename: filename, line: 1, column: 4, offset: 0),
                                text: "let"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error",
                        location: .init(filename: filename, line: 1, column: 4, offset: 0),
                        category: "Other",
                        fixIts: [
                            .init(
                                start: .init(filename: filename, line: 1, column: 5, offset: 0),
                                end: .init(filename: filename, line: 1, column: 6, offset: 0),
                                text: "_"
                            ),
                        ]
                    ),
                ]
            )
        }
    }
}
