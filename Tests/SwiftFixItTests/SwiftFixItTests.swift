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

import _InternalTestSupport
import struct Basics.AbsolutePath
import var Basics.localFileSystem
@testable
import SwiftFixIt
import struct TSCUtility.SerializedDiagnostics
import XCTest

final class SwiftFixItTests: XCTestCase {
    private struct TestDiagnostic: AnyDiagnostic {
        struct SourceLocation: AnySourceLocation {
            let filename: String
            let line: UInt64
            let column: UInt64
            let offset: UInt64
        }

        struct FixIt: AnyFixIt {
            let start: TestDiagnostic.SourceLocation
            let end: TestDiagnostic.SourceLocation
            let text: String
        }

        var text: String
        var level: SerializedDiagnostics.Diagnostic.Level
        var location: SourceLocation?
        var category: String?
        var categoryURL: String?
        var flag: String?
        var ranges: [(SourceLocation, SourceLocation)] = []
        var fixIts: [FixIt] = []
    }

    private struct SourceFileEdit {
        let input: String
        let result: String
    }

    private struct TestCase<T> {
        let edits: T
        let diagnostics: [TestDiagnostic]
    }

    private func _testAPI(
        _ sourceFilePathsAndEdits: [(AbsolutePath, SourceFileEdit)],
        _ diagnostics: [TestDiagnostic]
    ) throws {
        for (path, edit) in sourceFilePathsAndEdits {
            try localFileSystem.writeFileContents(path, string: edit.input)
        }

        let swiftFixIt = try SwiftFixIt(diagnostics: diagnostics, fileSystem: localFileSystem)
        try swiftFixIt.applyFixIts()

        for (path, edit) in sourceFilePathsAndEdits {
            try XCTAssertEqual(localFileSystem.readFileContents(path), edit.result)
        }
    }

    private func uniqueSwiftFileName() -> String {
        "\(UUID().uuidString).swift"
    }

    // Cannot use variadic generics: crashes.
    private func testAPI1File(
        _ getTestCase: (String) -> TestCase<SourceFileEdit>
    ) throws {
        try testWithTemporaryDirectory { fixturePath in
            let sourceFilePath = fixturePath.appending(self.uniqueSwiftFileName())

            let testCase = getTestCase(sourceFilePath.pathString)

            try self._testAPI(
                [(sourceFilePath, testCase.edits)],
                testCase.diagnostics
            )
        }
    }

    private func testAPI2Files(
        _ getTestCase: (String, String) -> TestCase<(SourceFileEdit, SourceFileEdit)>
    ) throws {
        try testWithTemporaryDirectory { fixturePath in
            let sourceFilePath1 = fixturePath.appending(self.uniqueSwiftFileName())
            let sourceFilePath2 = fixturePath.appending(self.uniqueSwiftFileName())

            let testCase = getTestCase(sourceFilePath1.pathString, sourceFilePath2.pathString)

            try self._testAPI(
                [(sourceFilePath1, testCase.edits.0), (sourceFilePath2, testCase.edits.1)],
                testCase.diagnostics
            )
        }
    }
}

extension SwiftFixItTests {
    func testFixIt() throws {
        try self.testAPI1File { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "let x = 1"),
                diagnostics: [
                    TestDiagnostic(
                        text: "error",
                        level: .error,
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

    func testFixItIgnoredDiagnostic() throws {
        try self.testAPI1File { (filename: String) in
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
        try self.testAPI1File { (filename: String) in
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

    func testNoteFixIt() throws {
        try self.testAPI1File { (filename: String) in
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

    func testNonParallelNoteFixIts() throws {
        try self.testAPI1File { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "let x = 22"),
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
                            .init(
                                start: .init(filename: filename, line: 1, column: 1, offset: 0),
                                end: .init(filename: filename, line: 1, column: 4, offset: 0),
                                text: "let"
                            ),
                        ]
                    ),
                    TestDiagnostic(
                        text: "error",
                        level: .error,
                        location: .init(filename: filename, line: 1, column: 1, offset: 0)
                    ),
                    // Make sure we apply this fix-it.
                    TestDiagnostic(
                        text: "note",
                        level: .note,
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        fixIts: [
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

    func testFixItsOnDifferentLines() throws {
        try self.testAPI1File { (filename: String) in
            .init(
                edits: .init(
                    input: """
                    var x = 1
                    var y = 2
                    var z = 3
                    """,
                    result: """
                    let x = 1
                    var y = 244
                    z = 3
                    """
                ),
                diagnostics: [
                    TestDiagnostic(
                        text: "error",
                        level: .error,
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
                ]
            )
        }
    }

    func testNonOverlappingFixItsOnSameLine() throws {
        try self.testAPI1File { (filename: String) in
            .init(
                edits: .init(input: "var x = foo(1, 2)", result: "x = fooo(1, 233)"),
                diagnostics: [
                    TestDiagnostic(
                        text: "error",
                        level: .error,
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        fixIts: [
                            // Replacement.
                            .init(
                                start: .init(filename: filename, line: 1, column: 9, offset: 0),
                                end: .init(filename: filename, line: 1, column: 12, offset: 0),
                                text: "fooo"
                            ),
                            // Addition.
                            .init(
                                start: .init(filename: filename, line: 1, column: 17, offset: 0),
                                end: .init(filename: filename, line: 1, column: 17, offset: 0),
                                text: "33"
                            ),
                            // Deletion.
                            .init(
                                start: .init(filename: filename, line: 1, column: 1, offset: 0),
                                end: .init(filename: filename, line: 1, column: 5, offset: 0),
                                text: ""
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    func testOverlappingFixItsSingleDiagnostic() throws {
        try self.testAPI1File { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "_ = 1"),
                diagnostics: [
                    TestDiagnostic(
                        text: "error",
                        level: .error,
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        fixIts: [
                            // Applied.
                            .init(
                                start: .init(filename: filename, line: 1, column: 1, offset: 0),
                                end: .init(filename: filename, line: 1, column: 6, offset: 0),
                                text: "_"
                            ),
                            // Ignored, overlaps with previous fix-it.
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

    func testOverlappingFixItsDifferentDiagnostics() throws {
        try self.testAPI1File { (filename: String) in
            .init(
                edits: .init(input: "var x = 1", result: "_ = 1"),
                diagnostics: [
                    TestDiagnostic(
                        text: "error",
                        level: .error,
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
                    TestDiagnostic(
                        text: "error",
                        level: .error,
                        location: .init(filename: filename, line: 1, column: 1, offset: 0),
                        fixIts: [
                            // Ignored, overlaps with previous fix-it.
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
        try self.testAPI1File { (filename: String) in
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
        try self.testAPI1File { (filename: String) in
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

    func testFixItsMultipleFiles() throws {
        try self.testAPI2Files { (filename1: String, filename2: String) in
            .init(
                edits: (
                    .init(input: "var x = 1", result: "let x = 1"),
                    .init(input: "var x = 1", result: "let x = 1")
                ),
                diagnostics: [
                    // filename1
                    TestDiagnostic(
                        text: "warning",
                        level: .warning,
                        location: .init(filename: filename1, line: 1, column: 1, offset: 0),
                        fixIts: [
                            .init(
                                start: .init(filename: filename1, line: 1, column: 1, offset: 0),
                                end: .init(filename: filename1, line: 1, column: 4, offset: 0),
                                text: "let"
                            ),
                        ]
                    ),
                    TestDiagnostic(
                        text: "error",
                        level: .error,
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
                    TestDiagnostic(
                        text: "warning",
                        level: .warning,
                        location: .init(filename: filename2, line: 1, column: 1, offset: 0),
                        fixIts: [
                            .init(
                                start: .init(filename: filename2, line: 1, column: 1, offset: 0),
                                end: .init(filename: filename2, line: 1, column: 4, offset: 0),
                                text: "let"
                            ),
                        ]
                    ),
                    TestDiagnostic(
                        text: "error",
                        level: .error,
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

    func testFixItNoteInDifferentFile() throws {
        try self.testAPI2Files { (filename1: String, filename2: String) in
            .init(
                edits: (
                    .init(input: "var x = 1", result: "let x = 1"),
                    .init(input: "var x = 1", result: "var x = 1")
                ),
                diagnostics: [
                    TestDiagnostic(
                        text: "error",
                        level: .error,
                        location: .init(filename: filename2, line: 1, column: 1, offset: 0)
                    ),
                    TestDiagnostic(
                        text: "note",
                        level: .note,
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
            )
        }
    }

    func testFixItInDifferentFile() throws {
        XCTExpectFailure()

        // Apply a fix-it in a different file.
        try self.testAPI2Files { (filename1: String, filename2: String) in
            .init(
                edits: (
                    .init(input: "var x = 1", result: "let x = 1"),
                    .init(input: "", result: "")
                ),
                diagnostics: [
                    TestDiagnostic(
                        text: "error",
                        level: .error,
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
    }
}
