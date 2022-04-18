//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct TSCBasic.StringError

public typealias StringError = TSCBasic.StringError

public struct InternalError: Error {
    private let description: String
    public init(_ description: String) {
        assertionFailure(description)
        self.description = "Internal error. Please file a bug at https://bugs.swift.org with this info. \(description)"
    }
}
