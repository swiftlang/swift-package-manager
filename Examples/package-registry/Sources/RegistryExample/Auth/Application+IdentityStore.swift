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

extension Application {
    private struct IdentityStoreKey: StorageKey, Sendable {
        typealias Value = IdentityStore
    }

    /// The ``IdentityStore`` associated with this `Application`.
    ///
    /// Created on first access during single-threaded boot and cached in
    /// application storage, so every endpoint that resolves or lists
    /// identities shares one store for the lifetime of the process.
    /// Mirrors ``userStore``.
    public var identityStore: IdentityStore {
        if let existing = storage[IdentityStoreKey.self] {
            return existing
        }
        let store = IdentityStore()
        storage[IdentityStoreKey.self] = store
        return store
    }
}