/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Foundation
import TSCBasic
import TSCUtility

final class SerializedDiagnosticsTests: XCTestCase {
  func testReadSwiftSerializedDiags() throws {
    let serializedDiagnosticsPath = AbsolutePath(#file).parentDirectory
        .appending(components: "Inputs", "serialized.dia")
    let contents = try localFileSystem.readFileContents(serializedDiagnosticsPath)
    let serializedDiags = try SerializedDiagnostics(data: Data(contents.contents))

    XCTAssertEqual(serializedDiags.versionNumber, 1)
    XCTAssertEqual(serializedDiags.diagnostics.count, 17)

    let one = serializedDiags.diagnostics[5]
    XCTAssertEqual(one.text, "expected ',' separator")
    XCTAssertEqual(one.level, .error)
    XCTAssertTrue(one.location.filename.hasSuffix("/StoreSearchCoordinator.swift"))
    XCTAssertEqual(one.location.line, 21)
    XCTAssertEqual(one.location.column, 69)
    XCTAssertEqual(one.location.offset, 0)
    XCTAssertNil(one.category)
    XCTAssertNil(one.flag)
    XCTAssertEqual(one.ranges.count, 0)
    XCTAssertEqual(one.fixIts.count, 1)
    XCTAssertEqual(one.fixIts[0].text, ",")
    XCTAssertEqual(one.fixIts[0].start, one.fixIts[0].end)
    XCTAssertTrue(one.fixIts[0].start.filename.hasSuffix("/StoreSearchCoordinator.swift"))
    XCTAssertEqual(one.fixIts[0].start.line, 21)
    XCTAssertEqual(one.fixIts[0].start.column, 69)
    XCTAssertEqual(one.fixIts[0].start.offset, 0)

    let two = serializedDiags.diagnostics[16]
    XCTAssertEqual(two.text, "use of unresolved identifier 'DispatchQueue'")
    XCTAssertEqual(two.level, .error)
    XCTAssertTrue(two.location.filename.hasSuffix("/Observable.swift"))
    XCTAssertEqual(two.location.line, 34)
    XCTAssertEqual(two.location.column, 13)
    XCTAssertEqual(two.location.offset, 0)
    XCTAssertNil(two.category)
    XCTAssertNil(two.flag)
    XCTAssertEqual(two.ranges.count, 1)
    XCTAssertTrue(two.ranges[0].0.filename.hasSuffix("/Observable.swift"))
    XCTAssertEqual(two.ranges[0].0.line, 34)
    XCTAssertEqual(two.ranges[0].0.column, 13)
    XCTAssertEqual(two.ranges[0].0.offset, 0)
    XCTAssertTrue(two.ranges[0].1.filename.hasSuffix("/Observable.swift"))
    XCTAssertEqual(two.ranges[0].1.line, 34)
    XCTAssertEqual(two.ranges[0].1.column, 26)
    XCTAssertEqual(two.ranges[0].1.offset, 0)
    XCTAssertEqual(two.fixIts.count, 0)
  }

  func testReadClangSerializedDiags() throws {
    let serializedDiagnosticsPath = AbsolutePath(#file).parentDirectory
        .appending(components: "Inputs", "clang.dia")
    let contents = try localFileSystem.readFileContents(serializedDiagnosticsPath)
    let serializedDiags = try SerializedDiagnostics(data: Data(contents.contents))

    XCTAssertEqual(serializedDiags.versionNumber, 1)
    XCTAssertEqual(serializedDiags.diagnostics.count, 4)

    let one = serializedDiags.diagnostics[1]
    XCTAssertEqual(one.text, "values of type 'NSInteger' should not be used as format arguments; add an explicit cast to 'long' instead")
    XCTAssertEqual(one.level, .warning)
    XCTAssertEqual(one.location.line, 252)
    XCTAssertEqual(one.location.column, 137)
    XCTAssertEqual(one.location.offset, 10046)
    XCTAssertEqual(one.category, "Format String Issue")
    XCTAssertEqual(one.flag, "format")
    XCTAssertEqual(one.ranges.count, 4)
    XCTAssertEqual(one.fixIts.count, 2)
  }
}
