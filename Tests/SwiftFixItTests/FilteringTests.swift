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

final class FilteringTests: XCTestCase {
    func testIgnoredDiag() throws {
        try testAPI1File { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "var x = 22"),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .ignored,
                        text: "ignored1",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        fixIts: [
                            // Skipped, diagnostic is 'ignored'.
                            .init(
                                start: .init(filename: filename, line: 1, column: 1, offset: 0),
                                end: .init(filename: filename, line: 1, column: 4, offset: 0),
                                text: "let"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(filename: filename, line: 1, column: 9, offset: 0),
                        fixIts: [
                            // Applied.
                            .init(
                                start: .init(filename: filename, line: 1, column: 9, offset: 0),
                                end: .init(filename: filename, line: 1, column: 10, offset: 0),
                                text: "22"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .ignored,
                        text: "ignored2",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        notes: [
                            Note(
                                text: "ignored2_note1",
                                location: .init(filename: filename, line: 1, column: 1, offset: 0)
                            ),
                            Note(
                                text: "ignored2_note2",
                                location: .init(filename: filename, line: 1, column: 1, offset: 0),
                                fixIts: [
                                    // Skipped, primary diagnostic is 'ignored'.
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

    func testDiagWithNoLocation() throws {
        try testAPI1File { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "var x = 22"),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: nil,
                        fixIts: [
                            // Skipped, no location.
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
                        fixIts: [
                            // Applied.
                            .init(
                                start: .init(filename: filename, line: 1, column: 9, offset: 0),
                                end: .init(filename: filename, line: 1, column: 10, offset: 0),
                                text: "22"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error3",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        notes: [
                            Note(
                                text: "error3_note1",
                                location: .init(filename: filename, line: 1, column: 3, offset: 0),
                            ),
                            Note(
                                text: "error3_note2",
                                location: nil,
                                fixIts: [
                                    // Skipped, no location.
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
                        text: "error4",
                        location: nil,
                        notes: [
                            Note(
                                text: "error4_note1",
                                location: .init(filename: filename, line: 1, column: 1, offset: 0)
                            ),
                            Note(
                                text: "error4_note2",
                                location: .init(filename: filename, line: 1, column: 1, offset: 0),
                                fixIts: [
                                    // Skipped, primary diagnostic has no location.
                                    .init(
                                        start: .init(filename: filename, line: 1, column: 7, offset: 0),
                                        end: .init(filename: filename, line: 1, column: 8, offset: 0),
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

    func testMultipleNotesWithFixIts() throws {
        try testAPI1File { filename in
            .init(
                edits: .init(input: "var x = 1", result: "var x = 1"),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        notes: [
                            Note(
                                text: "error1_note1",
                                location: .init(filename: filename, line: 1, column: 1, offset: 0),
                                fixIts: [
                                    // Skipped, primary diagnostic has more than 1 note with fix-it.
                                    .init(
                                        start: .init(filename: filename, line: 1, column: 1, offset: 0),
                                        end: .init(filename: filename, line: 1, column: 4, offset: 0),
                                        text: "let"
                                    ),
                                ]
                            ),
                            Note(
                                text: "error1_note2",
                                location: .init(filename: filename, line: 1, column: 1, offset: 0),
                                fixIts: [
                                    // Skipped, primary diagnostic has more than 1 note with fix-it.
                                    .init(
                                        start: .init(filename: filename, line: 1, column: 9, offset: 0),
                                        end: .init(filename: filename, line: 1, column: 10, offset: 0),
                                        text: "22"
                                    ),
                                ]
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .warning,
                        text: "warning1",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        notes: [
                            Note(
                                text: "warning1_note1",
                                location: .init(filename: filename, line: 1, column: 1, offset: 0),
                                fixIts: [
                                    // Skipped, primary diagnostic has more than 1 note with fix-it.
                                    .init(
                                        start: .init(filename: filename, line: 1, column: 5, offset: 0),
                                        end: .init(filename: filename, line: 1, column: 6, offset: 0),
                                        text: "y"
                                    ),
                                ]
                            ),
                            // This separator note should not make a difference.
                            Note(
                                text: "warning1_note2",
                                location: .init(filename: filename, line: 1, column: 1, offset: 0)
                            ),
                            Note(
                                text: "warning1_note3",
                                location: .init(filename: filename, line: 1, column: 1, offset: 0),
                                fixIts: [
                                    // Skipped, primary diagnostic has more than 1 note with fix-it.
                                    .init(
                                        start: .init(filename: filename, line: 1, column: 7, offset: 0),
                                        end: .init(filename: filename, line: 1, column: 8, offset: 0),
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

    func testDuplicateReplacementFixIts() throws {
        try testAPI1File { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "let x = 22"),
                diagnostics: [
                    // On primary diagnostics.
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        fixIts: [
                            // Applied.
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
                        fixIts: [
                            // Applied.
                            .init(
                                start: .init(filename: filename, line: 1, column: 1, offset: 0),
                                end: .init(filename: filename, line: 1, column: 4, offset: 0),
                                text: "let"
                            ),
                        ]
                    ),
                    // On notes.
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error3",
                        location: .init(filename: filename, line: 1, column: 9, offset: 0),
                        notes: [
                            Note(
                                text: "error3_note1",
                                location: .init(filename: filename, line: 1, column: 9, offset: 0),
                                fixIts: [
                                    // Applied.
                                    .init(
                                        start: .init(filename: filename, line: 1, column: 9, offset: 0),
                                        end: .init(filename: filename, line: 1, column: 10, offset: 0),
                                        text: "22"
                                    ),
                                ]
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error4",
                        location: .init(filename: filename, line: 1, column: 9, offset: 0),
                        notes: [
                            Note(
                                text: "error4_note1",
                                location: .init(filename: filename, line: 1, column: 9, offset: 0),
                                fixIts: [
                                    // Applied.
                                    .init(
                                        start: .init(filename: filename, line: 1, column: 9, offset: 0),
                                        end: .init(filename: filename, line: 1, column: 10, offset: 0),
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
}
