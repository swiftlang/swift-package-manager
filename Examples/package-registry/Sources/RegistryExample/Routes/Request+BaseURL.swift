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

extension Request {
    /// The base URL (`scheme://host`) to use when constructing absolute
    /// URLs in response bodies and `Link` / `Location` headers.
    ///
    /// The scheme is resolved, in order, from:
    ///
    /// 1. The `proto=` parameter of a forwarding header — either the
    ///    standards-compliant `Forwarded` header ([RFC 7239]) or the
    ///    deprecated `X-Forwarded-Proto` header set by common reverse
    ///    proxies, as parsed by Vapor's `HTTPHeaders.forwarded`.
    /// 2. `https` if the application has a TLS configuration, otherwise
    ///    `http`.
    ///
    /// The host comes from the request's `Host` header, falling back to
    /// `localhost` when absent.
    ///
    /// [RFC 7239]: https://www.rfc-editor.org/rfc/rfc7239
    var baseURL: String {
        let host = headers.first(name: .host) ?? "localhost"
        return "\(effectiveScheme)://\(host)"
    }

    private var effectiveScheme: String {
        if let forwarded = forwardedProto { return forwarded }
        if application.http.server.configuration.tlsConfiguration != nil {
            return "https"
        }
        return "http"
    }

    private var forwardedProto: String? {
        headers.forwarded.compactMap(\.proto).first?.lowercased()
    }
}
