/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func libc.ctime_r
import var libc.errno

public func ctime_r() throws -> String {
    // The string result that is produced by the ctime_r() function contains exactly 26 characters.
    let buffer = UnsafeMutablePointer<Int8>(allocatingCapacity: 50)
    defer {
        buffer.deallocateCapacity(50)
    }
    var t = try time()
    let result = libc.ctime_r(&t, buffer)
    guard result != nil else {
        throw SystemError.ctime_r(errno)
    }

    return String(cString: result!)
}
