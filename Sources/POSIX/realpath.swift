/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import var SPMLibc.errno
import var SPMLibc.ENOENT
import func SPMLibc.free
import func SPMLibc.realpath

/**
 Resolves all symbolic links, extra "/" characters, and references to /./
 and /../ in the input.

 Resolves both absolute and relative paths and return the absolute
 pathname.  All components in the provided input must exist when realpath()
 is called.
*/
public func realpath(_ path: String) throws -> String {
    let rv = realpath(path, nil)
    guard rv != nil else { throw SystemError.realpath(errno, path) }
    defer { free(rv) }
    guard let rvv = String(validatingUTF8: rv!) else { throw SystemError.realpath(-1, path) }
    return rvv
}

/**
 Resolves executable, both absolute and relative paths and referred from `PATH` environment variable and
 return the absolute pathname.

 All components in executable must exists when realpath(executable:) is called.
*/
public func realpath(executable: String) throws -> String {
    // when executable is an absolute path like `/usr/bin/swift`
    if executable.hasPrefix("/") {
        return try realpath(argv0)
    }
    // when executable is a relative path like `./swift` or `bin/swift`
    if executable.contains("/") {
        return try realpath(getcwd() + "/" + executable)
    }
    // when executable is resolved from PATH, it may be `swift` without any path component separator
    if let paths = getenv("PATH")?.split(separator: ":") {
        for path in paths {
            let joinedPath = String((path.hasSuffix("/") ? path : path + "/") + executable)
            if let fileStat = try? stat(joinedPath) {
                if fileStat.kind == .file || fileStat.kind == .symlink {
                    return try realpath(joinedPath)
                }
            }
        }
    }
    throw SystemError.realpath(ENOENT, executable)
}
