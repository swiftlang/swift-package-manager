/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

/// File system information for a particular file.
public struct FileInfo: Equatable, Codable {

    /// File timestamp wrapper.
    public struct FileTimestamp: Equatable, Codable {
        public let seconds: UInt64
        public let nanoseconds: UInt64

        // init(from date: Date) {
        //     // TODO(compnerd) initialize the value fro the Date
        //     self.seconds = 0
        //     self.nanoseconds = 0
        // }
    }

    /// File system entity kind.
    public enum Kind {
        case file, directory, symlink, blockdev, chardev, socket, unknown
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
        return .unknown
    }

    public init(attributes: [FileAttributeKey:Any]) {
        self.device = attributes[.systemNumber] as! UInt64
        self.inode = attributes[.systemFileNumber] as! UInt64
        self.mode = attributes[.posixPermissions] as! UInt64
        self.size = attributes[.size] as! UInt64

        // switch attributes[.type] as! FileAttributeType {
        // case .typeRegular:
        //     self.kind = .file
        // case .typeDirectory:
        //     self.kind = .directory
        // case .typeSymbolicLink:
        //     self.kind = .symlink
        // case .typeBlockSpecial:
        //     self.kind = .blockdev
        // case .typeCharacterSpecial:
        //     self.kind = .chardev
        // case .typeSocket:
        //     self.kind = .socket
        // case .typeUnknown:
        //     self.kind = .unknown
        // }

        // self.modTime = FileTimestamp(from: attributes[.modificationTime] as! Date)
        self.modTime = FileTimestamp(seconds: 0, nanoseconds: 0)
    }
}
