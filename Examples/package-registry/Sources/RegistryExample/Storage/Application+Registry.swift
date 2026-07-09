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
    private struct RegistryStoreKey: StorageKey, Sendable {
        typealias Value = RegistryStore
    }

    /// The ``RegistryStore`` associated with this `Application`.
    ///
    /// The store is lazily created on first access and cached in the
    /// application's storage, so every call within the same process
    /// returns the same actor instance. Route handlers and tests read
    /// this property to obtain the shared in-memory backing store for
    /// all package registry endpoints.
    public var registryStore: RegistryStore {
        if let existing = storage[RegistryStoreKey.self] {
            return existing
        }
        let store = RegistryStore()
        storage[RegistryStoreKey.self] = store
        return store
    }
}
