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

import Foundation

/// Produces the plaintext bearer tokens minted for token users.
public struct TokenGenerator: Sendable {
    private let generate: @Sendable () -> String

    /// Creates a generator backed by `generate`.
    ///
    /// - Parameter generate: A `@Sendable` closure returning a fresh token
    ///   on each call.
    public init(_ generate: @escaping @Sendable () -> String) {
        self.generate = generate
    }

    /// Returns a freshly generated plaintext token.
    public func makeToken() -> String {
        generate()
    }

    /// A cryptographically secure generator producing 256-bit,
    /// URL-safe base64 tokens from the system random number generator.
    public static let secureRandom = TokenGenerator {
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        return Data(bytes).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
