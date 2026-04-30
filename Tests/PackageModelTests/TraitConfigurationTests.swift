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

import Foundation
import Testing
import enum PackageModel.TraitConfiguration

@Suite(
    .tags(
        .TestSize.small
    )
)
struct TraitConfigurationTests {

    // MARK: - Encoding

    @Test
    func encode_default() throws {
        let encoded = try JSONEncoder().encode(TraitConfiguration.default)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(json.contains("\"default\""))
    }

    @Test
    func encode_enableAllTraits() throws {
        let encoded = try JSONEncoder().encode(TraitConfiguration.enableAllTraits)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(json.contains("\"enableAllTraits\""))
    }

    @Test
    func encode_disableAllTraits() throws {
        let encoded = try JSONEncoder().encode(TraitConfiguration.disableAllTraits)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(json.contains("\"disableAllTraits\""))
    }

    @Test
    func encode_enabledTraits() throws {
        let encoded = try JSONEncoder().encode(TraitConfiguration.enabledTraits(["FeatureA", "FeatureB"]))
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(json.contains("\"enabledTraits\""))
        #expect(json.contains("FeatureA"))
        #expect(json.contains("FeatureB"))
    }

    // MARK: - Roundtrip

    @Test
    func roundtrip_default() throws {
        let original = TraitConfiguration.default
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TraitConfiguration.self, from: data)
        #expect(decoded == original)
    }

    @Test
    func roundtrip_enableAllTraits() throws {
        let original = TraitConfiguration.enableAllTraits
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TraitConfiguration.self, from: data)
        #expect(decoded == original)
    }

    @Test
    func roundtrip_disableAllTraits() throws {
        let original = TraitConfiguration.disableAllTraits
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TraitConfiguration.self, from: data)
        #expect(decoded == original)
    }

    @Test
    func roundtrip_enabledTraits() throws {
        let original = TraitConfiguration.enabledTraits(["FeatureA", "FeatureB"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TraitConfiguration.self, from: data)
        #expect(decoded == original)
    }

    @Test
    func roundtrip_enabledTraits_preservesAllTraitNames() throws {
        let traits: Set<String> = ["Alpha", "Beta", "Gamma", "Delta"]
        let original = TraitConfiguration.enabledTraits(traits)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TraitConfiguration.self, from: data)
        guard case .enabledTraits(let decodedTraits) = decoded else {
            Issue.record("Expected .enabledTraits, got \(decoded)")
            return
        }
        #expect(decodedTraits == traits)
    }

    // MARK: - Decoding from known JSON

    @Test
    func decode_defaultFromJSON() throws {
        let json = #"{"default":[[]]}"#
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(TraitConfiguration.self, from: data)
        #expect(decoded == .default)
    }

    @Test
    func decode_enableAllTraitsFromJSON() throws {
        let json = #"{"enableAllTraits":[[]]}"#
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(TraitConfiguration.self, from: data)
        #expect(decoded == .enableAllTraits)
    }

    @Test
    func decode_disableAllTraitsFromJSON() throws {
        let json = #"{"disableAllTraits":[[]]}"#
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(TraitConfiguration.self, from: data)
        #expect(decoded == .disableAllTraits)
    }

    @Test
    func decode_enabledTraitsFromJSON() throws {
        let json = #"{"enabledTraits":["FeatureA","FeatureB"]}"#
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(TraitConfiguration.self, from: data)
        #expect(decoded == .enabledTraits(["FeatureA", "FeatureB"]))
    }
}
