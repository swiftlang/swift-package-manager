/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct libc.DirHandle
import var libc.errno
import func libc.opendir

public func opendir(path: String) throws -> DirHandle {
    let d = libc.opendir(path)
    guard d != nil else { throw SystemError.opendir(errno, path) }
    return d
}

@_exported import func libc.closedir
