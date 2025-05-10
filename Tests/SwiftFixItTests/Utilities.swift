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

struct TestDiagnostic: AnyDiagnostic {
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

struct SourceFileEdit {
    let input: String
    let result: String
}

struct TestCase<T> {
    let edits: T
    let diagnostics: [TestDiagnostic]
}

private func _testAPI(
    _ sourceFilePathsAndEdits: [(AbsolutePath, SourceFileEdit)],
    _ diagnostics: [TestDiagnostic],
    _ categories: Set<String>,
) throws {
    for (path, edit) in sourceFilePathsAndEdits {
        try localFileSystem.writeFileContents(path, string: edit.input)
    }

    let swiftFixIt = try SwiftFixIt(
        diagnostics: diagnostics,
        categories: categories,
        fileSystem: localFileSystem
    )
    try swiftFixIt.applyFixIts()

    for (path, edit) in sourceFilePathsAndEdits {
        try XCTAssertEqual(localFileSystem.readFileContents(path), edit.result)
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
