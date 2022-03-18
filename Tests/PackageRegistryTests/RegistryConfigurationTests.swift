//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import XCTest
import SPMTestSupport
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
        let json = #"""
        {
            "registries": {},
            "version": 1
        }
        """#

        let configuration = try decoder.decode(RegistryConfiguration.self, from: json)
        XCTAssertNil(configuration.defaultRegistry)
        XCTAssertEqual(configuration.scopedRegistries, [:])
    }

    func testDecodeExampleConfiguration() throws {
        let json = #"""
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
        """#

        let configuration = try decoder.decode(RegistryConfiguration.self, from: json)
        XCTAssertEqual(configuration.defaultRegistry?.url, defaultRegistryBaseURL)
        XCTAssertEqual(configuration.scopedRegistries["foo"]?.url, customRegistryBaseURL)
        XCTAssertEqual(configuration.scopedRegistries["bar"]?.url, customRegistryBaseURL)
    }

    func testDecodeConfigurationWithInvalidRegistryKey() throws {
        let json = #"""
        {
            "registries": {
                0: "\#(customRegistryBaseURL)"
            },
            "version": 1
        }
        """#

        XCTAssertThrowsError(try decoder.decode(RegistryConfiguration.self, from: json))
    }

    func testDecodeConfigurationWithInvalidRegistryValue() throws {
        let json = #"""
        {
            "registries": {
                "[default]": "\#(customRegistryBaseURL)"
            },
            "version": 1
        }
        """#

        XCTAssertThrowsError(try decoder.decode(RegistryConfiguration.self, from: json))
    }

    func testDecodeConfigurationWithMissingVersion() throws {
        let json = #"""
        {
            "registries": {}
        }
        """#

        XCTAssertThrowsError(try decoder.decode(RegistryConfiguration.self, from: json))
    }

    func testDecodeConfigurationWithInvalidVersion() throws {
        let json = #"""
        {
            "registries": {},
            "version": 999
        }
        """#

        XCTAssertThrowsError(try decoder.decode(RegistryConfiguration.self, from: json))
    }
}
