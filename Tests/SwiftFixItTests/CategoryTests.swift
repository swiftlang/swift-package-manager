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
    func testCorrectCategory() throws {
        try testAPI1File(categories: ["Other", "Test"]) { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "let _ = 1"),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        category: "Test",
                        fixIts: [
                            // Applied, correct category.
                            .init(
                                start: .init(filename: filename, line: 1, column: 1, offset: 0),
                                end: .init(filename: filename, line: 1, column: 4, offset: 0),
                                text: "let"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error2",
                        location: .init(filename: filename, line: 1, column: 4, offset: 0),
                        category: "Other",
                        fixIts: [
                            // Applied, correct category.
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

    func testCorrectCategoryWithNotes() throws {
        try testAPI1File(categories: ["Other", "Test"]) { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "let _ = 22"),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        category: "Test",
                        notes: [
                            Note(
                                text: "error1_note1",
                                location: .init(filename: filename, line: 1, column: 1, offset: 0),
                                fixIts: [
                                    // Applied, primary diagnostic has correct category.
                                    // Category of note does not matter.
                                    .init(
                                        start: .init(filename: filename, line: 1, column: 1, offset: 0),
                                        end: .init(filename: filename, line: 1, column: 4, offset: 0),
                                        text: "let"
                                    ),
                                ]
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error2",
                        location: .init(filename: filename, line: 1, column: 4, offset: 0),
                        category: "Other",
                        notes: [
                            // This separator note should not make a difference.
                            Note(
                                text: "error2_note1",
                                location: .init(filename: filename, line: 1, column: 3, offset: 0),
                            ),
                            Note(
                                text: "error2_note2",
                                location: .init(filename: filename, line: 1, column: 4, offset: 0),
                                fixIts: [
                                    // Applied, primary diagnostic has correct category.
                                    // Category of note does not matter.
                                    .init(
                                        start: .init(filename: filename, line: 1, column: 5, offset: 0),
                                        end: .init(filename: filename, line: 1, column: 6, offset: 0),
                                        text: "_"
                                    ),
                                ]
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error3",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        category: "Test",
                        notes: [
                            Note(
                                text: "error3_note1",
                                location: .init(filename: filename, line: 1, column: 1, offset: 0),
                                category: "Wrong",
                                fixIts: [
                                    // Applied, primary diagnostic has correct category.
                                    // Category of note does not matter.
                                    .init(
                                        start: .init(filename: filename, line: 1, column: 9, offset: 0),
                                        end: .init(filename: filename, line: 1, column: 10, offset: 0),
                                        text: "22",
                                    ),
                                ]
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    func testNoCategory() throws {
        try testAPI1File(categories: ["Test"]) { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "var x = 22"),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        fixIts: [
                            // Skipped, no category.
                            .init(
                                start: .init(filename: filename, line: 1, column: 1, offset: 0),
                                end: .init(filename: filename, line: 1, column: 4, offset: 0),
                                text: "let"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error2",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        category: "Test",
                        fixIts: [
                            // Applied, correct category.
                            .init(
                                start: .init(filename: filename, line: 1, column: 9, offset: 0),
                                end: .init(filename: filename, line: 1, column: 10, offset: 0),
                                text: "22",
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    func testNoCategoryWithNotes() throws {
        try testAPI1File(categories: ["Test"]) { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "var x = 22"),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(filename: filename, line: 1, column: 5, offset: 0),
                        category: nil,
                        notes: [
                            // This separator note should not make a difference.
                            Note(
                                text: "error1_note1",
                                location: .init(filename: filename, line: 1, column: 3, offset: 0),
                            ),
                            Note(
                                text: "error1_note2",
                                location: .init(filename: filename, line: 1, column: 1, offset: 0),
                                fixIts: [
                                    // Skipped, primary diagnostic has no category.
                                    .init(
                                        start: .init(filename: filename, line: 1, column: 1, offset: 0),
                                        end: .init(filename: filename, line: 1, column: 4, offset: 0),
                                        text: "let",
                                    ),
                                ]
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error2",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        category: "Test",
                        fixIts: [
                            // Applied, correct category.
                            .init(
                                start: .init(filename: filename, line: 1, column: 9, offset: 0),
                                end: .init(filename: filename, line: 1, column: 10, offset: 0),
                                text: "22",
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error3",
                        location: .init(filename: filename, line: 1, column: 4, offset: 0),
                        category: nil,
                        notes: [
                            Note(
                                text: "error3_note1",
                                location: .init(filename: filename, line: 1, column: 4, offset: 0),
                                category: "Test",
                                fixIts: [
                                    // Skipped, primary diagnostic has no category.
                                    // Category of note does not matter.
                                    .init(
                                        start: .init(filename: filename, line: 1, column: 5, offset: 0),
                                        end: .init(filename: filename, line: 1, column: 6, offset: 0),
                                        text: "_"
                                    ),
                                ]
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    func testWrongCategory() throws {
        try testAPI1File(categories: ["Test"]) { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "var x = 22"),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        category: "Other",
                        fixIts: [
                            // Skipped, wrong category.
                            .init(
                                start: .init(filename: filename, line: 1, column: 1, offset: 0),
                                end: .init(filename: filename, line: 1, column: 4, offset: 0),
                                text: "let"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error2",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        category: "Test",
                        fixIts: [
                            // Applied, correct category.
                            .init(
                                start: .init(filename: filename, line: 1, column: 9, offset: 0),
                                end: .init(filename: filename, line: 1, column: 10, offset: 0),
                                text: "22",
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    func testWrongCategoryWithNotes() throws {
        try testAPI1File(categories: ["Test"]) { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "var x = 22"),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(filename: filename, line: 1, column: 5, offset: 0),
                        category: "Other",
                        notes: [
                            // This separator note should not make a difference.
                            Note(
                                text: "error1_note1",
                                location: .init(filename: filename, line: 1, column: 3, offset: 0),
                            ),
                            Note(
                                text: "error1_note2",
                                location: .init(filename: filename, line: 1, column: 1, offset: 0),
                                fixIts: [
                                    // Skipped, primary diagnostic has wrong category.
                                    .init(
                                        start: .init(filename: filename, line: 1, column: 1, offset: 0),
                                        end: .init(filename: filename, line: 1, column: 4, offset: 0),
                                        text: "let",
                                    ),
                                ]
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error2",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        category: "Test",
                        fixIts: [
                            // Applied, correct category.
                            .init(
                                start: .init(filename: filename, line: 1, column: 9, offset: 0),
                                end: .init(filename: filename, line: 1, column: 10, offset: 0),
                                text: "22",
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error3",
                        location: .init(filename: filename, line: 1, column: 4, offset: 0),
                        category: "Other",
                        notes: [
                            Note(
                                text: "error3_note1",
                                location: .init(filename: filename, line: 1, column: 4, offset: 0),
                                category: "Test",
                                fixIts: [
                                    // Skipped, primary diagnostic has wrong category.
                                    // Category of note does not matter.
                                    .init(
                                        start: .init(filename: filename, line: 1, column: 5, offset: 0),
                                        end: .init(filename: filename, line: 1, column: 6, offset: 0),
                                        text: "_"
                                    ),
                                ]
                            ),
                        ]
                    ),
                ]
            )
        }
    }
}
