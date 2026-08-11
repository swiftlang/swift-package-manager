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
    private struct UserStoreKey: StorageKey, Sendable {
        typealias Value = UserStore
    }

    /// The ``UserStore`` associated with this `Application`.
    ///
    /// Created on first access during single-threaded boot (``configure``
    /// touches it while wiring the auth routes) and cached in application
    /// storage, so the registration and login endpoints share one store
    /// for the lifetime of the process. Mirrors ``registryStore``.
    public var userStore: UserStore {
        if let existing = storage[UserStoreKey.self] {
            return existing
        }
        let store = UserStore()
        storage[UserStoreKey.self] = store
        return store
    }
}
