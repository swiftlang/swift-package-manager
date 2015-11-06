/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func libc.fopen
import var libc.errno

public func fopen(path: String..., mode: String = "r") throws -> UnsafeMutablePointer<FILE> {
    let path = joinPathComponents(path)
    let f = libc.fopen(path, mode)
    guard f != nil else { throw SystemError.fopen(errno, path) }
    return f
}

/**
 Joins path components, unless a component is an absolute
 path, in which case it discards all previous path components.
*/
func joinPathComponents(join: [String]) -> String {
    guard join.count > 0 else { return "" }

    return join.dropFirst(1).reduce(join[0]) {
        if $1.hasPrefix("/") {
            return $1
        } else {
            return $0 + "/" + $1
        }
    }
}
