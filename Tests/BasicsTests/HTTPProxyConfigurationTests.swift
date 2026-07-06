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
import XCTest

@testable import Basics

final class HTTPProxyConfigurationTests: XCTestCase {

    // MARK: - JSON Parsing

    func testDecodeFullConfiguration() throws {
        let json = """
        {
            "version": 1,
            "http": { "proxy": "http://proxy.example.com:8080" },
            "https": { "proxy": "http://proxy.example.com:8443" },
            "noProxy": ["localhost", "127.0.0.1", ".internal.corp"]
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(HTTPProxyConfiguration.self, from: data)

        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.http?.proxy, "http://proxy.example.com:8080")
        XCTAssertEqual(config.https?.proxy, "http://proxy.example.com:8443")
        XCTAssertEqual(config.noProxy, ["localhost", "127.0.0.1", ".internal.corp"])
    }

    func testDecodeHTTPOnly() throws {
        let json = """
        {
            "version": 1,
            "http": { "proxy": "http://proxy:3128" }
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(HTTPProxyConfiguration.self, from: data)

        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.http?.proxy, "http://proxy:3128")
        XCTAssertNil(config.https)
        XCTAssertNil(config.noProxy)
    }

    func testDecodeEmptyConfig() throws {
        let json = """
        { "version": 1 }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(HTTPProxyConfiguration.self, from: data)

        XCTAssertEqual(config.version, 1)
        XCTAssertNil(config.http)
        XCTAssertNil(config.https)
        XCTAssertNil(config.noProxy)
        XCTAssertTrue(config.isEmpty)
    }

    func testRoundTrip() throws {
        let config = HTTPProxyConfiguration(
            version: 1,
            http: .init(proxy: "http://proxy:8080"),
            https: .init(proxy: "http://proxy:8443"),
            noProxy: ["localhost", "*.local"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        let decoded = try JSONDecoder().decode(HTTPProxyConfiguration.self, from: data)

        XCTAssertEqual(config, decoded)
    }

    // MARK: - Validation

    func testValidateAcceptsValidConfig() throws {
        let config = HTTPProxyConfiguration(
            version: 1,
            http: .init(proxy: "http://proxy.example.com:8080"),
            https: .init(proxy: "https://secure-proxy.example.com:443")
        )
        XCTAssertNoThrow(try config.validate())
    }

    func testValidateRejectsUnsupportedVersion() {
        let config = HTTPProxyConfiguration(version: 2)
        XCTAssertThrowsError(try config.validate()) { error in
            guard let validationError = error as? HTTPProxyConfiguration.ValidationError else {
                return XCTFail("Expected ValidationError, got \(error)")
            }
            XCTAssertEqual(validationError, .unsupportedVersion(2))
        }
    }

    func testValidateRejectsCredentialsInURL() {
        let config = HTTPProxyConfiguration(
            version: 1,
            http: .init(proxy: "http://user:pass@proxy:8080")
        )
        XCTAssertThrowsError(try config.validate()) { error in
            guard let validationError = error as? HTTPProxyConfiguration.ValidationError else {
                return XCTFail("Expected ValidationError, got \(error)")
            }
            XCTAssertEqual(validationError, .credentialsInProxyURL("http://user:pass@proxy:8080"))
        }
    }

    func testValidateRejectsMissingScheme() {
        XCTAssertThrowsError(try HTTPProxyConfiguration.validateProxyURL("proxy.example.com:8080")) { error in
            guard let validationError = error as? HTTPProxyConfiguration.ValidationError else {
                return XCTFail("Expected ValidationError, got \(error)")
            }
            if case .invalidProxyURL(_, let reason) = validationError {
                XCTAssertTrue(reason.contains("scheme"), "Expected reason about scheme, got: \(reason)")
            } else {
                XCTFail("Expected invalidProxyURL error")
            }
        }
    }

    func testValidateRejectsUnsupportedScheme() {
        XCTAssertThrowsError(try HTTPProxyConfiguration.validateProxyURL("ftp://proxy:21")) { error in
            guard let validationError = error as? HTTPProxyConfiguration.ValidationError else {
                return XCTFail("Expected ValidationError, got \(error)")
            }
            if case .invalidProxyURL(_, let reason) = validationError {
                XCTAssertTrue(reason.contains("unsupported scheme"), "Expected unsupported scheme, got: \(reason)")
            } else {
                XCTFail("Expected invalidProxyURL error")
            }
        }
    }

    func testValidateRejectsMissingHost() {
        XCTAssertThrowsError(try HTTPProxyConfiguration.validateProxyURL("http://")) { error in
            guard let validationError = error as? HTTPProxyConfiguration.ValidationError else {
                return XCTFail("Expected ValidationError, got \(error)")
            }
            if case .invalidProxyURL(_, let reason) = validationError {
                XCTAssertTrue(reason.contains("host"), "Expected reason about host, got: \(reason)")
            } else {
                XCTFail("Expected invalidProxyURL error")
            }
        }
    }

    func testValidateAcceptsSocks5() throws {
        XCTAssertNoThrow(try HTTPProxyConfiguration.validateProxyURL("socks5://proxy:1080"))
    }

    func testValidateAcceptsHTTPS() throws {
        XCTAssertNoThrow(try HTTPProxyConfiguration.validateProxyURL("https://secure-proxy:443"))
    }

    // MARK: - noProxy Matching

    func testNoProxyExactMatch() {
        let config = HTTPProxyConfiguration(
            version: 1,
            noProxy: ["example.com"]
        )
        XCTAssertTrue(config.shouldBypassProxy(for: "example.com"))
        XCTAssertFalse(config.shouldBypassProxy(for: "other.com"))
    }

    func testNoProxySubdomainMatch() {
        let config = HTTPProxyConfiguration(
            version: 1,
            noProxy: ["example.com"]
        )
        // "example.com" pattern matches exact and subdomains
        XCTAssertTrue(config.shouldBypassProxy(for: "example.com"))
        XCTAssertTrue(config.shouldBypassProxy(for: "sub.example.com"))
        XCTAssertTrue(config.shouldBypassProxy(for: "deep.sub.example.com"))
        XCTAssertFalse(config.shouldBypassProxy(for: "notexample.com"))
    }

    func testNoProxyLeadingDot() {
        let config = HTTPProxyConfiguration(
            version: 1,
            noProxy: [".example.com"]
        )
        // Leading dot matches subdomains only, NOT the base domain
        XCTAssertFalse(config.shouldBypassProxy(for: "example.com"))
        XCTAssertTrue(config.shouldBypassProxy(for: "sub.example.com"))
        XCTAssertTrue(config.shouldBypassProxy(for: "deep.sub.example.com"))
    }

    func testNoProxyWildcard() {
        let config = HTTPProxyConfiguration(
            version: 1,
            noProxy: ["*"]
        )
        XCTAssertTrue(config.shouldBypassProxy(for: "anything.com"))
        XCTAssertTrue(config.shouldBypassProxy(for: "localhost"))
        XCTAssertTrue(config.shouldBypassProxy(for: "192.168.1.1"))
    }

    func testNoProxyCaseInsensitive() {
        let config = HTTPProxyConfiguration(
            version: 1,
            noProxy: ["Example.COM"]
        )
        XCTAssertTrue(config.shouldBypassProxy(for: "example.com"))
        XCTAssertTrue(config.shouldBypassProxy(for: "EXAMPLE.COM"))
        XCTAssertTrue(config.shouldBypassProxy(for: "sub.Example.Com"))
    }

    func testNoProxyIPAddress() {
        let config = HTTPProxyConfiguration(
            version: 1,
            noProxy: ["192.168.1.1", "127.0.0.1"]
        )
        XCTAssertTrue(config.shouldBypassProxy(for: "192.168.1.1"))
        XCTAssertTrue(config.shouldBypassProxy(for: "127.0.0.1"))
        XCTAssertFalse(config.shouldBypassProxy(for: "192.168.1.2"))
    }

    func testNoProxyLocalhost() {
        let config = HTTPProxyConfiguration(
            version: 1,
            noProxy: ["localhost"]
        )
        XCTAssertTrue(config.shouldBypassProxy(for: "localhost"))
        XCTAssertFalse(config.shouldBypassProxy(for: "localhostx"))
    }

    func testNoProxyEmpty() {
        let config = HTTPProxyConfiguration(version: 1, noProxy: [])
        XCTAssertFalse(config.shouldBypassProxy(for: "anything.com"))
    }

    func testNoProxyNil() {
        let config = HTTPProxyConfiguration(version: 1)
        XCTAssertFalse(config.shouldBypassProxy(for: "anything.com"))
    }

    // MARK: - proxyURL(for:)

    func testProxyURLForHTTP() {
        let config = HTTPProxyConfiguration(
            version: 1,
            http: .init(proxy: "http://http-proxy:8080"),
            https: .init(proxy: "http://https-proxy:8443")
        )
        XCTAssertEqual(config.proxyURL(for: URL(string: "http://example.com")!), "http://http-proxy:8080")
        XCTAssertEqual(config.proxyURL(for: URL(string: "https://example.com")!), "http://https-proxy:8443")
    }

    func testProxyURLBypassesNoProxy() {
        let config = HTTPProxyConfiguration(
            version: 1,
            http: .init(proxy: "http://proxy:8080"),
            https: .init(proxy: "http://proxy:8080"),
            noProxy: ["internal.corp"]
        )
        XCTAssertNil(config.proxyURL(for: URL(string: "http://internal.corp/path")!))
        XCTAssertNil(config.proxyURL(for: URL(string: "https://api.internal.corp")!))
        XCTAssertEqual(config.proxyURL(for: URL(string: "http://external.com")!), "http://proxy:8080")
    }

    func testProxyURLReturnsNilForHTTPSWhenOnlyHTTPConfigured() {
        let config = HTTPProxyConfiguration(
            version: 1,
            http: .init(proxy: "http://proxy:8080")
        )
        XCTAssertEqual(config.proxyURL(for: URL(string: "http://example.com")!), "http://proxy:8080")
        XCTAssertNil(config.proxyURL(for: URL(string: "https://example.com")!))
    }

    // MARK: - ParsedProxyURL

    func testParseProxyURLHTTP() throws {
        let parsed = try HTTPProxyConfiguration.parseProxyURL("http://proxy.example.com:3128")
        XCTAssertEqual(parsed.scheme, "http")
        XCTAssertEqual(parsed.host, "proxy.example.com")
        XCTAssertEqual(parsed.port, 3128)
    }

    func testParseProxyURLDefaultPort() throws {
        let parsed = try HTTPProxyConfiguration.parseProxyURL("http://proxy.example.com")
        XCTAssertEqual(parsed.port, 80)

        let parsedHTTPS = try HTTPProxyConfiguration.parseProxyURL("https://proxy.example.com")
        XCTAssertEqual(parsedHTTPS.port, 443)

        let parsedSOCKS = try HTTPProxyConfiguration.parseProxyURL("socks5://proxy.example.com")
        XCTAssertEqual(parsedSOCKS.port, 1080)
    }

    func testParseProxyURLInvalid() {
        XCTAssertThrowsError(try HTTPProxyConfiguration.parseProxyURL("not a url"))
    }
}
