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

/// The redirect logic is hand-rolled because ``RegistryNIOHTTPClient`` is a custom HTTP client implementation
struct RegistryHTTPRedirectFollower: Sendable {
    typealias Perform = @Sendable (HTTPClientRequest, HTTPClient.ProgressHandler?) async throws -> HTTPClientResponse

    // Redirect up to 5 times
    static let maximumHops = 5

    private static let redirectStatusCodes: Set<Int> = [301, 302, 303, 307, 308]
    private static let credentialHeaders: Set<String> = ["authorization", "proxy-authorization", "cookie"]

    private let maximumHops: Int
    private let perform: Perform

    init(maximumHops: Int = Self.maximumHops, perform: @escaping Perform) {
        self.maximumHops = maximumHops
        self.perform = perform
    }

    func execute(
        _ request: HTTPClientRequest,
        progress: HTTPClient.ProgressHandler?
    ) async throws -> HTTPClientResponse {
        try await self.execute(request, from: request.url, progress: progress, hopsRemaining: self.maximumHops)
    }

    private func execute(
        _ request: HTTPClientRequest,
        from origin: URL,
        progress: HTTPClient.ProgressHandler?,
        hopsRemaining: Int
    ) async throws -> HTTPClientResponse {
        let response = try await self.perform(request, progress)

        guard let destination = Self.destination(of: response, from: request.url) else {
            return response
        }
        guard hopsRemaining > 0 else {
            throw RegistryHTTPTransportError.tooManyRedirects(origin.absoluteString)
        }

        return try await self.execute(
            Self.redirecting(request, to: destination, statusCode: response.statusCode),
            from: origin,
            progress: progress,
            hopsRemaining: hopsRemaining - 1
        )
    }

    private static func destination(of response: HTTPClientResponse, from url: URL) -> URL? {
        guard Self.redirectStatusCodes.contains(response.statusCode),
              let location = response.headers.get("Location").first
        else {
            return nil
        }
        return URL(string: location, relativeTo: url)?.absoluteURL
    }

    private static func redirecting(
        _ request: HTTPClientRequest,
        to destination: URL,
        statusCode: Int
    ) -> HTTPClientRequest {
        let headers = Self.headers(of: request, redirectedTo: destination)

        guard Self.convertsToGet(statusCode: statusCode, method: request.method),
              case .generic = request.kind
        else {
            return HTTPClientRequest(
                kind: request.kind,
                url: destination,
                headers: headers,
                body: request.body,
                options: request.options
            )
        }

        return HTTPClientRequest(
            kind: .generic(.get),
            url: destination,
            headers: headers,
            body: nil,
            options: request.options
        )
    }

    private static func convertsToGet(statusCode: Int, method: HTTPMethod) -> Bool {
        switch statusCode {
        case 303:
            guard case .head = method else { return true }
            return false
        case 301, 302:
            guard case .post = method else { return false }
            return true
        default:
            return false
        }
    }

    private static func headers(of request: HTTPClientRequest, redirectedTo destination: URL) -> HTTPClientHeaders {
        guard request.url.hasSameOrigin(as: destination) else {
            return HTTPClientHeaders(
                request.headers.filter { !Self.credentialHeaders.contains($0.name.lowercased()) }
            )
        }

        var headers = HTTPClientHeaders(
            request.headers.filter { $0.name.lowercased() != "authorization" }
        )
        guard let authorization = request.options.authorizationProvider?(destination), !authorization.isEmpty else {
            return headers
        }
        headers.add(name: "Authorization", value: authorization)
        return headers
    }
}
