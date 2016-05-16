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
 Causes the named directory to become the current working directory.
*/
public func chdir(_ path: String) throws {
    if memo == nil {
        let argv0 = try realpath(Process.arguments.first!)
        let cwd = try realpath(getcwd())
        memo = (argv0: argv0, wd: cwd)
    }

    if !NSFileManager.`default`().changeCurrentDirectoryPath(path) {
        throw SystemError.chdir(-1)
    }
}


private var memo: (argv0: String, wd: String)?

/**
 The initial working directory before any calls to Utility.chdir.
*/
public func getiwd() -> String {
    return memo?.wd ?? getcwd()
}

public var argv0: String {
    return memo?.argv0 ?? Process.arguments.first!
}
