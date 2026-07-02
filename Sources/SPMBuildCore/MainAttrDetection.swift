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
    return containsAtMain(in: content)
}

// Scans the content character-by-character, tracking line and block comment
// state plus single and multi-line string literal state. Returns true when
// `@main` is the first non-comment token on a line.
func containsAtMain(in content: String) -> Bool {
    var blockCommentDepth = 0
    var inLineComment = false
    var inString = false
    var inMultilineString = false
    var atLineStart = true
    let chars = Array(content)
    let n = chars.count
    var i = 0
    while i < n {
        let c = chars[i]

        if c.isNewline {
            inLineComment = false
            atLineStart = true
            i += 1
            continue
        }

        if inMultilineString {
            if c == "\\", i + 1 < n {
                i += 2
                continue
            }
            if c == "\"", i + 2 < n, chars[i + 1] == "\"", chars[i + 2] == "\"" {
                inMultilineString = false
                i += 3
                continue
            }
            i += 1
            continue
        }

        if inString {
            if c == "\\", i + 1 < n {
                i += 2
                continue
            }
            if c == "\"" {
                inString = false
                i += 1
                continue
            }
            i += 1
            continue
        }

        if blockCommentDepth > 0 {
            if c == "/", i + 1 < n, chars[i + 1] == "*" {
                blockCommentDepth += 1
                i += 2
                continue
            }
            if c == "*", i + 1 < n, chars[i + 1] == "/" {
                blockCommentDepth -= 1
                i += 2
                continue
            }
            i += 1
            continue
        }

        if inLineComment {
            i += 1
            continue
        }

        if c == "/", i + 1 < n, chars[i + 1] == "/" {
            inLineComment = true
            i += 2
            continue
        }
        if c == "/", i + 1 < n, chars[i + 1] == "*" {
            blockCommentDepth = 1
            i += 2
            continue
        }
        if c == "\"", i + 2 < n, chars[i + 1] == "\"", chars[i + 2] == "\"" {
            inMultilineString = true
            atLineStart = false
            i += 3
            continue
        }
        if c == "\"" {
            inString = true
            atLineStart = false
            i += 1
            continue
        }

        if c == " " || c == "\t" {
            i += 1
            continue
        }

        if atLineStart, c == "@",
           i + 4 < n,
           chars[i + 1] == "m",
           chars[i + 2] == "a",
           chars[i + 3] == "i",
           chars[i + 4] == "n"
        {
            return true
        }
        atLineStart = false
        i += 1
    }
    return false
}
