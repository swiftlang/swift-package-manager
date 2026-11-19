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


package func _getDiff(
    _ original: String,
    with modified: String,
) -> String {

    let originalLines = original.components(separatedBy: "\n")
    let modifiedLines = modified.components(separatedBy: "\n")

    let diff = modifiedLines.difference(from: originalLines)

    // Build a dictionary of removals by their original line index
    var removals: [Int: String] = [:]
    for change in diff.removals {
        if case let .remove(offset, element, _) = change {
            removals[offset] = element
        }
    }

    // Build a dictionary of insertions by their target line index
    var insertions: [Int: String] = [:]
    for change in diff.insertions {
        if case let .insert(offset, element, _) = change {
            insertions[offset] = element
        }
    }

    // Reconstruct the diff linearly
    var origIndex = 0
    var modIndex = 0

    var diffLines: [String] = []
    while origIndex < originalLines.count || modIndex < modifiedLines.count {
        if let removedLine = removals[origIndex] {
            diffLines.append("- \(removedLine)")
            origIndex += 1
        } else if let insertedLine = insertions[modIndex] {
            diffLines.append("+ \(insertedLine)")
            modIndex += 1
        } else {
            // Line matches in both
            if origIndex < originalLines.count {
                diffLines.append("  \(originalLines[origIndex])")
                origIndex += 1
                modIndex += 1
            }
        }
    }
    return diffLines.joined(separator: "\n")
}
