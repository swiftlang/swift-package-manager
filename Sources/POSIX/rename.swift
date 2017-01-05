/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import var libc.errno
import func libc.rename

public func rename(old: String, new: String) throws {
    let rv = libc.rename(old, new)
    guard rv == 0 else { throw SystemError.rename(errno, old: old, new: new) }
}
