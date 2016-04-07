/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/


import func libc.unlink
import var libc.errno

public func unlink(_ path: String) throws {
    guard libc.unlink(path) == 0 else {
        throw SystemError.unlink(errno, path)
    }
}
