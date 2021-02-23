/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import TSCBasic

public class MockHashAlgorithm: HashAlgorithm {
    public typealias Hash = (ByteString) -> ByteString

    public private(set) var hashes = ThreadSafeArrayStore<ByteString>()
    private var hashFunction: Hash!

    public init(hash: Hash? = nil) {
        self.hashFunction = hash ?? { hash in
            self.hashes.append(hash)
            return ByteString(hash.contents.reversed())
        }
    }

    public func hash(_ bytes: ByteString) -> ByteString {
        return self.hashFunction(bytes)
    }
}
