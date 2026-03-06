//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation

// looking into the file content to see if it is using the @main annotation
// this is not bullet-proof since theoretically the file can contain the @main string for other reasons
// but it is the closest to accurate we can do at this point
package func containsAtMain(fileSystem: FileSystem, path: AbsolutePath) throws -> Bool {
    let content: String = try fileSystem.readFileContents(path)
    let lines = content.split(whereSeparator: { $0.isNewline }).map { $0.trimmingCharacters(in: .whitespaces) }

    var multilineComment = false
    for line in lines {
        if line.hasPrefix("//") {
            continue
        }

        // Process the line character-by-character to handle comment boundaries
        // and @main detection on the same line (e.g., `*/ @main`).
        var remaining = line[line.startIndex...]
        while !remaining.isEmpty {
            if multilineComment {
                if let endRange = remaining.range(of: "*/") {
                    multilineComment = false
                    remaining = remaining[endRange.upperBound...]
                    // Trim leading whitespace from the remainder
                    remaining = remaining.drop(while: { $0.isWhitespace })
                } else {
                    // Entire remainder is inside a comment
                    break
                }
            } else {
                if remaining.hasPrefix("/*") {
                    multilineComment = true
                    remaining = remaining[remaining.index(remaining.startIndex, offsetBy: 2)...]
                } else if remaining.hasPrefix("@main") {
                    return true
                } else {
                    break
                }
            }
        }
    }
    return false
}
