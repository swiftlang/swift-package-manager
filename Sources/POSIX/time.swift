/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func libc.time
import typealias libc.time_t
import var libc.errno

public func time() throws -> time_t {
    let time = libc.time(nil)
    guard time != -1 else {
        throw SystemError.time(errno)
    }
    return time
}
