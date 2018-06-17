/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import clibc
import Basic
import Foundation

public final class Tag {
    internal typealias Handle = OpaquePointer

    private let handle: Handle
    private let lock = Lock()

    public lazy var identifier: ObjectID = {
        lock.withLock { ObjectID(oid: git_tag_id(self.handle)!.pointee) }
    }()

    public lazy var name: String = {
        lock.withLock { String(cString: git_tag_name(self.handle)!) }
    }()

    internal init(handle: Handle) {
        self.handle = handle
    }
}
