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

import Basics
import Foundation
import PackageModel
import PackageRegistry

import struct TSCUtility.Version

/// A source of advisories published by a package registry.
public protocol RegistryAdvisoryProvider: Sendable {
    /// Returns the advisories for a release, or `nil` when the registry does not support advisories.
    func advisories(for identity: PackageIdentity, version: Version) async throws -> [OSVRecord]?
}

/// Reads advisories from a registry's `advisories` endpoint.
///
/// `RegistryClient` is not declared `Sendable`. Sharing it across tasks is safe here because it is only used through
/// its async API, which synchronizes access to the client's mutable state internally.
public struct RegistryAdvisorySource: RegistryAdvisoryProvider, @unchecked Sendable {
    private struct Response: Decodable {
        let advisories: [OSVRecord]
    }

    private let client: RegistryClient
    private let observabilityScope: ObservabilityScope

    public init(client: RegistryClient, observabilityScope: ObservabilityScope) {
        self.client = client
        self.observabilityScope = observabilityScope
    }

    public func advisories(for identity: PackageIdentity, version: Version) async throws -> [OSVRecord]? {
        do {
            switch try await self.client.getPackageAdvisories(
                package: identity,
                version: version,
                observabilityScope: self.observabilityScope
            ) {
            case .unsupported:
                return nil
            case .supported(let body):
                return try JSONDecoder().decode(Response.self, from: body).advisories
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AuditError.advisorySourceFailed(
                source: "registry",
                package: identity.description,
                underlying: "\(error)"
            )
        }
    }
}
