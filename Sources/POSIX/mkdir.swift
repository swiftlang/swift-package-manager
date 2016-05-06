/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import var libc.EEXIST
import var libc.errno
import func libc.mkdir
import var libc.S_IRWXU
import var libc.S_IRWXG
import var libc.S_IRWXO

#if os(Linux)
    import Foundation  // String.hasPrefix
#endif

/**
 Recursively creates directories producing: `path`.

 It is *not* an error if the directory already exists.
*/
public func mkdir(_ path: String...) throws -> String {
    return try mkdir(path)
}

public func mkdir(_ path: [String]) throws -> String {
    let parts = path.flatMap{ $0.characters.split(separator: "/") }
    var prefix = path.first!.hasPrefix("/")
        ? ""
        : getcwd()

    for dir in parts {
        prefix = "\(prefix)/\(String(dir))"
        // TODO what is the general policy for attributes?
        guard mkdir(prefix, S_IRWXU | S_IRWXG | S_IRWXO) == 0 || errno == EEXIST else {
            throw SystemError.mkdir(errno, prefix)
        }
    }

    return prefix	
}

@available(*, unavailable)
public func mkdir() {}
