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
    private struct ClientStoreKey: StorageKey, Sendable {
        typealias Value = ClientStore
    }

    /// The ``ClientStore`` associated with this `Application`.
    ///
    /// Created on first access during single-threaded boot and cached in
    /// application storage, so every endpoint that resolves or lists
    /// clients shares one store for the lifetime of the process.
    /// Mirrors ``userStore``.
    public var clientStore: ClientStore {
        if let existing = storage[ClientStoreKey.self] {
            return existing
        }
        let store = ClientStore()
        storage[ClientStoreKey.self] = store
        return store
    }
}