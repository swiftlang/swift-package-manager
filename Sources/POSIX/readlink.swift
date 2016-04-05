/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import var libc.errno
import var libc.PATH_MAX
import func libc.readlink

public func readlink(_ path: String) throws -> String {
    let N = Int(PATH_MAX)
    let mem = UnsafeMutablePointer<Int8>(allocatingCapacity: N + 1)
    let n = readlink(path, mem, N)
    guard n >= 0 else {
        throw SystemError.readlink(errno, path)
    }
    mem[n] = 0  // readlink does not null terminate what it returns

    return String(validatingUTF8: mem)!
}
