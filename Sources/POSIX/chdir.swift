/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func libc.chdir
import var libc.errno


private var _argv0: String!

public var argv0: String {
    return _argv0 ?? Process.arguments.first!
}

/**
 Causes the named directory to become the current working directory.
*/
public func chdir(path: String) throws {
    if _argv0 == nil { _argv0 = try realpath(Process.arguments.first!) }

    guard libc.chdir(path) == 0 else {
        throw SystemError.chdir(errno)
    }
}
