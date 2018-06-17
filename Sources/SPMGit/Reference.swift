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

public class Reference {
    internal typealias Handle = OpaquePointer

    /// The reference struct pointer.
    internal let handle: Handle

    /// Lock to synchronize critical operations.
    internal let lock = Lock()

    internal init(handle: Handle) {
        self.handle = handle
    }

    deinit {
        git_reference_free(handle)
    }
}
