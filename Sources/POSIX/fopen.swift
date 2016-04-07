/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct libc.FILE
import func libc.fopen
import var libc.errno

public enum FopenMode: String {
    case Read = "r"
    case Write = "w"
}

public func fopen(_ path: String, mode: FopenMode = .Read) throws -> UnsafeMutablePointer<FILE> {
    let f = libc.fopen(path, mode.rawValue)
    guard f != nil else { throw SystemError.fopen(errno, path) }
    return f
}
