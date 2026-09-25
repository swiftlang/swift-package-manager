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
import NIOHTTP1

/// The encoding is hand-rolled because ``RegistryNIOHTTPClient`` is a custom HTTP client implementation
enum RegistryHTTPRequestEncoding {
    static func head(for request: HTTPClientRequest) throws -> HTTPRequestHead {
        let target = try RequestTarget(url: request.url)

        var headers = HTTPHeaders()
        for item in request.headers {
            headers.add(name: item.name, value: item.value)
        }
        if !headers.contains(name: "Host") {
            headers.add(name: "Host", value: target.hostHeader)
        }
        if let length = Self.contentLength(for: request), !headers.contains(name: "Content-Length") {
            headers.add(name: "Content-Length", value: "\(length)")
        }

        return HTTPRequestHead(
            version: .http1_1,
            method: Self.method(request.method),
            uri: target.uri,
            headers: headers
        )
    }

    private static func contentLength(for request: HTTPClientRequest) -> Int? {
        if let body = request.body { return body.count }

        switch request.method {
        case .post, .put: return 0
        case .head, .get, .delete: return .none
        }
    }

    private static func method(_ method: Basics.HTTPMethod) -> NIOHTTP1.HTTPMethod {
        switch method {
        case .head: return .HEAD
        case .get: return .GET
        case .post: return .POST
        case .put: return .PUT
        case .delete: return .DELETE
        }
    }
}

struct RequestTarget {
    let host: String
    let port: Int
    let uri: String

    private let headerHost: String

    init(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host,
              let scheme = components.scheme?.lowercased()
        else {
            throw RegistryHTTPTransportError.unsupportedURL(url.absoluteString)
        }

        guard scheme == "https" else {
            throw RegistryHTTPTransportError.unsupportedScheme(url.absoluteString)
        }

        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        self.headerHost = host
        self.host = Self.unbracketed(host)
        self.port = components.port ?? 443
        self.uri = components.percentEncodedQuery.map { "\(path)?\($0)" } ?? path
    }

    var hostHeader: String {
        self.port == 443 ? self.headerHost : "\(self.headerHost):\(self.port)"
    }

    private static func unbracketed(_ host: String) -> String {
        guard host.hasPrefix("["), host.hasSuffix("]") else { return host }
        return String(host.dropFirst().dropLast())
    }
}
