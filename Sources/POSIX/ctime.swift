/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func libc.time
import func libc.ctime
import typealias libc.time_t

public func ctime() throws -> String {
    var time = 0
    libc.time(&time)
    let result = libc.ctime(&time)

    return String(cString: result)
}