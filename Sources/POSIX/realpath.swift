/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import var SPMLibc.errno
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

private let pathComponentSeparator = "/"

/**
 Resolves executable, both absolute and relative paths and referred from `PATH` environment variable and
 return the absolute pathname.

 All components in executable must exists when realpath(executable:) is called.
*/
public func realpath(executable: String) throws -> String {
    if executable.starts(with: pathComponentSeparator) {
        return try realpath(argv0)
    }
    if executable.contains(pathComponentSeparator.first!) {
        return try realpath(getcwd() + pathComponentSeparator + executable)
    }
    if let paths = getenv("PATH")?.split(separator: ":") {
        for path in paths {
            if let s = try? stat(String(path) + "/" + executable) {
                if s.kind == .file || s.kind == .symlink {
                    let suffixedPath = path.reversed().starts(with: pathComponentSeparator) ? path : path + "/"
                    return try realpath(suffixedPath + executable)
                }
            }
        }
    }
    throw SystemError.realpath(2, executable)
}
