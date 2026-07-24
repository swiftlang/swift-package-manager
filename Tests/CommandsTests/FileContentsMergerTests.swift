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

private let sampleA = """
    {"kind":"test","payload":{"id":"ATests.testA"}}
    {"kind":"event","payload":{"kind":"testStarted","testID":"ATests.testA"}}
    """

private let sampleB = """
    {"kind":"test","payload":{"id":"BTests.testB"}}
    {"kind":"event","payload":{"kind":"testStarted","testID":"BTests.testB"}}
    """

struct MergeScenario: Sendable, CustomTestStringConvertible {
    let name: String
    let sources: [String]
    let expectedLineCount: Int
    var testDescription: String { name }
}

@Suite(
    .tags(
        Tag.TestSize.small,
    )
)
struct FileContentsMergerTests {
    @Test
    func mergesTwoSourcesPreservingEveryRecord() throws {
        let fs = InMemoryFileSystem()
        let a = AbsolutePath("/a.jsonl")
        let b = AbsolutePath("/b.jsonl")
        let dest = AbsolutePath("/merged.jsonl")
        try fs.writeFileContents(a, string: sampleA + "\n")
        try fs.writeFileContents(b, string: sampleB + "\n")

        try FileContentsMerger.merge(sources: [a, b], into: dest, fileSystem: fs)

        let merged: String = try fs.readFileContents(dest)
        let lines = merged.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(lines.count == 4, "every record from both sources must survive; got:\n\(merged)")
        #expect(lines[0].contains("ATests.testA"))
        #expect(lines[1].contains("testStarted"))
        #expect(lines[2].contains("BTests.testB"))
        #expect(merged.contains("ATests.testA"))
        #expect(merged.contains("BTests.testB"))
        #expect(merged.contains(sampleA))
        #expect(merged.contains(sampleB))
    }

    @Test(arguments: [
        MergeScenario(name: "single source", sources: [sampleA + "\n"], expectedLineCount: 2),
        MergeScenario(name: "single source without trailing newline", sources: [sampleA], expectedLineCount: 2),
        MergeScenario(name: "single source with surrounding blank lines", sources: ["\n\(sampleA)\n\n"], expectedLineCount: 2),
        MergeScenario(name: "two sources", sources: [sampleA + "\n", sampleB + "\n"], expectedLineCount: 4),
        MergeScenario(name: "three sources", sources: [sampleA + "\n", sampleB + "\n", sampleA + "\n"], expectedLineCount: 6),
    ])
    func mergesSourcesWithExpectedLineCount(_ scenario: MergeScenario) throws {
        let fs = InMemoryFileSystem()
        let dest = AbsolutePath("/merged.jsonl")
        let sources = try scenario.sources.enumerated().map { index, contents -> AbsolutePath in
            let path = AbsolutePath("/source\(index).jsonl")
            try fs.writeFileContents(path, string: contents)
            return path
        }

        try FileContentsMerger.merge(sources: sources, into: dest, fileSystem: fs)

        let merged: String = try fs.readFileContents(dest)
        let lines = merged.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(lines.count == scenario.expectedLineCount, "unexpected line count; got:\n\(merged)")
        #expect(merged.hasSuffix("\n"), "JSON Lines output must be newline-terminated")
    }

    @Test
    func skipsMissingSourceFiles() throws {
        let fs = InMemoryFileSystem()
        let present = AbsolutePath("/present.jsonl")
        let missing = AbsolutePath("/missing.jsonl")
        let dest = AbsolutePath("/merged.jsonl")
        try fs.writeFileContents(present, string: sampleA + "\n")

        try FileContentsMerger.merge(sources: [missing, present], into: dest, fileSystem: fs)

        let merged: String = try fs.readFileContents(dest)
        let lines = merged.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(lines.count == 2)
        #expect(merged.contains("ATests.testA"))
    }

    @Test
    func mergingWithNoSourcesProducesEmptyFile() throws {
        let fs = InMemoryFileSystem()
        let dest = AbsolutePath("/merged.jsonl")

        try FileContentsMerger.merge(sources: [], into: dest, fileSystem: fs)

        let merged: String = try fs.readFileContents(dest)
        #expect(merged.isEmpty)
    }

    @Test
    func mergingEmptyFilesProducesEmptyFile() throws {
        let fs = InMemoryFileSystem()
        let a = AbsolutePath("/a.jsonl")
        let b = AbsolutePath("/b.jsonl")
        let dest = AbsolutePath("/merged.jsonl")
        try fs.writeFileContents(a, string: "")
        try fs.writeFileContents(b, string: "")

        try FileContentsMerger.merge(sources: [a, b], into: dest, fileSystem: fs)

        let merged: String = try fs.readFileContents(dest)
        #expect(merged.isEmpty)
    }

    @Test
    func ignoresBlankLinesBetweenRecords() throws {
        let fs = InMemoryFileSystem()
        let a = AbsolutePath("/a.jsonl")
        let dest = AbsolutePath("/merged.jsonl")
        try fs.writeFileContents(a, string: "\n\(sampleA)\n\n")

        try FileContentsMerger.merge(sources: [a], into: dest, fileSystem: fs)

        let merged: String = try fs.readFileContents(dest)
        let lines = merged.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(lines.count == 2, "blank lines are not records and must be dropped; got:\n\(merged)")
    }
}
