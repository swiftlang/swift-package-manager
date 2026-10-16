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

/// Extracts the tags of every discovered test from a Swift Testing event stream
/// (JSON Lines) written by a test binary that was run with `--list-tests`.
enum TestTagCollector {
    private struct Record: Decodable {
        let kind: String
        let payload: Payload?

        struct Payload: Decodable {
            let tags: [String]?
        }
    }

    static func tags(fromJSONLines contents: String) -> Set<String> {
        var result: Set<String> = []
        let decoder = JSONDecoder()
        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let record = try? decoder.decode(Record.self, from: Data(line.utf8)),
                  record.kind == "test" else { continue }
            result.formUnion(record.payload?.tags ?? [])
        }
        return result
    }
}
