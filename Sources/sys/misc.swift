/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -------------------------------------------------------------------------
 Everything here should be moved to better places, it is a temporary
 repository for modules-to-be.
*/

import libc
import POSIX

/**
 Recursively deletes the provided directory.
 */
public func rmtree(components: String...) throws {
    let path = Path.join(components)
    var dirs = [String]()
    for entry in walk(path, recursively: true) {
        if entry.isDirectory {
            dirs.append(entry)
        } else {
            try POSIX.unlink(entry)
        }
    }
    for dir in dirs.reverse() {
        do {
            try POSIX.rmdir(dir)
        } catch .rmdir(let errno, _) as SystemError where errno == ENOENT {
            // Ignore ENOENT.
        }
    }
    do {
        try POSIX.rmdir(path)
    } catch .rmdir(let errno, _) as SystemError where errno == ENOENT {
        // Ignore ENOENT.
    }
}

/// - Returns: true if stdin is attached to a terminal
public func attachedToTerminal() -> Bool {
    return isatty(fileno(libc.stdin))
}
