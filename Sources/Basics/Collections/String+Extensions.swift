//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct TSCBasic.SHA256

extension String {
    /// generated for the byte string's contents.
    ///
    /// This property uses the CryptoKit implementation of
    /// Secure Hashing Algorithm 2 (SHA-2) hashing with a 256-bit digest, when available,
    /// falling back on a native implementation in Swift provided by TSCBasic.
    public var sha256Checksum: String {
        SHA256().hash(self).hexadecimalRepresentation
    }

    /// Drops the given suffix from the string, if present.
    public func spm_dropPrefix(_ prefix: String) -> String {
        if self.hasPrefix(prefix) {
            return String(self.dropFirst(prefix.count))
        }
        return self
    }

    public var isValidIdentifier: Bool {
        guard !isEmpty else { return false }
        return allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
