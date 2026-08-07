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

import Vapor

/// Verifies a plaintext password against a stored bcrypt hash.
///
/// The lone verification seam on the Basic path. Extracting it — mirroring
/// ``TokenGenerator`` — lets a test substitute a recording double to assert
/// the path performs exactly one verification regardless of account
/// existence, the invariant behind its constant-time guarantee.
public struct PasswordVerifier: Sendable {
    private let perform: @Sendable (String, String) async -> Bool

    /// Creates a verifier backed by `perform`.
    ///
    /// - Parameter perform: A `@Sendable` closure returning whether the
    ///   password (first argument) verifies against the hash (second).
    public init(_ perform: @escaping @Sendable (String, String) async -> Bool) {
        self.perform = perform
    }

    /// Returns whether `password` verifies against `hash`.
    func verify(_ password: String, against hash: String) async -> Bool {
        await perform(password, hash)
    }

    /// Verifies with bcrypt on the shared thread pool so its CPU cost never
    /// blocks the event loop. A rejected or malformed hash — anything bcrypt
    /// throws on — is treated as a failed verification.
    public static let bcrypt = PasswordVerifier { password, hash in
        let result = try? await NIOThreadPool.singleton.runIfActive {
            try Bcrypt.verify(password, created: hash)
        }
        return result ?? false
    }
}
