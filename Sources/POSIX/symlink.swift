/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func libc.dirfd
import var libc.errno
import func libc.symlinkat

/**
 Pass relative paths, nothing is normalized.
*/
public func symlink(create from: String, pointingAt to: String, relativeTo: String) throws {
    let d = try POSIX.opendir(relativeTo)
    defer { closedir(d) }

    let fd = dirfd(d)
    guard fd != -1 else { throw SystemError.dirfd(errno, relativeTo) }

    let rv = symlinkat(to, fd, from)
    guard rv != -1 else { throw SystemError.symlinkat(errno, to) }
}
