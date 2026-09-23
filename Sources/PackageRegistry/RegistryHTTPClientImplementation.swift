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

import Basics
import Foundation
import NIOSSL

struct RegistryHTTPClientImplementation: Sendable {
    typealias MutualTLS = @Sendable (
        HTTPClientRequest,
        TLSConfiguration,
        HTTPClient.ProgressHandler?
    ) async throws -> HTTPClientResponse

    private let identities: RegistryClientIdentityLookup
    private let fileSystem: FileSystem
    private let mutualTLS: MutualTLS
    private let fallback: HTTPClient.Implementation

    init(
        identities: RegistryClientIdentityLookup,
        fileSystem: FileSystem,
        mutualTLS: @escaping MutualTLS = RegistryHTTPClientImplementation.nioTransport,
        fallback: @escaping HTTPClient.Implementation
    ) {
        self.identities = identities
        self.fileSystem = fileSystem
        self.mutualTLS = mutualTLS
        self.fallback = fallback
    }

    @Sendable
    func execute(
        _ request: HTTPClientRequest,
        progress: HTTPClient.ProgressHandler?
    ) async throws -> HTTPClientResponse {
        let follower = RegistryHTTPRedirectFollower { hop, hopProgress in
            try await self.exchange(hop, progress: hopProgress)
        }

        return try await follower.execute(request, progress: progress)
    }

    private func exchange(
        _ request: HTTPClientRequest,
        progress: HTTPClient.ProgressHandler?
    ) async throws -> HTTPClientResponse {
        guard let identity = self.identities.identity(for: request.url) else {
            return try await self.fallback(request, progress)
        }

        let tlsConfiguration = try RegistryClientIdentityResolver(fileSystem: self.fileSystem)
            .resolve(identity)
            .makeTLSConfiguration()

        return try await self.mutualTLS(request, tlsConfiguration, progress)
    }

    @Sendable
    private static func nioTransport(
        _ request: HTTPClientRequest,
        tlsConfiguration: TLSConfiguration,
        progress: HTTPClient.ProgressHandler?
    ) async throws -> HTTPClientResponse {
        try await RegistryNIOHTTPClient().execute(
            request,
            tlsConfiguration: tlsConfiguration,
            progress: progress
        )
    }
}
