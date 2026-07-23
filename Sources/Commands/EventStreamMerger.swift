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

/// Combines Swift Testing event stream files produced by individual test
/// binaries into a single JSON Lines output file. Every record from every
/// source is preserved, in source order.
///
/// Multiple Swift Testing binaries (one per test product) each write their own
/// event stream; without merging, later invocations would truncate earlier ones
/// via `fopen(path, "wb")`.
enum EventStreamMerger {
    static func merge(
        sources: [AbsolutePath],
        into destination: AbsolutePath,
        fileSystem: FileSystem = localFileSystem,
    ) throws {
        var lines: [String] = []
        for source in sources {
            guard fileSystem.exists(source) else { continue }
            let contents: String = try fileSystem.readFileContents(source)
            lines.append(
                contentsOf: contents
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .map(String.init)
            )
        }

        let merged = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try fileSystem.writeFileContents(destination, string: merged)
    }
}
