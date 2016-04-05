/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func libc.gmtime_r
import struct libc.tm
import struct libc.time_t
import var libc.errno

public func gmtime_r() throws -> tm {
    var t = try time()
    var tmTime: tm = tm()
    let result = libc.gmtime_r(&t, &tmTime)
    guard result != nil else {
        throw SystemError.gmtime_r(errno)
    }

    return tmTime
}
