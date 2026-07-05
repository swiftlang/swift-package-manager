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
import Testing

@Suite(
    .tags(
        Tag.TestSize.small,
    )
)
struct XUnitXMLMergerTests {
    private static let sampleA_testSuite = """
        <testsuite name="TestResultsSampleA" errors="0" tests="2" failures="0" skipped="0" time="1.0">
        <testcase classname="Foo" name="testA" time="0.5" />
        <testcase classname="Foo" name="testB" time="0.5" />
        </testsuite>
        """
    private let sampleA = """
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuites>
        \(Self.sampleA_testSuite)
        </testsuites>

        """

    private static let sampleB_testSuite = """
        <testsuite name="TestResultsSampleB" errors="0" tests="1" failures="1" skipped="0" time="0.3">
        <testcase classname="Bar" name="testC" time="0.3">
        <failure message="boom"></failure>
        </testcase>
        </testsuite>
        """
    private let sampleB = """
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuites>
        \(Self.sampleB_testSuite)
        </testsuites>

        """

    private static let emptyResult_testSuite = """
        <testsuite name="TestResultsEmpty" errors="1" tests="10" failures="4" skipped="5" time="0.000279">

        </testsuite>
        """
    private let emptyResult = """
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuites>
        \(Self.emptyResult_testSuite)
        </testsuites>

        """

    @Test
    func mergesTwoSourcesPreservingBothTestsuites() throws {
        let fs = InMemoryFileSystem()
        let a = AbsolutePath("/a.xml")
        let b = AbsolutePath("/b.xml")
        let dest = AbsolutePath("/merged.xml")
        try fs.writeFileContents(a, string: sampleA)
        try fs.writeFileContents(b, string: sampleB)

        try XUnitXMLMerger.merge(sources: [a, b], into: dest, fileSystem: fs)

        let merged: String = try fs.readFileContents(dest)
        #expect(merged.contains("<?xml"))
        #expect(merged.contains("<testsuites>"))
        #expect(merged.contains("</testsuites>"))
        #expect(merged.contains(#"<testsuite name="TestResultsSampleA""#))
        #expect(merged.contains(#"<testsuite name="TestResultsSampleB""#))
        #expect(merged.contains(#"name="testA""#))
        #expect(merged.contains(#"name="testB""#))
        #expect(merged.contains(#"name="testC""#))
        #expect(merged.contains(#"<failure message="boom">"#))
        let testsuiteCount = merged.components(separatedBy: "<testsuite ").count - 1
        #expect(testsuiteCount == 2, "expected 2 <testsuite> elements in merged output, got \(testsuiteCount)")
    }

    @Test
    func mergesSingleSource() throws {
        let fs = InMemoryFileSystem()
        let a = AbsolutePath("/a.xml")
        let dest = AbsolutePath("/merged.xml")
        try fs.writeFileContents(a, string: sampleA)

        try XUnitXMLMerger.merge(sources: [a], into: dest, fileSystem: fs)

        let merged: String = try fs.readFileContents(dest)
        #expect(merged.contains(#"<testsuite name="TestResultsSampleA""#))
        #expect(merged.contains(#"name="testA""#))
        #expect(merged.contains(#"name="testB""#))
        let testsuiteCount = merged.components(separatedBy: "<testsuite ").count - 1
        #expect(testsuiteCount == 1)
    }

    @Test
    func mergingWithNoSourcesProducesEmptyTestsuites() throws {
        let fs = InMemoryFileSystem()
        let dest = AbsolutePath("/merged.xml")

        try XUnitXMLMerger.merge(sources: [], into: dest, fileSystem: fs)

        let merged: String = try fs.readFileContents(dest)
        #expect(merged.contains("<testsuites>"))
        #expect(merged.contains("</testsuites>"))
        #expect(!merged.contains("<testsuite "))
    }

    @Test
    func skipsMissingSourceFiles() throws {
        let fs = InMemoryFileSystem()
        let present = AbsolutePath("/present.xml")
        let missing = AbsolutePath("/missing.xml")
        let dest = AbsolutePath("/merged.xml")
        try fs.writeFileContents(present, string: sampleA)

        try XUnitXMLMerger.merge(sources: [missing, present], into: dest, fileSystem: fs)

        let merged: String = try fs.readFileContents(dest)
        #expect(merged.contains(#"<testsuite name="TestResultsSampleA""#))
        #expect(merged.contains(#"name="testA""#))
        let testsuiteCount = merged.components(separatedBy: "<testsuite ").count - 1
        #expect(testsuiteCount == 1)
    }

    @Test
    func preservesEmptyTestsuiteMetadata() throws {
        let fs = InMemoryFileSystem()
        let a = AbsolutePath("/empty.xml")
        let dest = AbsolutePath("/merged.xml")
        try fs.writeFileContents(a, string: emptyResult)

        try XUnitXMLMerger.merge(sources: [a], into: dest, fileSystem: fs)

        let merged: String = try fs.readFileContents(dest)
        let testsuiteCount = merged.components(separatedBy: "<testsuite ").count - 1
        #expect(testsuiteCount == 1, "empty testsuite should still be preserved for accurate reporting")
        #expect(merged.contains(#"<testsuite name="TestResultsEmpty""#))
        #expect(merged.contains(#"errors="1""#))
        #expect(merged.contains(#"tests="10""#))
        #expect(merged.contains(#"failures="4""#))
        #expect(merged.contains(#"skipped="5""#))
        #expect(merged.contains(#"time="0.000279""#))
    }

    @Test
    func doesNotEmitDuplicateXMLHeader() throws {
        let fs = InMemoryFileSystem()
        let a = AbsolutePath("/a.xml")
        let b = AbsolutePath("/b.xml")
        let dest = AbsolutePath("/merged.xml")
        try fs.writeFileContents(a, string: sampleA)
        try fs.writeFileContents(b, string: sampleB)

        try XUnitXMLMerger.merge(sources: [a, b], into: dest, fileSystem: fs)

        let merged: String = try fs.readFileContents(dest)
        let headerCount = merged.components(separatedBy: "<?xml").count - 1
        #expect(headerCount == 1)
    }

    @Test(
        arguments: [
            (
                contents: [],
                expected: """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <testsuites>
                    </testsuites>

                    """,
                    id: "No inputs",
            ),
            (
                contents: [
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <testsuites>
                    </testsuites>

                    """,

                ],
                expected: """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <testsuites>
                    </testsuites>

                    """,
                id: "Single input without any <testsuite>",
            ),
            (
                contents: [
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <testsuites>
                    \(Self.sampleA_testSuite)
                    </testsuites>
                    """,
                ],
                expected: """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <testsuites>
                    \(Self.sampleA_testSuite)
                    </testsuites>

                    """,
                id: "Single input with a single <testsuite>",
            ),
            (
                contents: [
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <testsuites>
                    \(Self.sampleB_testSuite)
                    \(Self.sampleA_testSuite)
                    </testsuites>
                    """,

                ],
                expected: """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <testsuites>
                    \(Self.sampleB_testSuite)
                    \(Self.sampleA_testSuite)
                    </testsuites>

                    """,
                id: "Single input with a two <testsuite>",
            ),
            (
                contents: [
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <testsuites>
                    \(Self.sampleA_testSuite)
                    </testsuites>
                    """,
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <testsuites>
                    \(Self.sampleB_testSuite)
                    </testsuites>
                    """,

                ],
                expected: """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <testsuites>
                    \(Self.sampleA_testSuite)
                    \(Self.sampleB_testSuite)
                    </testsuites>

                    """,
                id: "Two inputs each with a single <testsuite>",
            ),
            (
                contents: [
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <testsuites>
                    \(Self.sampleA_testSuite)
                    </testsuites>

                    """,
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <testsuites>
                    \(Self.sampleB_testSuite)
                    </testsuites>

                    """,
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <testsuites>
                    \(Self.emptyResult_testSuite)
                    </testsuites>
                    """,

                ],
                expected: """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <testsuites>
                    \(Self.sampleA_testSuite)
                    \(Self.sampleB_testSuite)
                    \(Self.emptyResult_testSuite)
                    </testsuites>

                    """,
                id: "Multiple inputs each with a single <testsuite>",
            ),
        ],

    )
    func mergeSourcesReturnsExpectedxUnitContents(
        data: (contents: [String], expected: String, id: String),
    ) async throws {
        let fs = InMemoryFileSystem()
        var inputs = [AbsolutePath]()
        // GIVEN we have a few xUnit XML contents
        for (index, value) in data.contents.enumerated() {
            let filename = AbsolutePath("/input_\(index).xml")
            try fs.writeFileContents(filename, string: value)
            inputs.append(filename)
        }

        let output = AbsolutePath("/merged.xml")
        // WHEN we merge them together
        try XUnitXMLMerger.merge(sources: inputs, into: output, fileSystem: fs)
        // AND we read the merged XML contents
        let actual: String = try fs.readFileContents(output)

        // THEN we expect the contents to match what we expect
        #expect(
            actual == data.expected,
            "actual is not as expected. id: \(data.id)",
        )

    }

}
