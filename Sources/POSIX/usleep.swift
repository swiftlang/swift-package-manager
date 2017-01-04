/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import libc

/// Suspends execution of the calling thread for the provided microseconds.
public func usleep(microSeconds: Int) throws {
    let rv = usleep(useconds_t(microSeconds))
    guard rv == 0 else { throw SystemError.usleep(errno) }
}
