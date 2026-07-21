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

@Suite("TokenHasher")
struct TokenHasherTests {
    @Test func `matches the known SHA-256 vector for the empty string`() {
        #expect(TokenHasher.hash("").value == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test func `is deterministic`() {
        #expect(TokenHasher.hash("swift-token") == TokenHasher.hash("swift-token"))
    }

    @Test func `distinct inputs produce distinct hashes`() {
        #expect(TokenHasher.hash("token-a") != TokenHasher.hash("token-b"))
    }

    @Test func `emits 64 lowercase hex characters`() {
        let hash = TokenHasher.hash("anything").value
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }
}

@Suite("TokenGenerator")
struct TokenGeneratorTests {
    @Test func `injected generator returns its fixed token`() {
        let generator = TokenGenerator { "fixed-token" }
        #expect(generator.makeToken() == "fixed-token")
    }

    @Test func `secureRandom yields a distinct token each call`() {
        #expect(TokenGenerator.secureRandom.makeToken() != TokenGenerator.secureRandom.makeToken())
    }

    @Test func `secureRandom tokens are long and URL-safe`() {
        let token = TokenGenerator.secureRandom.makeToken()
        #expect(token.count >= 40)
        #expect(!token.contains("+"))
        #expect(!token.contains("/"))
        #expect(!token.contains("="))
    }
}
