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
enum XUnitXMLMerger {
    static func merge(
        sources: [AbsolutePath],
        into destination: AbsolutePath,
        fileSystem: FileSystem = localFileSystem,
    ) throws {
        let root = XMLElement(name: "testsuites")
        let document = XMLDocument(rootElement: root)
        document.version = "1.0"
        document.characterEncoding = "UTF-8"

        for source in sources {
            guard fileSystem.exists(source) else { continue }
            let contents: String = try fileSystem.readFileContents(source)
            for testsuite in try extractTestsuites(from: contents) {
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
}
