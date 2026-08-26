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
import struct _InternalTestSupport.XUnitXMLHelpers

#if canImport(FoundationXML)
import FoundationXML
#endif


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

        try XUnitXMLMerger.merge(
            sources: [
                .init(path: a, package: nil),
                .init(path: b, package: nil),
            ],
            into: dest,
            fileSystem: fs,
        )

        let merged: String = try fs.readFileContents(dest)
        let (_, suites) = try XUnitXMLHelpers.parseTestsuites(merged)
        #expect(suites.count == 2, "expected 2 <testsuite> elements in merged output, got \(suites.count)")
        #expect(XUnitXMLHelpers.testsuiteName(suites[0]) == "TestResultsSampleA")
        #expect(XUnitXMLHelpers.testsuiteName(suites[1]) == "TestResultsSampleB")

        let sampleATestcases = suites[0].elements(forName: "testcase")
            .compactMap { $0.attribute(forName: "name")?.stringValue }
        #expect(sampleATestcases == ["testA", "testB"])

        let sampleBTestcases = suites[1].elements(forName: "testcase")
            .compactMap { $0.attribute(forName: "name")?.stringValue }
        #expect(sampleBTestcases == ["testC"])

        let failures = suites[1].elements(forName: "testcase")
            .flatMap { $0.elements(forName: "failure") }
        #expect(failures.first?.attribute(forName: "message")?.stringValue == "boom")
    }

    @Test
    func mergesSingleSource() throws {
        let fs = InMemoryFileSystem()
        let a = AbsolutePath("/a.xml")
        let dest = AbsolutePath("/merged.xml")
        try fs.writeFileContents(a, string: sampleA)

        try XUnitXMLMerger.merge(
            sources: [
                .init(path: a, package: nil),
            ],
            into: dest,
            fileSystem: fs,
        )

        let merged: String = try fs.readFileContents(dest)
        let (_, suites) = try XUnitXMLHelpers.parseTestsuites(merged)
        #expect(suites.count == 1)
        #expect(XUnitXMLHelpers.testsuiteName(suites[0]) == "TestResultsSampleA")

        let testcaseNames = suites[0].elements(forName: "testcase")
            .compactMap { $0.attribute(forName: "name")?.stringValue }
        #expect(testcaseNames == ["testA", "testB"])
    }

    @Test
    func mergingWithNoSourcesProducesEmptyTestsuites() throws {
        let fs = InMemoryFileSystem()
        let dest = AbsolutePath("/merged.xml")

        try XUnitXMLMerger.merge(sources: [], into: dest, fileSystem: fs)

        let merged: String = try fs.readFileContents(dest)
        let (rootOptional, suites) = try XUnitXMLHelpers.parseTestsuites(merged)
        let root = try #require(
            rootOptional,
            "Root element must not be nil",
        )
        let rootName = try #require(
            root.name,
            "Root element name is not set.  XML contents:\n\(merged)"
        )
        #expect(rootName == "testsuites")
        #expect(suites.isEmpty)
    }

    @Test
    func skipsMissingSourceFiles() throws {
        let fs = InMemoryFileSystem()
        let present = AbsolutePath("/present.xml")
        let missing = AbsolutePath("/missing.xml")
        let dest = AbsolutePath("/merged.xml")
        try fs.writeFileContents(present, string: sampleA)

        try XUnitXMLMerger.merge(
            sources: [
                .init(path: missing, package: nil),
                .init(path: present, package: nil),
            ],
            into: dest,
            fileSystem: fs,
        )

        let merged: String = try fs.readFileContents(dest)
        let (_, suites) = try XUnitXMLHelpers.parseTestsuites(merged)
        #expect(suites.count == 1)
        #expect(XUnitXMLHelpers.testsuiteName(suites[0]) == "TestResultsSampleA")
    }

    @Test
    func preservesEmptyTestsuiteMetadata() throws {
        let fs = InMemoryFileSystem()
        let a = AbsolutePath("/empty.xml")
        let dest = AbsolutePath("/merged.xml")
        try fs.writeFileContents(a, string: emptyResult)

        try XUnitXMLMerger.merge(
            sources: [
                .init(path: a, package: nil),
            ],
            into: dest,
            fileSystem: fs,
        )

        let merged: String = try fs.readFileContents(dest)
        let (_, suites) = try XUnitXMLHelpers.parseTestsuites(merged)
        #expect(suites.count == 1, "empty testsuite should still be preserved for accurate reporting")
        let suite = suites[0]
        #expect(XUnitXMLHelpers.testsuiteName(suite) == "TestResultsEmpty")
        #expect(suite.attribute(forName: "errors")?.stringValue == "1")
        #expect(suite.attribute(forName: "tests")?.stringValue == "10")
        #expect(suite.attribute(forName: "failures")?.stringValue == "4")
        #expect(suite.attribute(forName: "skipped")?.stringValue == "5")
        #expect(suite.attribute(forName: "time")?.stringValue == "0.000279")
    }

    @Test
    func doesNotEmitDuplicateXMLHeader() throws {
        let fs = InMemoryFileSystem()
        let a = AbsolutePath("/a.xml")
        let b = AbsolutePath("/b.xml")
        let dest = AbsolutePath("/merged.xml")
        try fs.writeFileContents(a, string: sampleA)
        try fs.writeFileContents(b, string: sampleB)

        try XUnitXMLMerger.merge(
            sources: [
                .init(path: a, package: nil),
                .init(path: b, package: nil),
            ],
            into: dest,
            fileSystem: fs,
        )

        let merged: String = try fs.readFileContents(dest)
        let headerCount = merged.components(separatedBy: "<?xml").count - 1
        #expect(headerCount == 1)
    }

    @Test
    func annotatesTestsuitesWithPackagePropertyWhenSourceHasPackageIdentity() throws {
        // Two sources, each attributed to a different workspace member.
        // Every `<testsuite>` from a given source must carry a child
        // `<properties><property name="package" value="<identity>"/></properties>`
        // in the merged output (per SE proposal for workspace `swift test`).
        let fs = InMemoryFileSystem()
        let a = AbsolutePath("/a.xml")
        let b = AbsolutePath("/b.xml")
        let dest = AbsolutePath("/merged.xml")
        try fs.writeFileContents(a, string: sampleA)
        try fs.writeFileContents(b, string: sampleB)

        try XUnitXMLMerger.merge(
            sources: [
                .init(path: a, package: "lib-a"),
                .init(path: b, package: "lib-b"),
            ],
            into: dest,
            fileSystem: fs,
        )

        let merged: String = try fs.readFileContents(dest)
        let (_, suites) = try XUnitXMLHelpers.parseTestsuites(merged)
        try #require(suites.count == 2)
        #expect(XUnitXMLHelpers.testsuiteName(suites[0]) == "TestResultsSampleA")
        #expect(XUnitXMLHelpers.testsuiteName(suites[1]) == "TestResultsSampleB")
        #expect(XUnitXMLHelpers.packagePropertyValue(in: suites[0]) == "lib-a")
        #expect(XUnitXMLHelpers.packagePropertyValue(in: suites[1]) == "lib-b")
    }

    @Test
    func doesNotAddPackagePropertyWhenSourceIsUnannotated() throws {
        // Back-compat: single-package (non-workspace) runs should still
        // produce `<testsuite>` elements with no `package` property.
        let fs = InMemoryFileSystem()
        let a = AbsolutePath("/a.xml")
        let dest = AbsolutePath("/merged.xml")
        try fs.writeFileContents(a, string: sampleA)

        try XUnitXMLMerger.merge(
            sources: [
                .init(path: a, package: nil),
            ],
            into: dest,
            fileSystem: fs,
        )

        let merged: String = try fs.readFileContents(dest)
        let (_, suites) = try XUnitXMLHelpers.parseTestsuites(merged)
        try #require(suites.count == 1)
        #expect(XUnitXMLHelpers.packagePropertyValue(in: suites[0]) == nil)
    }

    struct MergeSourcesReturnsExpectedxUnitContentsTestData: CustomTestStringConvertible {
        let contents: [String]
        let expected: String
        let id: String

        var testDescription: String { id }
    }
    @Test(
        arguments: [
            MergeSourcesReturnsExpectedxUnitContentsTestData(
                contents: [],
                expected: """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <testsuites>
                    </testsuites>

                    """,
                    id: "No inputs",
            ),
            MergeSourcesReturnsExpectedxUnitContentsTestData(
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
            MergeSourcesReturnsExpectedxUnitContentsTestData(
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
            MergeSourcesReturnsExpectedxUnitContentsTestData(
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
            MergeSourcesReturnsExpectedxUnitContentsTestData(
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
            MergeSourcesReturnsExpectedxUnitContentsTestData(
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
        data: MergeSourcesReturnsExpectedxUnitContentsTestData,
    ) async throws {

        func canonicalizeXML(_ xml: String) throws -> String {
            let document = try XMLDocument(xmlString: xml, options: [])
            guard let root = document.rootElement() else { return "" }
            return canonicalizeElement(root)
        }

        func canonicalizeElement(_ element: XMLElement) -> String {
            let name = element.name ?? ""
            let attributes = (element.attributes ?? [])
                .compactMap { attribute -> String? in
                    guard let attributeName = attribute.name else { return nil }
                    let value = (attribute.stringValue ?? "")
                        .replacingOccurrences(of: "&", with: "&amp;")
                        .replacingOccurrences(of: "<", with: "&lt;")
                        .replacingOccurrences(of: "\"", with: "&quot;")
                    return "\(attributeName)=\"\(value)\""
                }
                .sorted()
                .joined(separator: " ")
            let attributesPart = attributes.isEmpty ? "" : " \(attributes)"

            let children = (element.children ?? []).compactMap { node -> String? in
                if let childElement = node as? XMLElement {
                    return canonicalizeElement(childElement)
                }
                if node.kind == .text {
                    let text = (node.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return text.isEmpty ? nil : text
                }
                return nil
            }.joined()

            if children.isEmpty {
                return "<\(name)\(attributesPart)/>"
            }
            return "<\(name)\(attributesPart)>\(children)</\(name)>"
        }

        let fs = InMemoryFileSystem()
        var inputs = [XUnitXMLMerger.Source]()
        // GIVEN we have a few xUnit XML contents
        for (index, value) in data.contents.enumerated() {
            let filename = AbsolutePath("/input_\(index).xml")
            try fs.writeFileContents(filename, string: value)
            inputs.append(.init(path: filename, package: nil))
        }

        let output = AbsolutePath("/merged.xml")
        // WHEN we merge them together
        try XUnitXMLMerger.merge(sources: inputs, into: output, fileSystem: fs)
        // AND we read the merged XML contents
        let actual: String = try fs.readFileContents(output)

        // THEN we expect the contents to be semantically equal to what we expect
        let actualCanonical = try canonicalizeXML(actual)
        let expectedCanonical = try canonicalizeXML(data.expected)
        #expect(
            actualCanonical == expectedCanonical,
            "actual is not semantically equal to expected. id: \(data.id)\nactual canonical:   \(actualCanonical)\nexpected canonical: \(expectedCanonical)",
        )

    }

}
