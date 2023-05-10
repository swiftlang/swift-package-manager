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

import Basics
import XCTest

import struct TSCBasic.ByteString

final class ByteStringExtensionsTests: XCTestCase {
    func testSHA256Checksum() {
        let byteString = ByteString(encodingAsUTF8: "abc")
        XCTAssertEqual(byteString.contents, [0x61, 0x62, 0x63])

        // See https://csrc.nist.gov/csrc/media/projects/cryptographic-standards-and-guidelines/documents/examples/sha_all.pdf
        XCTAssertEqual(byteString.sha256Checksum, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
