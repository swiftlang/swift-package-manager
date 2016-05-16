/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/


import Foundation
import enum POSIX.SystemError

/**
 Resolves all symbolic links, extra "/" characters, and references to /./
 and /../ in the input.

 Resolves both absolute and relative paths and return the absolute
 pathname.  All components in the provided input must exist when realpath()
 is called.
*/
public func realpath(_ path: String) throws -> String {
    let cwd = NSURL(fileURLWithPath: getcwd())
    let rv: NSURL

    #if os(OSX)
        if #available(OSX 10.11, *) {
            rv = NSURL(fileURLWithPath: path, relativeTo: cwd)
        } else {
            rv = NSURL(string: path, relativeTo: cwd)!
        }
    #else
        rv = NSURL(fileURLWithPath: path, relativeToURL: cwd)
    #endif

    #if os(OSX)
        let rvv = rv.resolvingSymlinksInPath?.standardizingPath
    #else
        let rvv = rv.URLByResolvingSymlinksInPath?.URLByStandardizingPath
    #endif

    guard let rvvv = rvv else { throw SystemError.realpath(-1, path) }
    return rvvv.path!
}
