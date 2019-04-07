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

    /// The device number.
    public let device: UInt64

    /// The inode number.
    public let inode: UInt64

    /// The size of the file.
    public let size: UInt64

    /// The modification time of the file.
    public let modTime: Date

    /// Kind of file system entity.
    public let posixPermissions: Int16

    /// Kind of file system entity.
    public let fileType: FileAttributeType

    public init(_ attrs: [FileAttributeKey : Any]) {
        let device = (attrs[.systemNumber] as? NSNumber)?.uint64Value
        assert(device != nil)
        self.device = device!

        let inode = attrs[.systemFileNumber] as? UInt64
        assert(inode != nil)
        self.inode = inode!

        let posixPermissions = (attrs[.posixPermissions] as? NSNumber)?.int16Value
        assert(posixPermissions != nil)
        self.posixPermissions = posixPermissions!

        let fileType = attrs[.type] as? FileAttributeType
        assert(fileType != nil)
        self.fileType = fileType!

        let size = attrs[.size] as? UInt64
        assert(size != nil)
        self.size = size!

        let modTime = attrs[.modificationDate] as? Date
        assert(modTime != nil)
        self.modTime = modTime!
    }
}

extension FileAttributeType: Codable {}
