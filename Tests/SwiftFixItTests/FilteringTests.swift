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
    func testFixItIgnoredDiagnostic() throws {
        try testAPI1File { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "var x = 1"),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .ignored,
                        text: "error",
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        fixIts: [
                            // Ignore, diagnostic is ignored.
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

    func testFixItNoLocation() throws {
        try testAPI1File { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "var x = 1"),
                diagnostics: [
                    PrimaryDiagnostic(
                        level: .error,
                        text: "error",
                        location: nil,
                        fixIts: [
                            // Ignore, diagnostic without location.
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

    func testParallelFixIts1() throws {
        // First parallel fix-it is applied per emission order.
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
                                    // Applied.
                                    .init(
                                        start: .init(filename: filename, line: 1, column: 1, offset: 0),
                                        end: .init(filename: filename, line: 1, column: 4, offset: 0),
                                        text: "let"
                                    ),
                                ]
                            ),
                            Note(
                                text: "note",
                                location: .init(filename: filename, line: 1, column: 1, offset: 0),
                                fixIts: [
                                    // Ignored, parallel to previous fix-it.
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

    func testParallelFixIts2() throws {
        // First parallel fix-it is applied per emission order.
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
                                    // Applied.
                                    .init(
                                        start: .init(filename: filename, line: 1, column: 1, offset: 0),
                                        end: .init(filename: filename, line: 1, column: 4, offset: 0),
                                        text: "let"
                                    ),
                                ]
                            ),
                            Note(
                                text: "note",
                                location: .init(filename: filename, line: 1, column: 1, offset: 0)
                            ),
                            Note(
                                text: "note",
                                location: .init(filename: filename, line: 1, column: 1, offset: 0),
                                fixIts: [
                                    // Ignored, parallel to previous fix-it.
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
