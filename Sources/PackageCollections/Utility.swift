/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import class Foundation.FileManager
import TSCBasic

import PackageModel
import SourceControl

struct MultipleErrors: Error {
    let errors: [Error]

    init(_ errors: [Error]) {
        self.errors = errors
    }
}

struct NotFoundError: Error {
    let item: String

    init(_ item: String) {
        self.item = item
    }
}
