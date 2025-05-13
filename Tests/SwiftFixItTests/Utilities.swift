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

struct SourceLocation: AnySourceLocation {
    let filename: String
    let line: UInt64
    let column: UInt64
    let offset: UInt64
}

struct FixIt: AnyFixIt {
    let start: SourceLocation
    let end: SourceLocation
    let text: String
}

private struct CommonDiagnosticData {
    let level: SerializedDiagnostics.Diagnostic.Level
    let text: String
    let location: SourceLocation?
    let category: String?
    let categoryURL: String?
    let flag: String?
    let ranges: [(SourceLocation, SourceLocation)]
    let fixIts: [FixIt]
}

struct Note {
    fileprivate let data: CommonDiagnosticData

    init(
        text: String,
        location: SourceLocation?,
        category: String? = nil,
        categoryURL: String? = nil,
        flag: String? = nil,
        ranges: [(SourceLocation, SourceLocation)] = [],
        fixIts: [FixIt] = [],
    ) {
        self.data = .init(
            level: .note,
            text: text,
            location: location,
            category: category,
            categoryURL: categoryURL,
            flag: flag,
            ranges: ranges,
            fixIts: fixIts,
        )
    }
}

struct PrimaryDiagnostic {
    enum Level {
        case ignored, warning, error, fatal, remark
    }

    fileprivate let data: CommonDiagnosticData
    let notes: [Note]

    init(
        level: Level,
        text: String,
        location: SourceLocation?,
        category: String? = nil,
        categoryURL: String? = nil,
        flag: String? = nil,
        ranges: [(SourceLocation, SourceLocation)] = [],
        fixIts: [FixIt] = [],
        notes: [Note] = [],
    ) {
        let level: SerializedDiagnostics.Diagnostic.Level = switch level {
        case .ignored: .ignored
        case .warning: .warning
        case .error: .error
        case .fatal: .fatal
        case .remark: .remark
        }
        self.data = .init(
            level: level,
            text: text,
            location: location,
            category: category,
            categoryURL: categoryURL,
            flag: flag,
            ranges: ranges,
            fixIts: fixIts,
        )
        self.notes = notes
    }
}

private struct _TestDiagnostic: AnyDiagnostic {
    let data: CommonDiagnosticData

    var level: SerializedDiagnostics.Diagnostic.Level {
        self.data.level
    }

    var text: String {
        self.data.text
    }

    var location: SourceLocation? {
        self.data.location
    }

    var category: String? {
        self.data.category
    }

    var categoryURL: String? {
        self.data.categoryURL
    }

    var flag: String? {
        self.data.flag
    }

    var ranges: [(SourceLocation, SourceLocation)] {
        self.data.ranges
    }

    var fixIts: [FixIt] {
        self.data.fixIts
    }

    init(note: Note) {
        self.data = note.data
    }

    init(primaryDiagnostic: PrimaryDiagnostic) {
        self.data = primaryDiagnostic.data
    }
}

struct SourceFileEdit {
    let input: String
    let result: String
}

struct TestCase<T> {
    let edits: T
    let diagnostics: [PrimaryDiagnostic]
}

private func _testAPI(
    _ sourceFilePathsAndEdits: [(AbsolutePath, SourceFileEdit)],
    _ diagnostics: [PrimaryDiagnostic],
    _ categories: Set<String>,
) throws {
    for (path, edit) in sourceFilePathsAndEdits {
        try localFileSystem.writeFileContents(path, string: edit.input)
    }

    var testDiagnostics: [_TestDiagnostic] = []
    for diagnostic in diagnostics {
        testDiagnostics.append(.init(primaryDiagnostic: diagnostic))
        for note in diagnostic.notes {
            testDiagnostics.append(.init(note: note))
        }
    }

    let swiftFixIt = try SwiftFixIt(
        diagnostics: testDiagnostics,
        categories: categories,
        fileSystem: localFileSystem
    )
    try swiftFixIt.applyFixIts()

    for (i, (path, edit)) in sourceFilePathsAndEdits.enumerated() {
        let actual = try localFileSystem.readFileContents(path) as String
        let expected = edit.result
        guard expected == actual else {
            XCTFail(
                """
                ===================================>
                File #\(i + 1) (expected/actual contents)
                ====================================
                \(expected)
                ====================================
                \(actual)
                <===================================
                """
            )

            continue
        }
    }
}

private func uniqueSwiftFileName() -> String {
    "\(UUID().uuidString).swift"
}

// Cannot use variadic generics: crashes.
func testAPI1File(
    categories: Set<String> = [],
    _ getTestCase: (String) -> TestCase<SourceFileEdit>
) throws {
    try testWithTemporaryDirectory { fixturePath in
        let sourceFilePath = fixturePath.appending(uniqueSwiftFileName())

        let testCase = getTestCase(sourceFilePath.pathString)

        try _testAPI(
            [(sourceFilePath, testCase.edits)],
            testCase.diagnostics,
            categories
        )
    }
}

func testAPI2Files(
    categories: Set<String> = [],
    _ getTestCase: (String, String) -> TestCase<(SourceFileEdit, SourceFileEdit)>,
) throws {
    try testWithTemporaryDirectory { fixturePath in
        let sourceFilePath1 = fixturePath.appending(uniqueSwiftFileName())
        let sourceFilePath2 = fixturePath.appending(uniqueSwiftFileName())

        let testCase = getTestCase(sourceFilePath1.pathString, sourceFilePath2.pathString)

        try _testAPI(
            [(sourceFilePath1, testCase.edits.0), (sourceFilePath2, testCase.edits.1)],
            testCase.diagnostics,
            categories
        )
    }
}
