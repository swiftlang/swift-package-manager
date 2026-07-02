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

/// A normalized, syntactically-validated email address used as the sole
/// identity of a registry ``User``.
///
/// Construction goes through a single failable initializer that trims
/// surrounding whitespace, applies Unicode canonical (NFC) composition,
/// and lowercases the address with `String.lowercased()` (locale-independent
/// Unicode case mapping). Because both registration and login funnel raw
/// input through the same initializer, two spellings that normalize to the
/// same value (for example `"Mona@Example.com"` and `" mona@example.com "`)
/// collapse to one identity — so a user always logs in with whatever casing
/// they registered.
///
/// The validation is intentionally lightweight, matching the "reference
/// example" scope of this server: the address must contain exactly one
/// `@`, a non-empty local part, and a domain that contains a `.` and
/// neither begins nor ends with one. It is not a full RFC 5322 parser.
public struct EmailAddress: Hashable, Sendable {
    /// The normalized address (trimmed, NFC-composed, lowercased).
    public let value: String

    /// Creates a normalized email address, or `nil` if `raw` is not a
    /// syntactically valid address once normalized.
    ///
    /// - Parameter raw: The address exactly as supplied by the client.
    public init?(_ raw: String) {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
        guard EmailAddress.isValid(normalized) else { return nil }
        self.value = normalized
    }

    private static func isValid(_ candidate: String) -> Bool {
        guard !candidate.isEmpty, !candidate.contains(where: \.isWhitespace) else {
            return false
        }
        let parts = candidate.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let local = parts[0]
        let domain = parts[1]
        guard !local.isEmpty, !domain.isEmpty, domain.contains(".") else { return false }
        return !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }
}
