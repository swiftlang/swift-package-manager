//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

import struct TSCBasic.ByteString
import protocol TSCBasic.HashAlgorithm

package final class MockHashAlgorithm {
    package typealias Handler = @Sendable (ByteString) -> ByteString

    package let hashes = ThreadSafeArrayStore<ByteString>()
    private let handler: Handler?

    package init(handler: Handler? = nil) {
        self.handler = handler
    }

    package func hash(_ hash: ByteString) -> ByteString {
        if let handler = self.handler {
            return handler(hash)
        } else {
            self.hashes.append(hash)
            return ByteString(hash.contents.reversed())
        }
    }
}

extension MockHashAlgorithm: HashAlgorithm {}
