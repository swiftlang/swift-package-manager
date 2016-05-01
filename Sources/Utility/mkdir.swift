/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

/**
 Recursively creates directories producing: `path`.

 It is *not* an error if the directory already exists.

 Returns the created directory path; either absolute if an absolute path was passed, otherwise relative to the current working directory.
*/
public func mkdir(_ path: String...) throws -> String {
    return try mkdir(path)
}

public func mkdir(_ path: [String]) throws -> String {
    let prefix = path.joined(separator: "/")

    try NSFileManager.`default`().createDirectory(atPath: prefix, withIntermediateDirectories: true, attributes: [:])

    return prefix
}
