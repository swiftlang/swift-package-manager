//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@testable import Commands

import Basics
import Foundation
import Testing

@Suite(
    .tags(
        Tag.TestSize.small,
    )
)
struct EventStreamMergerTests {
    private let sampleA = """
        {"kind":"test","payload":{"id":"ATests.testA"}}
        {"kind":"event","payload":{"kind":"testStarted","testID":"ATests.testA"}}
        """

    private let sampleB = """
        {"kind":"test","payload":{"id":"BTests.testB"}}
        {"kind":"event","payload":{"kind":"testStarted","testID":"BTests.testB"}}
        """

    @Test
    func mergesTwoSourcesPreservingEveryRecord() throws {
        let fs = InMemoryFileSystem()
        let a = AbsolutePath("/a.jsonl")
        let b = AbsolutePath("/b.jsonl")
        let dest = AbsolutePath("/merged.jsonl")
        try fs.writeFileContents(a, string: sampleA + "\n")
        try fs.writeFileContents(b, string: sampleB + "\n")

        try EventStreamMerger.merge(sources: [a, b], into: dest, fileSystem: fs)

        let merged: String = try fs.readFileContents(dest)
        let lines = merged.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(lines.count == 4, "every record from both sources must survive; got:\n\(merged)")
        #expect(lines[0].contains("ATests.testA"))
        #expect(lines[1].contains("testStarted"))
        #expect(lines[2].contains("BTests.testB"))
        #expect(merged.contains("ATests.testA"))
        #expect(merged.contains("BTests.testB"))
    }

    @Test
    func mergesSingleSourceUnchanged() throws {
        let fs = InMemoryFileSystem()
        let a = AbsolutePath("/a.jsonl")
        let dest = AbsolutePath("/merged.jsonl")
        try fs.writeFileContents(a, string: sampleA + "\n")

        try EventStreamMerger.merge(sources: [a], into: dest, fileSystem: fs)

        let merged: String = try fs.readFileContents(dest)
        let lines = merged.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(lines.count == 2)
        #expect(merged.hasSuffix("\n"), "JSON Lines output must be newline-terminated")
    }

    @Test
    func skipsMissingSourceFiles() throws {
        let fs = InMemoryFileSystem()
        let present = AbsolutePath("/present.jsonl")
        let missing = AbsolutePath("/missing.jsonl")
        let dest = AbsolutePath("/merged.jsonl")
        try fs.writeFileContents(present, string: sampleA + "\n")

        try EventStreamMerger.merge(sources: [missing, present], into: dest, fileSystem: fs)

        let merged: String = try fs.readFileContents(dest)
        let lines = merged.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(lines.count == 2)
        #expect(merged.contains("ATests.testA"))
    }

    @Test
    func mergingWithNoSourcesProducesEmptyFile() throws {
        let fs = InMemoryFileSystem()
        let dest = AbsolutePath("/merged.jsonl")

        try EventStreamMerger.merge(sources: [], into: dest, fileSystem: fs)

        let merged: String = try fs.readFileContents(dest)
        #expect(merged.isEmpty)
    }

    @Test
    func ignoresBlankLinesBetweenRecords() throws {
        let fs = InMemoryFileSystem()
        let a = AbsolutePath("/a.jsonl")
        let dest = AbsolutePath("/merged.jsonl")
        try fs.writeFileContents(a, string: "\n\(sampleA)\n\n")

        try EventStreamMerger.merge(sources: [a], into: dest, fileSystem: fs)

        let merged: String = try fs.readFileContents(dest)
        let lines = merged.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(lines.count == 2, "blank lines are not records and must be dropped; got:\n\(merged)")
    }
}
