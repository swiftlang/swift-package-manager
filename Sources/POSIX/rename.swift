/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import var SPMLibc.errno
import func SPMLibc.rename

public func rename(old: String, new: String) throws {
    let rv = SPMLibc.rename(old, new)
    guard rv == 0 else { throw SystemError.rename(errno, old: old, new: new) }
}
