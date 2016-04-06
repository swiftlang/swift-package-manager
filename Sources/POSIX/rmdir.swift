/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/


import var libc.errno
import func libc.rmdir

public func rmdir(_ path: String) throws {
    guard rmdir(path) == 0 else {
        throw SystemError.rmdir(errno, path)
    }
}
