/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic

extension FileSystem {
    // Returns true if a path does not exist. Makes #expect statements more obvious.
    public func notExists(_ path: AbsolutePath, followSymlink: Bool = false) -> Bool {
        !exists(path, followSymlink: followSymlink)
    }
}
