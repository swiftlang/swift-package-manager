/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import libc

/// Get file status.
//
// FIXME: We should probably return our own wrapper type to insulate clients
// from platform dependencies.
public func stat(_ path: String) throws -> libc.stat {
    var buf = libc.stat()
    guard libc.stat(path, &buf) == 0 else {
        throw SystemError.dirfd(errno, path)
    }
    return buf
}
