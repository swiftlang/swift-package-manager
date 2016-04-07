/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func libc.strftime
import struct libc.tm

public func strftime(_ format: String, time: tm) throws -> String {
    let resultSize = format.characters.count + 200
    let result = UnsafeMutablePointer<Int8>(allocatingCapacity: resultSize)
    defer {
        result.deallocateCapacity(resultSize)
    }
    var time = time
    guard libc.strftime(result, resultSize, format, &time) != 0 else {
        throw SystemError.strftime
    }

    return String(cString: result)
}
