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
import Dispatch
import Foundation
import PackageModel
import SPMBuildCore
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
struct XUnitGeneratorTests {
    /// Builds a `ParallelTestRunner.TestResult` with the fields the
    /// generator inspects. `packageIdentity` is propagated via the
    /// synthesized `BuiltTestProduct` so the generator can group and
    /// annotate suites by it.
    private static func makeResult(
        packageIdentity: PackageIdentity?,
        productName: String,
        testCase: String,
        testName: String,
        success: Bool = true,
        durationMs: Int = 100,
    ) -> ParallelTestRunner.TestResult {
        let product = BuiltTestProduct(
            productName: productName,
            umbrellaProductName: nil,
            binaryPath: AbsolutePath("/tmp/\(productName)"),
            packagePath: AbsolutePath("/tmp/\(productName)"),
            packageIdentity: packageIdentity,
            testEntryPointPath: nil,
        )
        let unitTest = UnitTest(testProduct: product, name: testName, testCase: testCase)
        return ParallelTestRunner.TestResult(
            unitTest: unitTest,
            output: "",
            success: success,
            duration: .milliseconds(durationMs),
        )
    }

    @Test
    func generate_singlePackageResults_annotatesTestsuiteWithPackageProperty() throws {
        let fs = InMemoryFileSystem()
        let dest = AbsolutePath("/out.xml")

        let generator = XUnitGenerator(
            fileSystem: fs,
            results: [
                Self.makeResult(
                    packageIdentity: .plain("myproject"),
                    productName: "MyProjectTests",
                    testCase: "MyProjectTests.FirstTests",
                    testName: "testOne",
                ),
                Self.makeResult(
                    packageIdentity: .plain("myproject"),
                    productName: "MyProjectTests",
                    testCase: "MyProjectTests.FirstTests",
                    testName: "testTwo",
                ),
            ],
        )
        try generator.generate(at: dest, detailedFailureMessage: false)

        let contents: String = try fs.readFileContents(dest)
        let (_, suites) = try XUnitXMLHelpers.parseTestsuites(contents)
        try #require(suites.count == 1)
        #expect(XUnitXMLHelpers.packagePropertyValue(in: suites[0]) == "myproject")
        #expect(XUnitXMLHelpers.testcaseNames(in: suites[0]).sorted() == ["testOne", "testTwo"])
    }

    @Test
    func generate_multiPackageResults_emitsPerPackageTestsuitesEachAnnotated() throws {
        let fs = InMemoryFileSystem()
        let dest = AbsolutePath("/out.xml")

        let generator = XUnitGenerator(
            fileSystem: fs,
            results: [
                Self.makeResult(
                    packageIdentity: .plain("lib-a"),
                    productName: "LibAXCTests",
                    testCase: "LibAXCTests.LibAXCTests",
                    testName: "testLibAGreeting",
                ),
                Self.makeResult(
                    packageIdentity: .plain("lib-b"),
                    productName: "LibBXCTests",
                    testCase: "LibBXCTests.LibBXCTests",
                    testName: "testLibBGreeting",
                ),
            ],
        )
        try generator.generate(at: dest, detailedFailureMessage: false)

        let contents: String = try fs.readFileContents(dest)
        let (_, suites) = try XUnitXMLHelpers.parseTestsuites(contents)
        try #require(suites.count == 2)
        let byPackage = Dictionary(uniqueKeysWithValues: suites.compactMap { suite -> (String, XMLElement)? in
            guard let package = XUnitXMLHelpers.packagePropertyValue(in: suite) else { return nil }
            return (package, suite)
        })
        let libASuite = try #require(byPackage["lib-a"])
        let libBSuite = try #require(byPackage["lib-b"])
        #expect(XUnitXMLHelpers.testcaseNames(in: libASuite) == ["testLibAGreeting"])
        #expect(XUnitXMLHelpers.testcaseNames(in: libBSuite) == ["testLibBGreeting"])
    }

    @Test
    func generate_withEmptyResults_emitsEmptyTestsuiteWithZeroCounts() throws {
        // Regression: `swift test --xunit-output PATH` on a package with
        // no test cases must still produce an xUnit file whose
        // `<testsuite>` reports `tests="0" failures="0"`. Prior to the
        // per-package grouping, this was the default flat output; the
        // grouping change must not lose it when the result list is empty.
        let fs = InMemoryFileSystem()
        let dest = AbsolutePath("/out.xml")

        let generator = XUnitGenerator(fileSystem: fs, results: [])
        try generator.generate(at: dest, detailedFailureMessage: false)

        let contents: String = try fs.readFileContents(dest)
        let (_, suites) = try XUnitXMLHelpers.parseTestsuites(contents)
        try #require(suites.count == 1)
        #expect(XUnitXMLHelpers.packagePropertyValue(in: suites[0]) == nil)
        #expect(suites[0].attribute(forName: "tests")?.stringValue == "0")
        #expect(suites[0].attribute(forName: "failures")?.stringValue == "0")
        #expect(XUnitXMLHelpers.testcaseNames(in: suites[0]).isEmpty)
    }

    @Test
    func generate_resultsWithNilPackageIdentity_emitsUnannotatedTestsuite() throws {
        // Back-compat: cached `BuiltTestProduct` values from pre-workspace
        // SwiftPM invocations decode with `packageIdentity == nil`. The
        // generator must still emit its historical single-suite shape
        // for those results, with no `<properties>` block.
        let fs = InMemoryFileSystem()
        let dest = AbsolutePath("/out.xml")

        let generator = XUnitGenerator(
            fileSystem: fs,
            results: [
                Self.makeResult(
                    packageIdentity: nil,
                    productName: "LegacyTests",
                    testCase: "LegacyTests.FirstTests",
                    testName: "testLegacy",
                ),
            ],
        )
        try generator.generate(at: dest, detailedFailureMessage: false)

        let contents: String = try fs.readFileContents(dest)
        let (_, suites) = try XUnitXMLHelpers.parseTestsuites(contents)
        try #require(suites.count == 1)
        #expect(XUnitXMLHelpers.packagePropertyValue(in: suites[0]) == nil)
        #expect(XUnitXMLHelpers.testcaseNames(in: suites[0]) == ["testLegacy"])
    }
}
