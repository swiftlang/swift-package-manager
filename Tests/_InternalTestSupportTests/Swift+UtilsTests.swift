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

import func _InternalTestSupport._getDiff
import Testing


struct GetDiffTestData: CustomTestArgumentEncodable {
    func encodeTestArgument(to encoder: some Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(original)
        try container.encode(modified)
        try container.encode(expected)
        try container.encode(id)
    }

    let original: String
    let modified: String
    let expected: String
    let id: String
}

extension GetDiffTestData: CustomTestStringConvertible {
    var testDescription: String { id }
}


@Suite(
    .tags(
        .TestSize.small,
    ),
)
struct StringUtilsTests {

    @Test(
        arguments: [
            GetDiffTestData(
                original: "",
                modified: "",
                expected: "  ",
                id: "two empty strings produce a single unchanged empty line",
            ),
            GetDiffTestData(
                original: "hello",
                modified: "hello",
                expected: "  hello",
                id: "identical single-line strings produce a single unchanged line",
            ),
            GetDiffTestData(
                original: "a\nb\nc",
                modified: "a\nb\nc",
                expected: "  a\n  b\n  c",
                id: "identical multi-line strings produce all unchanged lines",
            ),
            GetDiffTestData(
                original: "a\nb",
                modified: "a\nb\nc",
                expected: "  a\n  b\n+ c",
                id: "line appended at end is marked as inserted",
            ),
            GetDiffTestData(
                original: "b",
                modified: "a\nb",
                expected: "+ a\n  b",
                id: "line prepended at start is marked as inserted",
            ),
            GetDiffTestData(
                original: "a\nb\nc",
                modified: "a\nc",
                expected: "  a\n- b\n  c",
                id: "line removed from middle is marked as removed",
            ),
            GetDiffTestData(
                original: "a\nb\nc",
                modified: "a\nB\nc",
                expected: "  a\n- b\n+ B\n  c",
                id: "line replaced in middle produces removal then insertion",
            ),
            GetDiffTestData(
                original: "abc",
                modified: "xyz",
                expected: "- abc\n+ xyz",
                id: "completely different single-line strings produce removal then insertion",
            ),
            GetDiffTestData(
                original: "",
                modified: "hello",
                expected: "- \n+ hello",
                id: "empty original to non-empty modified removes empty and inserts content",
            ),
            GetDiffTestData(
                original: "hello",
                modified: "",
                expected: "- hello\n+ ",
                id: "non-empty original to empty modified removes content and inserts empty",
            ),
            GetDiffTestData(
                original: "a\nb",
                modified: "a\n\nb",
                expected: "  a\n+ \n  b",
                id: "blank line inserted between existing lines is marked as inserted",
            ),
            GetDiffTestData(
                original: "a\nb\n",
                modified: "a\nb\n",
                expected: "  a\n  b\n  ",
                id: "identical strings with trailing newline preserve the empty trailing line",
            ),
            GetDiffTestData(
                original: "a",
                modified: "a\nb\nc",
                expected: "  a\n+ b\n+ c",
                id: "multiple consecutive lines appended at end are each marked as inserted",
            ),
            GetDiffTestData(
                original: "c",
                modified: "a\nb\nc",
                expected: "+ a\n+ b\n  c",
                id: "multiple consecutive lines prepended at start are each marked as inserted",
            ),
            GetDiffTestData(
                original: "a\nb\nc\nd",
                modified: "a\nd",
                expected: "  a\n- b\n- c\n  d",
                id: "multiple consecutive lines removed from middle are each marked as removed",
            ),
            GetDiffTestData(
                original: "a\nb\nc",
                modified: "c",
                expected: "- a\n- b\n  c",
                id: "multiple consecutive lines removed from start are each marked as removed",
            ),
            GetDiffTestData(
                original: "a\nb\nc",
                modified: "a",
                expected: "  a\n- b\n- c",
                id: "multiple consecutive lines removed from end are each marked as removed",
            ),
            GetDiffTestData(
                original: "a\nb",
                modified: "a\nb\n",
                expected: "  a\n  b\n+ ",
                id: "adding a trailing newline appears as an inserted empty line",
            ),
            GetDiffTestData(
                original: "a\nb\n",
                modified: "a\nb",
                expected: "  a\n  b\n- ",
                id: "removing a trailing newline appears as a removed empty line",
            ),
            GetDiffTestData(
                original: "a\n\nb",
                modified: "a\nb",
                expected: "  a\n- \n  b",
                id: "blank line removed from between existing lines is marked as removed",
            ),
            GetDiffTestData(
                original: "a\nb\nc\nd",
                modified: "a\nx\nc\ny\nd",
                expected: "  a\n- b\n+ x\n  c\n+ y\n  d",
                id: "interleaved insertions and removals preserve unchanged anchor lines",
            ),
            GetDiffTestData(
                original: "a\nb\nc",
                modified: "x\ny\nz",
                expected: "- a\n- b\n- c\n+ x\n+ y\n+ z",
                id: "completely different multi-line strings produce all removals then all insertions",
            ),
            GetDiffTestData(
                original: "a\nb\nc",
                modified: "",
                expected: "- a\n- b\n- c\n+ ",
                id: "multi-line original to empty modified removes every line and inserts empty",
            ),
        ]
    )
    func getDiffReturnsExpectedOutput(
        data: GetDiffTestData,
    ) {
        let actual = _getDiff(data.original, with: data.modified)

        #expect(actual == data.expected)
    }
}
