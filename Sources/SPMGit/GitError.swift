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

/// Error encountered during a git operation.
public struct GitError: Error {
    let code: git_error_code
    let `class`: git_error_t
    let message: String
}
