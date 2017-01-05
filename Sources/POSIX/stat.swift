/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import libc

/// Extensions to the libc `stat` structure to interpret the contents in more readable ways.
extension libc.stat {

     /// File system entity kind.
     public enum Kind {
         case file, directory, symlink, fifo, blockdev, chardev, socket, unknown

         fileprivate init(mode: mode_t) {
             switch mode {
                 case S_IFREG:  self = .file
                 case S_IFDIR:  self = .directory
                 case S_IFLNK:  self = .symlink
                 case S_IFBLK:  self = .blockdev
                 case S_IFCHR:  self = .chardev
                 case S_IFSOCK: self = .socket
             default:
                 self = .unknown
             }
         }
     }

     /// Kind of file system entity.
     public var kind: Kind {
         return Kind(mode: st_mode & S_IFMT)
     }
 }

public func stat(_ path: String) throws -> libc.stat {
    var sbuf = libc.stat()
    let rv = stat(path, &sbuf)
    guard rv == 0 else { throw SystemError.stat(errno, path) }
    return sbuf
}

public func lstat(_ path: String) throws -> libc.stat {
    var sbuf = libc.stat()
    let rv = lstat(path, &sbuf)
    guard rv == 0 else { throw SystemError.stat(errno, path) }
    return sbuf
}
