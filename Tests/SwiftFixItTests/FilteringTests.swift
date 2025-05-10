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
                    TestDiagnostic(
                        text: "error",
                        level: .ignored,
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
                    TestDiagnostic(
                        text: "error",
                        level: .error,
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
                    TestDiagnostic(
                        text: "error",
                        level: .error,
                        location: .init(filename: filename, line: 1, column: 1, offset: 0)
                    ),
                    TestDiagnostic(
                        text: "note",
                        level: .note,
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
                    TestDiagnostic(
                        text: "note",
                        level: .note,
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
            )
        }
    }

    func testParallelFixIts2() throws {
        // First parallel fix-it is applied per emission order.
        try testAPI1File { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "let x = 1"),
                diagnostics: [
                    TestDiagnostic(
                        text: "error",
                        level: .error,
                        location: .init(filename: filename, line: 1, column: 1, offset: 0)
                    ),
                    TestDiagnostic(
                        text: "note",
                        level: .note,
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
                    TestDiagnostic(
                        text: "note",
                        level: .note,
                        location: .init(filename: filename, line: 1, column: 1, offset: 0)
                    ),
                    TestDiagnostic(
                        text: "note",
                        level: .note,
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
            )
        }
    }
}
