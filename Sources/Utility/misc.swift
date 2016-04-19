/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -------------------------------------------------------------------------
 Everything here should be moved to better places, it is a temporary
 repository for modules-to-be.
*/

import POSIX
import var libc.ENOENT

/**
 Recursively deletes the provided directory.
 */
public func rmtree(_ components: String...) throws {
    let path = Path.join(components)
    var dirs = [String]()
    for entry in walk(path, recursively: true) {
        if entry.isDirectory && !entry.isSymlink {
            dirs.append(entry)
        } else {
            try POSIX.unlink(entry)
        }
    }
    for dir in dirs.reversed() {
        do {
            try POSIX.rmdir(dir)
        } catch .rmdir(let errno, _) as SystemError where errno == ENOENT {
            // if the directory is not there then proceed
            // this could happen if it was in fact symlinked
            // from another part of the tree etc.
        }
    }
    try POSIX.rmdir(path)
}


#if os(OSX) || os(iOS) || os(Linux)
    extension Character {
        public static var newline: Character { return "\n" }
    }
#else
    //ERROR: Unsupported platform
#endif
