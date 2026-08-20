//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Testing
@testable import RegistryExample

@Suite("EmailAddress normalization and validation")
struct EmailAddressTests {
    @Test func `lowercases and trims surrounding whitespace`() {
        #expect(EmailAddress("  Mona@Example.COM ")?.value == "mona@example.com")
    }

    @Test func `equal spellings normalize to the same value`() {
        #expect(EmailAddress("Mona@Example.com") == EmailAddress(" mona@example.com "))
    }

    @Test func `canonically composes decomposed unicode`() {
        let composed = EmailAddress("m\u{00F6}na@example.com")
        let decomposed = EmailAddress("mo\u{0308}na@example.com")
        #expect(composed == decomposed)
    }

    @Test func `accepts a conventional address`() {
        #expect(EmailAddress("a.b+tag@sub.example.com")?.value == "a.b+tag@sub.example.com")
    }

    @Test(arguments: [
        "",
        "   ",
        "no-at-sign.com",
        "@example.com",
        "local@",
        "local@nodot",
        "local@.example.com",
        "local@example.com.",
        "two@@example.com",
        "inner space@example.com",
    ])
    func `rejects invalid addresses`(raw: String) {
        #expect(EmailAddress(raw) == nil)
    }
}
