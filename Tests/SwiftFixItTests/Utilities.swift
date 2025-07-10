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
import struct Foundation.UUID
@testable
import SwiftFixIt
import class SwiftSyntax.SourceLocationConverter
import Testing
import struct TSCUtility.SerializedDiagnostics

struct SourceLocation: AnySourceLocation {
    var path: AbsolutePath
    var line: UInt64
    var column: UInt64
    var offset: UInt64

    var filename: String {
        self.path.pathString
    }

    init(path: AbsolutePath, line: UInt64, column: UInt64) {
        self.path = path
        self.line = line
        self.column = column
        self.offset = 0
    }

    fileprivate mutating func computeOffset(
        using converters: [AbsolutePath: SourceLocationConverter]
    ) {
        guard let converter = converters[self.path] else {
            return
        }
        self.offset = UInt64(converter.position(ofLine: Int(self.line), column: Int(self.column)).utf8Offset)
    }
}

struct FixIt: AnyFixIt {
    var start: SourceLocation
    var end: SourceLocation
    var text: String
}

private struct Diagnostic: AnyDiagnostic {
    var level: SerializedDiagnostics.Diagnostic.Level
    var text: String
    var location: SourceLocation?
    var category: String?
    var categoryURL: String?
    var flag: String?
    var ranges: [(SourceLocation, SourceLocation)]
    var fixIts: [FixIt]

    fileprivate func withSourceLocationOffsets(
        using converters: [AbsolutePath: SourceLocationConverter]
    ) -> Self {
        var copy = self

        copy.location?.computeOffset(using: converters)
        for i in self.ranges.indices {
            copy.ranges[i].0.computeOffset(using: converters)
            copy.ranges[i].1.computeOffset(using: converters)
        }
        for i in self.fixIts.indices {
            copy.fixIts[i].start.computeOffset(using: converters)
            copy.fixIts[i].end.computeOffset(using: converters)
        }

        return copy
    }
}

struct Note {
    fileprivate var diagnostic: Diagnostic

    init(
        text: String,
        location: SourceLocation?,
        category: String? = nil,
        categoryURL: String? = nil,
        flag: String? = nil,
        ranges: [(SourceLocation, SourceLocation)] = [],
        fixIts: [FixIt] = [],
    ) {
        self.diagnostic = .init(
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

    fileprivate var diagnostic: Diagnostic
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
        self.diagnostic = .init(
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

struct SourceFileEdit {
    let input: String
    let result: String
    fileprivate let locationInTest: Testing.SourceLocation

    init(
        input: String,
        result: String,
        locationInTest: Testing.SourceLocation = #_sourceLocation
    ) {
        self.input = input
        self.result = result
        self.locationInTest = locationInTest
    }
}

struct Summary {
    let summary: SwiftFixIt.Summary
    fileprivate let locationInTest: Testing.SourceLocation

    init(
        numberOfFixItsApplied: Int,
        numberOfFilesChanged: Int,
        locationInTest: Testing.SourceLocation = #_sourceLocation
    ) {
        self.summary = .init(numberOfFixItsApplied: numberOfFixItsApplied, numberOfFilesChanged: numberOfFilesChanged)
        self.locationInTest = locationInTest
    }
}

struct TestCase<T> {
    let edits: T
    let summary: Summary
    let diagnostics: [PrimaryDiagnostic]
}

extension Testing.Issue {
    fileprivate static func record<T>(
        title: String,
        comparisonComponents components: T...,
        sourceLocation: Testing.SourceLocation
    ) {
        let messageDelimiter = "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        let componentSeparator = "────────────────────────────────────────────"

        var message = "\n\(messageDelimiter)\n\(title)\n\(messageDelimiter)\n"
        for component in components {
            message += "\(component)\n"
            break
        }
        for component in components.dropFirst() {
            message += "\(componentSeparator)\n\(component)\n"
        }
        message += messageDelimiter

        Issue.record(.init(rawValue: message), sourceLocation: sourceLocation)
    }
}

private func _testAPI(
    _ sourceFilePathsAndEdits: [(AbsolutePath, SourceFileEdit)],
    _ expectedSummary: Summary,
    _ diagnostics: [PrimaryDiagnostic],
    _ categories: Set<String>,
) throws {
    for (path, edit) in sourceFilePathsAndEdits {
        try localFileSystem.writeFileContents(path, string: edit.input)
    }

    let flatDiagnostics: [Diagnostic]
    do {
        let converters = Dictionary(uniqueKeysWithValues: sourceFilePathsAndEdits.map { path, edit in
            (path, SourceLocationConverter(file: path.pathString, source: edit.input))
        })

        flatDiagnostics = diagnostics.reduce(into: Array()) { partialResult, primaryDiagnostic in
            partialResult.append(primaryDiagnostic.diagnostic.withSourceLocationOffsets(using: converters))
            for note in primaryDiagnostic.notes {
                partialResult.append(note.diagnostic.withSourceLocationOffsets(using: converters))
            }
        }
    }

    let swiftFixIt = try SwiftFixIt(
        diagnostics: flatDiagnostics,
        categories: categories,
        excludedSourceDirectories: [],
        fileSystem: localFileSystem
    )
    let actualSummary = try swiftFixIt.applyFixIts()

    for (i, (path, edit)) in sourceFilePathsAndEdits.enumerated() {
        let actualContents = try localFileSystem.readFileContents(path) as String
        let expectedContents = edit.result
        let originalContents = edit.input

        if expectedContents != actualContents {
            Issue.record(
                title: "File #\(i + 1) (original/expected/actual contents)",
                comparisonComponents: originalContents, expectedContents, actualContents,
                sourceLocation: edit.locationInTest
            )
        }
    }

    if expectedSummary.summary != actualSummary {
        Issue.record(
            title: "Expected/actual change summaries",
            comparisonComponents: expectedSummary.summary, actualSummary,
            sourceLocation: expectedSummary.locationInTest
        )
    }
}

private func uniqueSwiftFileName() -> String {
    "\(UUID().uuidString).swift"
}

// Cannot use variadic generics: crashes.
func testAPI1File(
    categories: Set<String> = [],
    _ getTestCase: (AbsolutePath) -> TestCase<SourceFileEdit>
) throws {
    try testWithTemporaryDirectory { fixturePath in
        let sourceFilePath = fixturePath.appending(uniqueSwiftFileName())

        let testCase = getTestCase(sourceFilePath)

        try _testAPI(
            [(sourceFilePath, testCase.edits)],
            testCase.summary,
            testCase.diagnostics,
            categories
        )
    }
}

func testAPI2Files(
    categories: Set<String> = [],
    _ getTestCase: (AbsolutePath, AbsolutePath) -> TestCase<(SourceFileEdit, SourceFileEdit)>,
) throws {
    try testWithTemporaryDirectory { fixturePath in
        let sourceFilePath1 = fixturePath.appending(uniqueSwiftFileName())
        let sourceFilePath2 = fixturePath.appending(uniqueSwiftFileName())

        let testCase = getTestCase(sourceFilePath1, sourceFilePath2)

        try _testAPI(
            [(sourceFilePath1, testCase.edits.0), (sourceFilePath2, testCase.edits.1)],
            testCase.summary,
            testCase.diagnostics,
            categories
        )
    }
}
