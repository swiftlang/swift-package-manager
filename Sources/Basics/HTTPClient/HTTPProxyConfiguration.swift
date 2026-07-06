//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

/// Configuration for HTTP/HTTPS proxy routing.
///
/// This struct represents the contents of a `proxy.json` configuration file
/// used by Swift Package Manager to route HTTP traffic through proxy servers.
public struct HTTPProxyConfiguration: Codable, Equatable, Sendable {
    /// Schema version. Must be `1`.
    public var version: Int

    /// Proxy settings for HTTP requests.
    public var http: ProtocolProxy?

    /// Proxy settings for HTTPS requests.
    public var https: ProtocolProxy?

    /// Hosts and patterns that should bypass the proxy.
    public var noProxy: [String]?

    /// Proxy settings for a single protocol.
    public struct ProtocolProxy: Codable, Equatable, Sendable {
        /// The proxy URL (scheme://host[:port]).
        public var proxy: String

        public init(proxy: String) {
            self.proxy = proxy
        }
    }

    public init(version: Int = 1, http: ProtocolProxy? = nil, https: ProtocolProxy? = nil, noProxy: [String]? = nil) {
        self.version = version
        self.http = http
        self.https = https
        self.noProxy = noProxy
    }

    /// Returns `true` if the configuration has no meaningful proxy settings.
    public var isEmpty: Bool {
        http == nil && https == nil && (noProxy == nil || noProxy!.isEmpty)
    }
}

// MARK: - Validation

extension HTTPProxyConfiguration {
    /// Errors that can occur when validating proxy configuration.
    public enum ValidationError: Error, CustomStringConvertible, Equatable {
        case unsupportedVersion(Int)
        case invalidProxyURL(String, reason: String)
        case credentialsInProxyURL(String)

        public var description: String {
            switch self {
            case .unsupportedVersion(let version):
                return "unsupported proxy configuration version \(version), expected 1"
            case .invalidProxyURL(let url, let reason):
                return "invalid proxy URL '\(url)': \(reason)"
            case .credentialsInProxyURL(let url):
                return "proxy URL '\(url)' must not contain credentials; authenticated proxy support is not yet available"
            }
        }
    }

    /// Validates the proxy configuration, throwing an error if invalid.
    public func validate() throws {
        if version != 1 {
            throw ValidationError.unsupportedVersion(version)
        }
        if let http {
            try Self.validateProxyURL(http.proxy)
        }
        if let https {
            try Self.validateProxyURL(https.proxy)
        }
    }

    /// Validates a proxy URL string.
    ///
    /// Requirements:
    /// - Must be a valid URL with a scheme and host
    /// - Must not contain credentials (userinfo)
    /// - Supported schemes: http, https, socks5
    static func validateProxyURL(_ urlString: String) throws {
        guard let components = URLComponents(string: urlString) else {
            throw ValidationError.invalidProxyURL(urlString, reason: "not a valid URL")
        }

        // Check for credentials
        if components.user != nil || components.password != nil {
            throw ValidationError.credentialsInProxyURL(urlString)
        }

        // Check for scheme
        guard let scheme = components.scheme?.lowercased() else {
            throw ValidationError.invalidProxyURL(urlString, reason: "missing scheme")
        }

        // Check for supported scheme
        let supportedSchemes = ["http", "https", "socks5"]
        guard supportedSchemes.contains(scheme) else {
            throw ValidationError.invalidProxyURL(urlString, reason: "unsupported scheme '\(scheme)', expected one of: \(supportedSchemes.joined(separator: ", "))")
        }

        // Check for host
        guard let host = components.host, !host.isEmpty else {
            throw ValidationError.invalidProxyURL(urlString, reason: "missing host")
        }
    }
}

// MARK: - noProxy matching

extension HTTPProxyConfiguration {
    /// Determines whether the given host should bypass the proxy based on the `noProxy` patterns.
    ///
    /// Matching rules:
    /// - `*` matches all hosts
    /// - `example.com` matches exactly `example.com` and all subdomains
    /// - `.example.com` matches subdomains of `example.com` but NOT `example.com` itself
    /// - IP addresses are matched exactly
    /// - Matching is case-insensitive
    ///
    /// - Parameter host: The target hostname to check.
    /// - Returns: `true` if the host should bypass the proxy (go direct).
    public func shouldBypassProxy(for host: String) -> Bool {
        guard let noProxy, !noProxy.isEmpty else {
            return false
        }

        let lowercasedHost = host.lowercased()

        for pattern in noProxy {
            let lowercasedPattern = pattern.lowercased().trimmingCharacters(in: .whitespaces)

            // Wildcard matches everything
            if lowercasedPattern == "*" {
                return true
            }

            // Leading dot: match subdomains only, not the base domain itself
            if lowercasedPattern.hasPrefix(".") {
                let suffix = lowercasedPattern // e.g. ".example.com"
                if lowercasedHost.hasSuffix(suffix) {
                    return true
                }
                continue
            }

            // Exact match
            if lowercasedHost == lowercasedPattern {
                return true
            }

            // Subdomain match: pattern "example.com" matches "sub.example.com"
            if lowercasedHost.hasSuffix(".\(lowercasedPattern)") {
                return true
            }
        }

        return false
    }

    /// Returns the proxy URL to use for the given request URL, or `nil` if the request should go direct.
    ///
    /// - Parameter url: The target URL being requested.
    /// - Returns: The proxy URL string if a proxy should be used, `nil` otherwise.
    public func proxyURL(for url: URL) -> String? {
        // Check if the host is in the noProxy list
        if let host = url.host, shouldBypassProxy(for: host) {
            return nil
        }

        // Determine which proxy to use based on the URL scheme
        switch url.scheme?.lowercased() {
        case "http":
            return http?.proxy
        case "https":
            return https?.proxy
        default:
            return nil
        }
    }
}

// MARK: - Parsed proxy URL components

extension HTTPProxyConfiguration {
    /// Parsed components of a proxy URL for use in URLSession configuration.
    public struct ParsedProxyURL: Equatable, Sendable {
        public let scheme: String
        public let host: String
        public let port: Int

        /// Default ports per scheme.
        public static func defaultPort(for scheme: String) -> Int {
            switch scheme.lowercased() {
            case "http": return 80
            case "https": return 443
            case "socks5": return 1080
            default: return 80
            }
        }
    }

    /// Parses a proxy URL string into its components.
    ///
    /// - Parameter urlString: The proxy URL string.
    /// - Returns: Parsed proxy URL components.
    /// - Throws: `ValidationError` if the URL is invalid.
    public static func parseProxyURL(_ urlString: String) throws -> ParsedProxyURL {
        guard let components = URLComponents(string: urlString),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty
        else {
            throw ValidationError.invalidProxyURL(urlString, reason: "not a valid URL")
        }

        let port = components.port ?? ParsedProxyURL.defaultPort(for: scheme)
        return ParsedProxyURL(scheme: scheme, host: host, port: port)
    }
}
