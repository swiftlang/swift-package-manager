//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

struct RegistryClientIdentityLookup: Sendable {
    private let identities: [String: RegistryConfiguration.Identity]

    init(configuration: RegistryConfiguration) {
        self.identities = configuration.registryAuthentication.compactMapValues(\.identity)
    }

    var isEmpty: Bool {
        self.identities.isEmpty
    }

    func identity(for url: URL) -> RegistryConfiguration.Identity? {
        guard let key = try? RegistryConfiguration.authenticationStorageKey(for: url) else {
            return .none
        }
        return self.identities[key]
    }
}
