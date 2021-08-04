/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
@testable import PackageRegistry

private let defaultRegistryBaseURL = URL(string: "https://packages.example.com/")!
private let customRegistryBaseURL = URL(string: "https://custom.packages.example.com/")!

final class RegistryConfigurationTests: XCTestCase {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    func testEmptyConfiguration() throws {
        let configuration = RegistryConfiguration()
        XCTAssertNil(configuration.defaultRegistry)
        XCTAssertEqual(configuration.scopedRegistries, [:])
    }

    func testRoundTripCodingForEmptyConfiguration() throws {
        let configuration = RegistryConfiguration()

        let encoded = try encoder.encode(configuration)
        let decoded = try decoder.decode(RegistryConfiguration.self, from: encoded)

        XCTAssertEqual(configuration, decoded)
    }

    func testRoundTripCodingForExampleConfiguration() throws {
        var configuration = RegistryConfiguration()

        configuration.defaultRegistry = .init(url: defaultRegistryBaseURL)
        configuration.scopedRegistries["foo"] = .init(url: customRegistryBaseURL)
        configuration.scopedRegistries["bar"] = .init(url: customRegistryBaseURL)

        let encoded = try encoder.encode(configuration)
        let decoded = try decoder.decode(RegistryConfiguration.self, from: encoded)

        XCTAssertEqual(configuration, decoded)
    }

    func testDecodeEmptyConfiguration() throws {
        let data = #"""
        {
            "registries": {},
            "version": 1
        }
        """#.data(using: .utf8)!

        let configuration = try decoder.decode(RegistryConfiguration.self, from: data)
        XCTAssertNil(configuration.defaultRegistry)
        XCTAssertEqual(configuration.scopedRegistries, [:])
    }

    func testDecodeExampleConfiguration() throws {
        let data = #"""
        {
            "registries": {
                "[default]": {
                    "url": "\#(defaultRegistryBaseURL)"
                },
                "foo": {
                    "url": "\#(customRegistryBaseURL)"
                },
                "bar": {
                    "url": "\#(customRegistryBaseURL)"
                },
            },
            "version": 1
        }
        """#.data(using: .utf8)!

        let configuration = try decoder.decode(RegistryConfiguration.self, from: data)
        XCTAssertEqual(configuration.defaultRegistry?.url, defaultRegistryBaseURL)
        XCTAssertEqual(configuration.scopedRegistries["foo"]?.url, customRegistryBaseURL)
        XCTAssertEqual(configuration.scopedRegistries["bar"]?.url, customRegistryBaseURL)
    }

    func testDecodeConfigurationWithInvalidRegistryKey() throws {
        let data = #"""
        {
            "registries": {
                0: "\#(customRegistryBaseURL)"
            },
            "version": 1
        }
        """#.data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(RegistryConfiguration.self, from: data))
    }

    func testDecodeConfigurationWithInvalidRegistryValue() throws {
        let data = #"""
        {
            "registries": {
                "[default]": "\#(customRegistryBaseURL)"
            },
            "version": 1
        }
        """#.data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(RegistryConfiguration.self, from: data))
    }

    func testDecodeConfigurationWithMissingVersion() throws {
        let data = #"""
        {
            "registries": {}
        }
        """#.data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(RegistryConfiguration.self, from: data))
    }

    func testDecodeConfigurationWithInvalidVersion() throws {
        let data = #"""
        {
            "registries": {},
            "version": 999
        }
        """#.data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(RegistryConfiguration.self, from: data))
    }
}
