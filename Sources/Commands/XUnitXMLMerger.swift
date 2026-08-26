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

import Basics
import Foundation

#if canImport(FoundationXML)
import FoundationXML
#endif

/// Combines xUnit XML files produced by individual test binaries into a single
/// output file. Each source file's `<testsuite>` elements are preserved
/// and placed under one `<testsuites>` root in the destination.
///
/// Multiple Swift Testing binaries (one per test product) each write their own
/// xUnit output; without merging, later invocations would truncate earlier ones
/// via `fopen(path, "wb")`. This type aggregates those outputs.
///
/// In a workspace context each source can be annotated with the identity of
/// the workspace member that produced it. When set, every extracted
/// `<testsuite>` element in the merged output gets an
/// `<properties><property name="package" value="<identity>"/></properties>`
/// child so downstream consumers (CI reporters, IDEs) can attribute each
/// suite to its owning member.
enum XUnitXMLMerger {
    /// One xUnit XML source file to merge, optionally attributed to a
    /// workspace member.
    struct Source {
        /// Path to the source xUnit XML file. May be absent on disk —
        /// missing files are skipped (see `merge`).
        let path: AbsolutePath
        /// Identity of the workspace member that produced this source, as
        /// its `PackageIdentity.description`. `nil` for single-package
        /// (non-workspace) runs; when set, every `<testsuite>` extracted
        /// from this source is annotated with a `package` property.
        let package: String?
    }

    static func merge(
        sources: [Source],
        into destination: AbsolutePath,
        fileSystem: FileSystem = localFileSystem,
    ) throws {
        let root = XMLElement(name: "testsuites")
        let document = XMLDocument(rootElement: root)
        document.version = "1.0"
        document.characterEncoding = "UTF-8"

        for source in sources {
            guard fileSystem.exists(source.path) else { continue }
            let contents: String = try fileSystem.readFileContents(source.path)
            for testsuite in try extractTestsuites(from: contents) {
                if let package = source.package {
                    annotatePackage(testsuite, packageIdentity: package)
                }
                root.addChild(testsuite)
            }
        }

        try fileSystem.writeFileContents(
            destination,
            string: document.xmlString(options: [.nodePrettyPrint, .nodeCompactEmptyElement]),
        )
    }

    private static func extractTestsuites(from xml: String) throws -> [XMLElement] {
        let document = try XMLDocument(xmlString: xml, options: [])
        guard let root = document.rootElement() else { return [] }
        return root.elements(forName: "testsuite").map { element in
            element.detach()
            return element
        }
    }

    /// Adds a `<property name="package" value="<identity>"/>` entry to
    /// the testsuite's `<properties>` block, creating the block if it
    /// doesn't already exist. If a `package` property is already present
    /// it's left untouched (source-of-truth wins).
    private static func annotatePackage(_ testsuite: XMLElement, packageIdentity: String) {
        let properties: XMLElement
        if let existing = testsuite.elements(forName: "properties").first {
            properties = existing
        } else {
            properties = XMLElement(name: "properties")
            testsuite.addChild(properties)
        }
        let alreadyHasPackage = properties.elements(forName: "property").contains { property in
            property.attribute(forName: "name")?.stringValue == "package"
        }
        guard !alreadyHasPackage else { return }
        let property = XMLElement(name: "property")
        property.addAttribute(XMLNode.attribute(withName: "name", stringValue: "package") as! XMLNode)
        property.addAttribute(XMLNode.attribute(withName: "value", stringValue: packageIdentity) as! XMLNode)
        properties.addChild(property)
    }
}
