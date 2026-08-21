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

/// Produces the ``ClientID``s minted for newly registered clients.
///
/// Mirrors ``TokenGenerator``, and differs from it in exactly the way an id
/// differs from a token: ids are public names that need only be unique, so a
/// UUID suffices where a credential demands the system CSPRNG.
public struct ClientIDGenerator: Sendable {
    private let generate: @Sendable () -> ClientID

    /// Creates a generator backed by `generate`.
    ///
    /// - Parameter generate: A `@Sendable` closure returning a fresh id on each
    ///   call.
    public init(_ generate: @escaping @Sendable () -> ClientID) {
        self.generate = generate
    }

    /// Returns a freshly generated id.
    public func makeID() -> ClientID {
        generate()
    }

    /// A generator producing random UUID ids; tests inject a fixed sequence
    /// instead.
    public static let random = ClientIDGenerator { ClientID(UUID().uuidString) }
}
