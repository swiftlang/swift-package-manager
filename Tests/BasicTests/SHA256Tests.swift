/*
This source file is part of the Swift.org open source project

Copyright 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

class SHA256Tests: XCTestCase {

    func testBasics() throws {
        let knownHashes = [
            "": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            "The quick brown fox jumps over the lazy dog": "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592",
            "@#$%^&*&^%$#$%^&*()&^%$#$%^&*()@#$%^&*()": "8abeb32e2aed588be8fc73e995c79ee535651bc9642faf03fb6f111d270e9e2e",
            "Hello!": "334d016f755cd6dc58c53a86e183882f8ec14f52fb05345887c8a5edd42c87b7",
            "तुमसे न हो पाएगा": "bcd3be1284e4d5ef65de89a6203f174fbc4f6bafb376a5e62d36afd3cf93427f",
        ]

        // Test known hashes.
        for (input, hash) in knownHashes {
            XCTAssertEqual(SHA256(input).digestString(), hash, "Incorrect value for \(input)")
        }

        // Test a big input.
        let byte = "f"
        let stream = BufferedOutputByteStream()
        for _ in 0..<20000 {
            stream <<< byte
        }
        XCTAssertEqual(SHA256(stream.bytes).digestString(), "23d00697ba26b4140869bab958431251e7e41982794d41b605b6a1d5dee56abf")
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
