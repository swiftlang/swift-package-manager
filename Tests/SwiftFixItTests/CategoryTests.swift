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

import Testing

struct CategoryTests {
    @Test
    func testCorrectCategory() throws {
        try testAPI1File(categories: ["Other", "Test"]) { path in
            .init(
                edits: .init(input: "var x = 1", result: "let _ = 1"),
                summary: .init(numberOfFixItsApplied: 2, numberOfFilesChanged: 1),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(path: path, line: 1, column: 1),
                        category: "Test",
                        fixIts: [
                            // Applied, correct category.
                            .init(
                                start: .init(path: path, line: 1, column: 1),
                                end: .init(path: path, line: 1, column: 4),
                                text: "let"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error2",
                        location: .init(path: path, line: 1, column: 4),
                        category: "Other",
                        fixIts: [
                            // Applied, correct category.
                            .init(
                                start: .init(path: path, line: 1, column: 5),
                                end: .init(path: path, line: 1, column: 6),
                                text: "_"
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    @Test
    func testCorrectCategoryWithNotes() throws {
        try testAPI1File(categories: ["Other", "Test"]) { path in
            .init(
                edits: .init(input: "var x = 1", result: "let _ = 22"),
                summary: .init(numberOfFixItsApplied: 3, numberOfFilesChanged: 1),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(path: path, line: 1, column: 1),
                        category: "Test",
                        notes: [
                            Note(
                                text: "error1_note1",
                                location: .init(path: path, line: 1, column: 1),
                                fixIts: [
                                    // Applied, primary diagnostic has correct category.
                                    // Category of note does not matter.
                                    .init(
                                        start: .init(path: path, line: 1, column: 1),
                                        end: .init(path: path, line: 1, column: 4),
                                        text: "let"
                                    ),
                                ]
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error2",
                        location: .init(path: path, line: 1, column: 4),
                        category: "Other",
                        notes: [
                            // This separator note should not make a difference.
                            Note(
                                text: "error2_note1",
                                location: .init(path: path, line: 1, column: 3),
                            ),
                            Note(
                                text: "error2_note2",
                                location: .init(path: path, line: 1, column: 4),
                                fixIts: [
                                    // Applied, primary diagnostic has correct category.
                                    // Category of note does not matter.
                                    .init(
                                        start: .init(path: path, line: 1, column: 5),
                                        end: .init(path: path, line: 1, column: 6),
                                        text: "_"
                                    ),
                                ]
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error3",
                        location: .init(path: path, line: 1, column: 1),
                        category: "Test",
                        notes: [
                            Note(
                                text: "error3_note1",
                                location: .init(path: path, line: 1, column: 1),
                                category: "Wrong",
                                fixIts: [
                                    // Applied, primary diagnostic has correct category.
                                    // Category of note does not matter.
                                    .init(
                                        start: .init(path: path, line: 1, column: 9),
                                        end: .init(path: path, line: 1, column: 10),
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

    @Test
    func testNoCategory() throws {
        try testAPI1File(categories: ["Test"]) { path in
            .init(
                edits: .init(input: "var x = 1", result: "var x = 22"),
                summary: .init(numberOfFixItsApplied: 1, numberOfFilesChanged: 1),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(path: path, line: 1, column: 1),
                        fixIts: [
                            // Skipped, no category.
                            .init(
                                start: .init(path: path, line: 1, column: 1),
                                end: .init(path: path, line: 1, column: 4),
                                text: "let"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error2",
                        location: .init(path: path, line: 1, column: 1),
                        category: "Test",
                        fixIts: [
                            // Applied, correct category.
                            .init(
                                start: .init(path: path, line: 1, column: 9),
                                end: .init(path: path, line: 1, column: 10),
                                text: "22",
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    @Test
    func testNoCategoryWithNotes() throws {
        try testAPI1File(categories: ["Test"]) { path in
            .init(
                edits: .init(input: "var x = 1", result: "var x = 22"),
                summary: .init(numberOfFixItsApplied: 1, numberOfFilesChanged: 1),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(path: path, line: 1, column: 5),
                        category: nil,
                        notes: [
                            // This separator note should not make a difference.
                            Note(
                                text: "error1_note1",
                                location: .init(path: path, line: 1, column: 3),
                            ),
                            Note(
                                text: "error1_note2",
                                location: .init(path: path, line: 1, column: 1),
                                fixIts: [
                                    // Skipped, primary diagnostic has no category.
                                    .init(
                                        start: .init(path: path, line: 1, column: 1),
                                        end: .init(path: path, line: 1, column: 4),
                                        text: "let",
                                    ),
                                ]
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error2",
                        location: .init(path: path, line: 1, column: 1),
                        category: "Test",
                        fixIts: [
                            // Applied, correct category.
                            .init(
                                start: .init(path: path, line: 1, column: 9),
                                end: .init(path: path, line: 1, column: 10),
                                text: "22",
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error3",
                        location: .init(path: path, line: 1, column: 4),
                        category: nil,
                        notes: [
                            Note(
                                text: "error3_note1",
                                location: .init(path: path, line: 1, column: 4),
                                category: "Test",
                                fixIts: [
                                    // Skipped, primary diagnostic has no category.
                                    // Category of note does not matter.
                                    .init(
                                        start: .init(path: path, line: 1, column: 5),
                                        end: .init(path: path, line: 1, column: 6),
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

    @Test
    func testWrongCategory() throws {
        try testAPI1File(categories: ["Test"]) { path in
            .init(
                edits: .init(input: "var x = 1", result: "var x = 22"),
                summary: .init(numberOfFixItsApplied: 1, numberOfFilesChanged: 1),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(path: path, line: 1, column: 1),
                        category: "Other",
                        fixIts: [
                            // Skipped, wrong category.
                            .init(
                                start: .init(path: path, line: 1, column: 1),
                                end: .init(path: path, line: 1, column: 4),
                                text: "let"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error2",
                        location: .init(path: path, line: 1, column: 1),
                        category: "Test",
                        fixIts: [
                            // Applied, correct category.
                            .init(
                                start: .init(path: path, line: 1, column: 9),
                                end: .init(path: path, line: 1, column: 10),
                                text: "22",
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    @Test
    func testWrongCategoryWithNotes() throws {
        try testAPI1File(categories: ["Test"]) { path in
            .init(
                edits: .init(input: "var x = 1", result: "var x = 22"),
                summary: .init(numberOfFixItsApplied: 1, numberOfFilesChanged: 1),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(path: path, line: 1, column: 5),
                        category: "Other",
                        notes: [
                            // This separator note should not make a difference.
                            Note(
                                text: "error1_note1",
                                location: .init(path: path, line: 1, column: 3),
                            ),
                            Note(
                                text: "error1_note2",
                                location: .init(path: path, line: 1, column: 1),
                                fixIts: [
                                    // Skipped, primary diagnostic has wrong category.
                                    .init(
                                        start: .init(path: path, line: 1, column: 1),
                                        end: .init(path: path, line: 1, column: 4),
                                        text: "let",
                                    ),
                                ]
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error2",
                        location: .init(path: path, line: 1, column: 1),
                        category: "Test",
                        fixIts: [
                            // Applied, correct category.
                            .init(
                                start: .init(path: path, line: 1, column: 9),
                                end: .init(path: path, line: 1, column: 10),
                                text: "22",
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error3",
                        location: .init(path: path, line: 1, column: 4),
                        category: "Other",
                        notes: [
                            Note(
                                text: "error3_note1",
                                location: .init(path: path, line: 1, column: 4),
                                category: "Test",
                                fixIts: [
                                    // Skipped, primary diagnostic has wrong category.
                                    // Category of note does not matter.
                                    .init(
                                        start: .init(path: path, line: 1, column: 5),
                                        end: .init(path: path, line: 1, column: 6),
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
