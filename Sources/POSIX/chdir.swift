/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func libc.chdir
import var libc.errno

/**
 Causes the named directory to become the current working directory.
*/
public func chdir(_ path: String) throws {
    if memo == nil {
        let argv0 = try realpath(CommandLine.arguments.first!)
        let cwd = try realpath(getcwd())
        memo = (argv0: argv0, wd: cwd)
    }

    guard libc.chdir(path) == 0 else {
        throw SystemError.chdir(errno, path)
    }
}

private var memo: (argv0: String, wd: String)?

/**
 The initial working directory before any calls to POSIX.chdir.
*/
public func getiwd() -> String {
    return memo?.wd ?? getcwd()
}

public var argv0: String {
    return memo?.argv0 ?? CommandLine.arguments.first!
}
