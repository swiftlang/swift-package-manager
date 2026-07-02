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
    /// 1. The `proto=` parameter of a standards-compliant `Forwarded`
    ///    header ([RFC 7239]).
    /// 2. The `X-Forwarded-Proto` header set by common reverse proxies.
    /// 3. `https` if the application has a TLS configuration, otherwise
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
        if let value = headers.first(name: "X-Forwarded-Proto"),
           let first = value.split(separator: ",").first {
            let trimmed = first.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed.lowercased() }
        }
        guard let forwarded = headers.first(name: "Forwarded") else { return nil }
        for rawEntry in forwarded.split(separator: ",") {
            for rawParam in rawEntry.split(separator: ";") {
                let param = rawParam.trimmingCharacters(in: .whitespaces)
                guard param.lowercased().hasPrefix("proto=") else { continue }
                var value = String(param.dropFirst("proto=".count))
                if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                return value.lowercased()
            }
        }
        return nil
    }
}
