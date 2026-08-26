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

import Foundation

#if canImport(FoundationXML)
import FoundationXML
#endif

public struct XUnitXMLHelpers {
    /// Parses an xUnit XML document and returns its root element together
    /// with the `<testsuite>` children when the root is `<testsuites>`.
    ///
    /// Shared by xUnit-related tests (`XUnitXMLMergerTests`,
    /// `XUnitGeneratorTests`, workspace `swift test` e2e tests).
    static public func parseTestsuites(_ xml: String) throws -> (root: XMLElement?, suites: [XMLElement]) {
        let document = try XMLDocument(xmlString: xml, options: [])
        let root = document.rootElement()
        let suites = (root?.name == "testsuites" ? root?.elements(forName: "testsuite") : nil) ?? []
        return (root: root, suites: suites)
    }

    /// Returns the `name` attribute of a `<testsuite>` element, if present.
    static public func testsuiteName(_ element: XMLElement) -> String? {
        element.attribute(forName: "name")?.stringValue
    }

    /// Returns the value of the child
    /// `<properties><property name="package" value="…"/></properties>`
    /// inside a `<testsuite>` element, or `nil` if no such property exists.
    ///
    /// This is the annotation Slice 6 (Swift Testing side) and its
    /// XUnitGenerator follow-up (XCTest side) both emit to attribute each
    /// `<testsuite>` to its owning workspace member.
    static public func packagePropertyValue(in testsuite: XMLElement) -> String? {
        for properties in testsuite.elements(forName: "properties") {
            for property in properties.elements(forName: "property")
            where property.attribute(forName: "name")?.stringValue == "package" {
                return property.attribute(forName: "value")?.stringValue
            }
        }
        return nil
    }

    /// Returns the `name` attribute of each `<testcase>` child of a
    /// `<testsuite>`, in document order.
    static public func testcaseNames(in testsuite: XMLElement) -> [String] {
        testsuite.elements(forName: "testcase")
            .compactMap { $0.attribute(forName: "name")?.stringValue }
    }
}
