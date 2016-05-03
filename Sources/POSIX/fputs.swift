/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct libc.FILE
import func libc.fputs
import func libc.fwrite
import var libc.EOF

public func fputs(_ string: String, _ fp: UnsafeMutablePointer<FILE>) throws {
    guard libc.fputs(string, fp) != EOF else {
        throw SystemError.fputs
    }
}

public func fputs(_ bytes: [UInt8], _ fp: UnsafeMutablePointer<FILE>) throws {
    guard libc.fwrite(bytes, bytes.count, 1, fp) == 1 else {
        throw SystemError.fputs
    }
}
