/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import var libc.errno
import func libc.mkdtemp
import func libc.rmdir

#if os(Linux)
    import Foundation  // String.hasSuffix
#endif

/**
 Creates a temporary directory for the duration of the provided closure.
 
 - Note: We only call rmdir() on the directory once done, it is up to
 you to recursively delete the contents and thus ensure the rmdir succeeds
*/
public func mkdtemp<T>(_ template: String, prefix: String! = nil, body: @noescape(String) throws -> T) rethrows -> T {
    var prefix = prefix
    if prefix == nil { prefix = getenv("TMPDIR") ?? "/tmp/" }
    if !prefix!.hasSuffix("/") {
        prefix! += "/"
    }
    let path = prefix! + "\(template).XXXXXX"

    return try path.withCString { template in
        let mutable = UnsafeMutablePointer<Int8>(template)
        let dir = libc.mkdtemp(mutable)  //TODO get actual TMP dir
        if dir == nil { throw SystemError.mkdtemp(errno) }
        defer { rmdir(dir!) }
        return try body(String(validatingUTF8: dir!)!)
    }
}
