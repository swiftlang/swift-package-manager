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

import struct TSCBasic.ByteString
import struct TSCBasic.SHA256

extension ByteString {
    /// A lowercase, hexadecimal representation of the SHA256 hash
    /// generated for the byte string's contents.
    ///
    /// This property uses the CryptoKit implementation of
    /// Secure Hashing Algorithm 2 (SHA-2) hashing with a 256-bit digest, when available,
    /// falling back on a native implementation in Swift provided by TSCBasic.
    public var sha256Checksum: String {
        SHA256().hash(self).hexadecimalRepresentation
    }

    public init(json: SerializedJSON) {
        self.init(json.underlying.utf8)
    }
}
