/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/


import var libc.errno
import func libc.free
import func libc.getcwd
import var libc.PATH_MAX

/**
 - Returns: The absolute pathname of the current working directory.
*/
public func getcwd() throws -> String {
    let cwd = libc.getcwd(nil, Int(PATH_MAX))
    if cwd == nil { throw SystemError.getcwd(errno) }
    defer { free(cwd) }
    guard let path = String(validatingUTF8: cwd) else { throw SystemError.getcwd(-1) }
    return path
}
