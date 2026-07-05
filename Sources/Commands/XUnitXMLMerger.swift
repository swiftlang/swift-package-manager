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

/// Combines xUnit XML files produced by individual test binaries into a single
/// output file. Each source file's `<testsuite>` elements are preserved verbatim
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
        var output = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<testsuites>\n"

        for source in sources {
            guard fileSystem.exists(source) else { continue }
            let contents: String = try fileSystem.readFileContents(source)
            for block in extractTestsuiteBlocks(from: contents) {
                output += block
                output += "\n"
            }
        }

        output += "</testsuites>\n"
        try fileSystem.writeFileContents(destination, string: output)
    }

    private static let openMarker = "<testsuite"
    private static let closeMarker = "</testsuite>"

    private static func extractTestsuiteBlocks(from xml: String) -> [Substring] {
        var results: [Substring] = []
        var searchStart = xml.startIndex
        while let openRange = xml.range(of: openMarker, range: searchStart..<xml.endIndex) {
            let afterOpen = openRange.upperBound
            guard afterOpen < xml.endIndex else { break }
            let nextChar = xml[afterOpen]
            guard nextChar == " " || nextChar == ">" else {
                searchStart = afterOpen
                continue
            }
            guard let closeRange = xml.range(of: closeMarker, range: afterOpen..<xml.endIndex) else {
                break
            }
            results.append(xml[openRange.lowerBound..<closeRange.upperBound])
            searchStart = closeRange.upperBound
        }
        return results
    }
}
