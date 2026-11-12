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

/// If any registry supports mTLS, an `HTTPClient` is returned that supports mTLS
/// Else, the default `HTTPClient` is returned
enum RegistryHTTPClientProvider {
    static func makeHTTPClient(
        configuration: RegistryConfiguration,
        httpClientConfiguration: HTTPClientConfiguration,
        fileSystem: FileSystem
    ) -> HTTPClient {
        // Get all identities in the registry configuration
        // `RegistryHTTPClientImplementation` knows the registry URL the user cares about
        // It filters the `identities` list and finds the one identity associated with the given registry URL
        let identities = RegistryClientIdentityLookup(configuration: configuration)
        guard !identities.isEmpty else {
            return HTTPClient(configuration: httpClientConfiguration)
        }

        let defaultTransport = HTTPClient()
        let implementation = RegistryHTTPClientImplementation(
            identities: identities,
            fileSystem: fileSystem,
            fallback: { request, progress in
                try await defaultTransport.execute(Self.withoutWrapperStrategies(request), progress: progress)
            }
        )

        return HTTPClient(configuration: httpClientConfiguration, implementation: implementation.execute)
    }

    /// Strips the client of wrapper logic because the caller of ``makeHTTPClient`` adds this already
    private static func withoutWrapperStrategies(_ request: HTTPClientRequest) -> HTTPClientRequest {
        var unwrapped = request
        unwrapped.options.retryStrategy = .none
        unwrapped.options.circuitBreakerStrategy = .none
        unwrapped.options.validResponseCodes = .none
        return unwrapped
    }
}
