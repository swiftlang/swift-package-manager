/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func SPMLibc.chdir
import var SPMLibc.errno

/**
 Causes the named directory to become the current working directory.
*/
public func chdir(_ path: String) throws {
    guard SPMLibc.chdir(path) == 0 else {
        throw SystemError.chdir(errno, path)
    }
}
