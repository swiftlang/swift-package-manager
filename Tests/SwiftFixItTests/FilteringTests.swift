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

struct FilteringTests {
    @Test
    func testIgnoredDiag() throws {
        try testAPI1File { path in
            .init(
                edits: .init(input: "var x = 1", result: "var x = 22"),
                summary: .init(numberOfFixItsApplied: 1, numberOfFilesChanged: 1),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .ignored,
                        text: "ignored1",
                        location: .init(path: path, line: 1, column: 1),
                        fixIts: [
                            // Skipped, diagnostic is 'ignored'.
                            .init(
                                start: .init(path: path, line: 1, column: 1),
                                end: .init(path: path, line: 1, column: 4),
                                text: "let"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(path: path, line: 1, column: 9),
                        fixIts: [
                            // Applied.
                            .init(
                                start: .init(path: path, line: 1, column: 9),
                                end: .init(path: path, line: 1, column: 10),
                                text: "22"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .ignored,
                        text: "ignored2",
                        location: .init(path: path, line: 1, column: 1),
                        notes: [
                            Note(
                                text: "ignored2_note1",
                                location: .init(path: path, line: 1, column: 1)
                            ),
                            Note(
                                text: "ignored2_note2",
                                location: .init(path: path, line: 1, column: 1),
                                fixIts: [
                                    // Skipped, primary diagnostic is 'ignored'.
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
    func testDiagWithNoLocation() throws {
        try testAPI1File { path in
            .init(
                edits: .init(input: "var x = 1", result: "var x = 22"),
                summary: .init(numberOfFixItsApplied: 1, numberOfFilesChanged: 1),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: nil,
                        fixIts: [
                            // Skipped, no location.
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
                        fixIts: [
                            // Applied.
                            .init(
                                start: .init(path: path, line: 1, column: 9),
                                end: .init(path: path, line: 1, column: 10),
                                text: "22"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error3",
                        location: .init(path: path, line: 1, column: 1),
                        notes: [
                            Note(
                                text: "error3_note1",
                                location: .init(path: path, line: 1, column: 3),
                            ),
                            Note(
                                text: "error3_note2",
                                location: nil,
                                fixIts: [
                                    // Skipped, no location.
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
                        text: "error4",
                        location: nil,
                        notes: [
                            Note(
                                text: "error4_note1",
                                location: .init(path: path, line: 1, column: 1)
                            ),
                            Note(
                                text: "error4_note2",
                                location: .init(path: path, line: 1, column: 1),
                                fixIts: [
                                    // Skipped, primary diagnostic has no location.
                                    .init(
                                        start: .init(path: path, line: 1, column: 7),
                                        end: .init(path: path, line: 1, column: 8),
                                        text: ":"
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
    func testMultipleNotesWithFixIts() throws {
        try testAPI1File { path in
            .init(
                edits: .init(input: "var x = 1", result: "var x = 1"),
                summary: .init(numberOfFixItsApplied: 0, numberOfFilesChanged: 0),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(path: path, line: 1, column: 1),
                        notes: [
                            Note(
                                text: "error1_note1",
                                location: .init(path: path, line: 1, column: 1),
                                fixIts: [
                                    // Skipped, primary diagnostic has more than 1 note with fix-it.
                                    .init(
                                        start: .init(path: path, line: 1, column: 1),
                                        end: .init(path: path, line: 1, column: 4),
                                        text: "let"
                                    ),
                                ]
                            ),
                            Note(
                                text: "error1_note2",
                                location: .init(path: path, line: 1, column: 1),
                                fixIts: [
                                    // Skipped, primary diagnostic has more than 1 note with fix-it.
                                    .init(
                                        start: .init(path: path, line: 1, column: 9),
                                        end: .init(path: path, line: 1, column: 10),
                                        text: "22"
                                    ),
                                ]
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .warning,
                        text: "warning1",
                        location: .init(path: path, line: 1, column: 1),
                        notes: [
                            Note(
                                text: "warning1_note1",
                                location: .init(path: path, line: 1, column: 1),
                                fixIts: [
                                    // Skipped, primary diagnostic has more than 1 note with fix-it.
                                    .init(
                                        start: .init(path: path, line: 1, column: 5),
                                        end: .init(path: path, line: 1, column: 6),
                                        text: "y"
                                    ),
                                ]
                            ),
                            // This separator note should not make a difference.
                            Note(
                                text: "warning1_note2",
                                location: .init(path: path, line: 1, column: 1)
                            ),
                            Note(
                                text: "warning1_note3",
                                location: .init(path: path, line: 1, column: 1),
                                fixIts: [
                                    // Skipped, primary diagnostic has more than 1 note with fix-it.
                                    .init(
                                        start: .init(path: path, line: 1, column: 7),
                                        end: .init(path: path, line: 1, column: 8),
                                        text: ":"
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
    func testDuplicatePrimaryDiag() throws {
        try testAPI1File { path in
            .init(
                edits: .init(input: "var x = (1, 1)", result: "let x = (22, 13)"),
                summary: .init(numberOfFixItsApplied: 3, numberOfFilesChanged: 1),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(path: path, line: 1, column: 1),
                        fixIts: [
                            // Applied.
                            .init(
                                start: .init(path: path, line: 1, column: 1),
                                end: .init(path: path, line: 1, column: 4),
                                text: "let"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .warning,
                        text: "warning1",
                        location: .init(path: path, line: 1, column: 10),
                        notes: [
                            Note(
                                text: "warning1_note1",
                                location: .init(path: path, line: 1, column: 10),
                                fixIts: [
                                    // Applied.
                                    .init(
                                        start: .init(path: path, line: 1, column: 10),
                                        end: .init(path: path, line: 1, column: 11),
                                        text: "22"
                                    ),
                                ]
                            ),
                            Note(
                                text: "warning1_note2",
                                location: .init(path: path, line: 1, column: 5),
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(path: path, line: 1, column: 1),
                        notes: [
                            Note(
                                text: "error1_note1",
                                location: .init(path: path, line: 1, column: 5),
                                fixIts: [
                                    // Skipped, duplicate primary diagnostic.
                                    .init(
                                        start: .init(path: path, line: 1, column: 5),
                                        end: .init(path: path, line: 1, column: 6),
                                        text: "y"
                                    ),
                                ]
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .warning,
                        text: "warning1",
                        location: .init(path: path, line: 1, column: 10),
                        fixIts: [
                            // Skipped, duplicate primary diagnostic.
                            .init(
                                start: .init(path: path, line: 1, column: 7),
                                end: .init(path: path, line: 1, column: 8),
                                text: ":"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error2",
                        location: .init(path: path, line: 1, column: 14),
                        fixIts: [
                            // Applied.
                            .init(
                                start: .init(path: path, line: 1, column: 14),
                                end: .init(path: path, line: 1, column: 14),
                                text: "3"
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    @Test
    func testDuplicateReplacementFixIts() throws {
        try testAPI1File { path in
            .init(
                edits: .init(input: "var x = 1", result: "let x = 22"),
                summary: .init(
                    // 4 because skipped by SwiftIDEUtils.FixItApplier, not SwiftFixIt.
                    numberOfFixItsApplied: 4,
                    numberOfFilesChanged: 1
                ),
                diagnostics: [
                    // On primary diagnostics.
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(path: path, line: 1, column: 1),
                        fixIts: [
                            // Applied.
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
                        fixIts: [
                            // Skipped.
                            .init(
                                start: .init(path: path, line: 1, column: 1),
                                end: .init(path: path, line: 1, column: 4),
                                text: "let"
                            ),
                        ]
                    ),
                    // On notes.
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error3",
                        location: .init(path: path, line: 1, column: 9),
                        notes: [
                            Note(
                                text: "error3_note1",
                                location: .init(path: path, line: 1, column: 9),
                                fixIts: [
                                    // Applied.
                                    .init(
                                        start: .init(path: path, line: 1, column: 9),
                                        end: .init(path: path, line: 1, column: 10),
                                        text: "22"
                                    ),
                                ]
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error4",
                        location: .init(path: path, line: 1, column: 9),
                        notes: [
                            Note(
                                text: "error4_note1",
                                location: .init(path: path, line: 1, column: 9),
                                fixIts: [
                                    // Skipped.
                                    .init(
                                        start: .init(path: path, line: 1, column: 9),
                                        end: .init(path: path, line: 1, column: 10),
                                        text: "22"
                                    ),
                                ]
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    func testDuplicateInsertionFixIts() throws {
        try testAPI1File { path in
            .init(
                edits: .init(input: "var x = 1", result: "@W var yx = 21"),
                summary: .init(
                    // 6 because skipped by SwiftIDEUtils.FixItApplier, not SwiftFixIt.
                    numberOfFixItsApplied: 6,
                    numberOfFilesChanged: 1
                ),
                diagnostics: [
                    // Duplicate fix-it pairs:
                    // - on primary + on primary.
                    // - on note + on note.
                    // - on primary + on note.
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1_fixit1",
                        location: .init(path: path, line: 1, column: 1),
                        fixIts: [
                            // Applied.
                            .init(
                                start: .init(path: path, line: 1, column: 1),
                                end: .init(path: path, line: 1, column: 1),
                                text: "@W "
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error2_fixit2",
                        location: .init(path: path, line: 1, column: 2),
                        notes: [
                            Note(
                                text: "error2_note1",
                                location: .init(path: path, line: 1, column: 9),
                                fixIts: [
                                    // Applied.
                                    .init(
                                        start: .init(path: path, line: 1, column: 9),
                                        end: .init(path: path, line: 1, column: 9),
                                        text: "2"
                                    ),
                                ]
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error3_fixit1",
                        location: .init(path: path, line: 1, column: 3),
                        fixIts: [
                            // Skipped, duplicate insertion.
                            .init(
                                start: .init(path: path, line: 1, column: 1),
                                end: .init(path: path, line: 1, column: 1),
                                text: "@W "
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error4_fixit3",
                        location: .init(path: path, line: 1, column: 4),
                        fixIts: [
                            // Applied.
                            .init(
                                start: .init(path: path, line: 1, column: 5),
                                end: .init(path: path, line: 1, column: 5),
                                text: "y"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error5_fixit2",
                        location: .init(path: path, line: 1, column: 5),
                        notes: [
                            Note(
                                text: "error5_note1",
                                location: .init(path: path, line: 1, column: 9),
                                fixIts: [
                                    // Skipped, duplicate insertion.
                                    .init(
                                        start: .init(path: path, line: 1, column: 9),
                                        end: .init(path: path, line: 1, column: 9),
                                        text: "2"
                                    ),
                                ]
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error6_fixit3",
                        location: .init(path: path, line: 1, column: 6),
                        notes: [
                            Note(
                                text: "error6_note1",
                                location: .init(path: path, line: 1, column: 5),
                                fixIts: [
                                    // Skipped, duplicate insertion.
                                    .init(
                                        start: .init(path: path, line: 1, column: 5),
                                        end: .init(path: path, line: 1, column: 5),
                                        text: "y"
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
