/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import SPMLibc

/// File system information for a particular file.
public struct FileInfo: Equatable, Codable {

    /// File timestamp wrapper.
    public struct FileTimestamp: Equatable, Codable {
        public let seconds: UInt64
        public let nanoseconds: UInt64
    }

    /// File system entity kind.
    public enum Kind {
        case file, directory, symlink, blockdev, chardev, socket, unknown

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

    /// The device number.
    public let device: UInt64

    /// The inode number.
    public let inode: UInt64

    /// The mode flags of the file.
    public let mode: UInt64

    /// The size of the file.
    public let size: UInt64

    /// The modification time of the file.
    public let modTime: FileTimestamp

    /// Kind of file system entity.
    public var kind: Kind {
        return Kind(mode: mode_t(mode) & S_IFMT)
    }

    public init(_ buf: SPMLibc.stat) {
        self.device = UInt64(buf.st_dev)
        self.inode = UInt64(buf.st_ino)
        self.mode = UInt64(buf.st_mode)
        self.size = UInt64(buf.st_size)

      #if os(macOS)
        let seconds = buf.st_mtimespec.tv_sec
        let nanoseconds = buf.st_mtimespec.tv_nsec
      #else
        let seconds = buf.st_mtim.tv_sec
        let nanoseconds = buf.st_mtim.tv_nsec
      #endif

        self.modTime = FileTimestamp(
            seconds: UInt64(seconds), nanoseconds: UInt64(nanoseconds))
    }
}

public func stat(_ path: String) throws -> SPMLibc.stat {
    var sbuf = SPMLibc.stat()
    let rv = stat(path, &sbuf)
    guard rv == 0 else { throw SystemError.stat(errno, path) }
    return sbuf
}

public func lstat(_ path: String) throws -> SPMLibc.stat {
    var sbuf = SPMLibc.stat()
    let rv = lstat(path, &sbuf)
    guard rv == 0 else { throw SystemError.stat(errno, path) }
    return sbuf
}
