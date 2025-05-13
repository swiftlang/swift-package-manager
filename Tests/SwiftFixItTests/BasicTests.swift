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

final class BasicTests: XCTestCase {
    func testPrimaryDiag() throws {
        try testAPI1File { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "let x = 1"),
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
    }

    func testNote() throws {
        try testAPI1File { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "let x = 1"),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        notes: [
                            Note(
                                text: "note",
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
                    ),
                ]
            )
        }
    }

    func testMultiplePrimaryDiagsWithNotes() throws {
        try testAPI1File { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "let x = 22"),
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
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        notes: [
                            Note(
                                text: "error2_note1",
                                location: .init(filename: filename, line: 1, column: 1, offset: 0),
                                fixIts: [
                                    // Make sure we apply this fix-it.
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

    func testNonOverlappingCompoundFixIt() throws {
        try testAPI1File { (filename: String) in
            .init(
                edits: .init(
                    input: """
                    var x = 1
                    var y = 2
                    var z = 3
                    var w = foo(1, 2)
                    """,
                    result: """
                    let x = 1
                    var y = 244
                    z = 3
                    w = fooo(1, 233)
                    """
                ),
                diagnostics: [
                    // Different lines.
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        fixIts: [
                            // Replacement.
                            .init(
                                start: .init(filename: filename, line: 1, column: 1, offset: 0),
                                end: .init(filename: filename, line: 1, column: 4, offset: 0),
                                text: "let"
                            ),
                            // Addition.
                            .init(
                                start: .init(filename: filename, line: 2, column: 10, offset: 0),
                                end: .init(filename: filename, line: 2, column: 10, offset: 0),
                                text: "44"
                            ),
                            // Deletion.
                            .init(
                                start: .init(filename: filename, line: 3, column: 1, offset: 0),
                                end: .init(filename: filename, line: 3, column: 5, offset: 0),
                                text: ""
                            ),
                        ]
                    ),
                    // Same line.
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error2",
                        location: .init(filename: filename, line: 4, column: 1, offset: 0),
                        fixIts: [
                            // Replacement.
                            .init(
                                start: .init(filename: filename, line: 4, column: 9, offset: 0),
                                end: .init(filename: filename, line: 4, column: 12, offset: 0),
                                text: "fooo"
                            ),
                            // Addition.
                            .init(
                                start: .init(filename: filename, line: 4, column: 17, offset: 0),
                                end: .init(filename: filename, line: 4, column: 17, offset: 0),
                                text: "33"
                            ),
                            // Deletion.
                            .init(
                                start: .init(filename: filename, line: 4, column: 1, offset: 0),
                                end: .init(filename: filename, line: 4, column: 5, offset: 0),
                                text: ""
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    func testOverlappingCompoundFixIt() throws {
        try testAPI1File { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "_ = 1"),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        fixIts: [
                            // Applied.
                            .init(
                                start: .init(filename: filename, line: 1, column: 1, offset: 0),
                                end: .init(filename: filename, line: 1, column: 6, offset: 0),
                                text: "_"
                            ),
                            // Skipped, overlaps with previous fix-it.
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
    }

    func testOverlappingFixIts() throws {
        try testAPI1File { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "_ = 1"),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        fixIts: [
                            // Applied.
                            .init(
                                start: .init(filename: filename, line: 1, column: 1, offset: 0),
                                end: .init(filename: filename, line: 1, column: 6, offset: 0),
                                text: "_"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        fixIts: [
                            // Skipped, overlaps with previous fix-it.
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
    }

    func testFixItsMultipleFiles() throws {
        try testAPI2Files { (filename1: String, filename2: String) in
            .init(
                edits: (
                    .init(input: "var x = 1", result: "let x = 1"),
                    .init(input: "var x = 1", result: "let x = 1")
                ),
                diagnostics: [
                    // filename1
                    PrimaryDiagnostic(
                        level: .warning,
                        text: "warning",
                        location: .init(filename: filename1, line: 1, column: 1, offset: 0),
                        fixIts: [
                            .init(
                                start: .init(filename: filename1, line: 1, column: 1, offset: 0),
                                end: .init(filename: filename1, line: 1, column: 4, offset: 0),
                                text: "let"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error",
                        location: .init(filename: filename1, line: 1, column: 1, offset: 0),
                        fixIts: [
                            .init(
                                start: .init(filename: filename1, line: 1, column: 1, offset: 0),
                                end: .init(filename: filename1, line: 1, column: 4, offset: 0),
                                text: "let"
                            ),
                        ]
                    ),
                    // filename2
                    PrimaryDiagnostic(
                        level: .warning,
                        text: "warning",
                        location: .init(filename: filename2, line: 1, column: 1, offset: 0),
                        fixIts: [
                            .init(
                                start: .init(filename: filename2, line: 1, column: 1, offset: 0),
                                end: .init(filename: filename2, line: 1, column: 4, offset: 0),
                                text: "let"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error",
                        location: .init(filename: filename2, line: 1, column: 1, offset: 0),
                        fixIts: [
                            .init(
                                start: .init(filename: filename2, line: 1, column: 1, offset: 0),
                                end: .init(filename: filename2, line: 1, column: 4, offset: 0),
                                text: "let"
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    func testNoteInDifferentFile() throws {
        try testAPI2Files { (filename1: String, filename2: String) in
            .init(
                edits: (
                    .init(input: "var x = 1", result: "let x = 1"),
                    .init(input: "var x = 1", result: "var x = 1")
                ),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error",
                        location: .init(filename: filename2, line: 1, column: 1, offset: 0),
                        notes: [
                            Note(
                                text: "note",
                                location: .init(filename: filename1, line: 1, column: 1, offset: 0),
                                fixIts: [
                                    .init(
                                        start: .init(filename: filename1, line: 1, column: 1, offset: 0),
                                        end: .init(filename: filename1, line: 1, column: 4, offset: 0),
                                        text: "let"
                                    ),
                                ]
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    func testDiagNotInTheSameFileAsFixIt() {
        do {
            try testAPI2Files { (filename1: String, filename2: String) in
                .init(
                    edits: (
                        .init(input: "var x = 1", result: "let x = 1"),
                        .init(input: "", result: "")
                    ),
                    diagnostics: [
                        PrimaryDiagnostic(
                            level: .error,
                            text: "error",
                            location: .init(filename: filename2, line: 1, column: 1, offset: 0),
                            fixIts: [
                                .init(
                                    start: .init(filename: filename1, line: 1, column: 1, offset: 0),
                                    end: .init(filename: filename1, line: 1, column: 4, offset: 0),
                                    text: "let"
                                ),
                            ]
                        ),
                    ]
                )
            }
        } catch {
            // Expected to throw an error.
            return
        }

        XCTFail()
    }
}
