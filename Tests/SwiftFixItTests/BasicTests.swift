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

struct BasicTests {
    @Test
    func testNoDiagnostics() throws {
        // Edge case.
        try testAPI1File { _ in
            .init(
                edits: .init(input: "var x = 1", result: "var x = 1"),
                summary: .init(numberOfFixItsApplied: 0, numberOfFilesChanged: 0),
                diagnostics: []
            )
        }
    }

    @Test
    func testPrimaryDiag() throws {
        try testAPI1File { path in
            .init(
                edits: .init(input: "var x = 1", result: "let x = 1"),
                summary: .init(numberOfFixItsApplied: 1, numberOfFilesChanged: 1),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error",
                        location: .init(path: path, line: 1, column: 1),
                        fixIts: [
                            .init(
                                start: .init(path: path, line: 1, column: 1),
                                end: .init(path: path, line: 1, column: 4),
                                text: "let"
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    @Test
    func testNote() throws {
        try testAPI1File { path in
            .init(
                edits: .init(input: "var x = 1", result: "let x = 1"),
                summary: .init(numberOfFixItsApplied: 1, numberOfFilesChanged: 1),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error",
                        location: .init(path: path, line: 1, column: 1),
                        notes: [
                            Note(
                                text: "note",
                                location: .init(path: path, line: 1, column: 1),
                                fixIts: [
                                    .init(
                                        start: .init(path: path, line: 1, column: 1),
                                        end: .init(path: path, line: 1, column: 4),
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

    @Test
    func testMultiplePrimaryDiagsWithNotes() throws {
        try testAPI1File { path in
            .init(
                edits: .init(input: "var x = 1", result: "let x = 22"),
                summary: .init(numberOfFixItsApplied: 2, numberOfFilesChanged: 1),
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
                        location: .init(path: path, line: 1, column: 1),
                        notes: [
                            Note(
                                text: "error2_note1",
                                location: .init(path: path, line: 1, column: 1),
                                fixIts: [
                                    // Make sure we apply this fix-it.
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

    @Test
    func testNonOverlappingCompoundFixIt() throws {
        try testAPI1File { path in
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
                summary: .init(numberOfFixItsApplied: 2, numberOfFilesChanged: 1),
                diagnostics: [
                    // Different lines.
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(path: path, line: 1, column: 1),
                        fixIts: [
                            // Replacement.
                            .init(
                                start: .init(path: path, line: 1, column: 1),
                                end: .init(path: path, line: 1, column: 4),
                                text: "let"
                            ),
                            // Addition.
                            .init(
                                start: .init(path: path, line: 2, column: 10),
                                end: .init(path: path, line: 2, column: 10),
                                text: "44"
                            ),
                            // Deletion.
                            .init(
                                start: .init(path: path, line: 3, column: 1),
                                end: .init(path: path, line: 3, column: 5),
                                text: ""
                            ),
                        ]
                    ),
                    // Same line.
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error2",
                        location: .init(path: path, line: 4, column: 1),
                        fixIts: [
                            // Replacement.
                            .init(
                                start: .init(path: path, line: 4, column: 9),
                                end: .init(path: path, line: 4, column: 12),
                                text: "fooo"
                            ),
                            // Addition.
                            .init(
                                start: .init(path: path, line: 4, column: 17),
                                end: .init(path: path, line: 4, column: 17),
                                text: "33"
                            ),
                            // Deletion.
                            .init(
                                start: .init(path: path, line: 4, column: 1),
                                end: .init(path: path, line: 4, column: 5),
                                text: ""
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    @Test
    func testOverlappingCompoundFixIt() throws {
        try testAPI1File { path in
            .init(
                edits: .init(input: "var x = 1", result: "_ = 1"),
                summary: .init(numberOfFixItsApplied: 1, numberOfFilesChanged: 1),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error",
                        location: .init(path: path, line: 1, column: 1),
                        fixIts: [
                            // Applied.
                            .init(
                                start: .init(path: path, line: 1, column: 1),
                                end: .init(path: path, line: 1, column: 6),
                                text: "_"
                            ),
                            // Skipped, overlaps with previous fix-it.
                            .init(
                                start: .init(path: path, line: 1, column: 1),
                                end: .init(path: path, line: 1, column: 4),
                                text: "let"
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    @Test
    func testOverlappingFixIts() throws {
        try testAPI1File { path in
            .init(
                edits: .init(input: "var x = 1", result: "_ = 1"),
                summary: .init(
                    // 2 because skipped by SwiftIDEUtils.FixItApplier, not SwiftFixIt.
                    numberOfFixItsApplied: 2 /**/,
                    numberOfFilesChanged: 1
                ),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(path: path, line: 1, column: 1),
                        fixIts: [
                            // Applied.
                            .init(
                                start: .init(path: path, line: 1, column: 1),
                                end: .init(path: path, line: 1, column: 6),
                                text: "_"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error2",
                        location: .init(path: path, line: 1, column: 1),
                        fixIts: [
                            // Skipped, overlaps with previous fix-it.
                            .init(
                                start: .init(path: path, line: 1, column: 1),
                                end: .init(path: path, line: 1, column: 4),
                                text: "let"
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    @Test
    func testFixItsMultipleFiles() throws {
        try testAPI2Files { path1, path2 in
            .init(
                edits: (
                    .init(input: "var x = 1", result: "let _ = 1"),
                    .init(input: "var x = 1", result: "let _ = 1")
                ),
                summary: .init(numberOfFixItsApplied: 4, numberOfFilesChanged: 2),
                diagnostics: [
                    // path1
                    PrimaryDiagnostic(
                        level: .warning,
                        text: "warning1",
                        location: .init(path: path1, line: 1, column: 1),
                        fixIts: [
                            .init(
                                start: .init(path: path1, line: 1, column: 1),
                                end: .init(path: path1, line: 1, column: 4),
                                text: "let"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error1",
                        location: .init(path: path1, line: 1, column: 5),
                        fixIts: [
                            .init(
                                start: .init(path: path1, line: 1, column: 5),
                                end: .init(path: path1, line: 1, column: 6),
                                text: "_"
                            ),
                        ]
                    ),
                    // path2
                    PrimaryDiagnostic(
                        level: .warning,
                        text: "warning2",
                        location: .init(path: path2, line: 1, column: 5),
                        fixIts: [
                            .init(
                                start: .init(path: path2, line: 1, column: 5),
                                end: .init(path: path2, line: 1, column: 6),
                                text: "_"
                            ),
                        ]
                    ),
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error2",
                        location: .init(path: path2, line: 1, column: 1),
                        fixIts: [
                            .init(
                                start: .init(path: path2, line: 1, column: 1),
                                end: .init(path: path2, line: 1, column: 4),
                                text: "let"
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    @Test
    func testNoteInDifferentFile() throws {
        try testAPI2Files { path1, path2 in
            .init(
                edits: (
                    .init(input: "var x = 1", result: "let x = 1"),
                    .init(input: "var x = 1", result: "var x = 1")
                ),
                summary: .init(numberOfFixItsApplied: 1, numberOfFilesChanged: 1),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error",
                        location: .init(path: path2, line: 1, column: 1),
                        notes: [
                            Note(
                                text: "note",
                                location: .init(path: path1, line: 1, column: 1),
                                fixIts: [
                                    .init(
                                        start: .init(path: path1, line: 1, column: 1),
                                        end: .init(path: path1, line: 1, column: 4),
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

    @Test
    func testDiagNotInTheSameFileAsFixIt() {
        #expect(throws: Error.self) {
            try testAPI2Files { path1, path2 in
                .init(
                    edits: (
                        .init(input: "var x = 1", result: "let x = 1"),
                        .init(input: "", result: "")
                    ),
                    summary: .init(numberOfFixItsApplied: 1, numberOfFilesChanged: 1),
                    diagnostics: [
                        PrimaryDiagnostic(
                            level: .error,
                            text: "error",
                            location: .init(path: path2, line: 1, column: 1),
                            fixIts: [
                                .init(
                                    start: .init(path: path1, line: 1, column: 1),
                                    end: .init(path: path1, line: 1, column: 4),
                                    text: "let"
                                ),
                            ]
                        ),
                    ]
                )
            }
        }
    }
}
