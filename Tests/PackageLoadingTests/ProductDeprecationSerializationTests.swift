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

import Foundation
import PackageModel
import Testing

@testable import PackageLoading

@Suite(
    .tags(
        .TestSize.small,
        .FunctionalArea.Manifest,
        .Feature.Deprecation,
    ),
)
struct ProductDeprecationSerializationTests {

    // MARK: - Serialization.Product.Deprecation.Replacement wire format

    @Test
    func replacementSamePackageEncodesToWireFormat() throws {
        let replacement: Serialization.Product.Deprecation.Replacement = .renamed("NewName")
        let encoded = try JSONEncoder().encode(replacement)
        let json = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(json["kind"] as? String == "renamed")
        #expect(json["product"] as? String == "NewName")
        #expect(json["package"] == nil)
    }

    @Test
    func replacementCrossPackageEncodesToWireFormat() throws {
        let replacement: Serialization.Product.Deprecation.Replacement = .renamed(
            "prod",
            package: "pkg",
        )
        let encoded = try JSONEncoder().encode(replacement)
        let json = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(json["kind"] as? String == "renamed")
        #expect(json["product"] as? String == "prod")
        #expect(json["package"] as? String == "pkg")
    }

    @Test
    func replacementSamePackageDecodesFromWireFormat() throws {
        let json = #"{"kind":"renamed","product":"NewName"}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(
            Serialization.Product.Deprecation.Replacement.self,
            from: data,
        )
        guard case .renamed(let product, let package) = decoded else {
            Issue.record("expected .renamed case, got \(decoded)")
            return
        }
        #expect(product == "NewName")
        #expect(package == nil)
    }

    @Test
    func replacementCrossPackageDecodesFromWireFormat() throws {
        let json = #"{"kind":"renamed","product":"prod","package":"pkg"}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(
            Serialization.Product.Deprecation.Replacement.self,
            from: data,
        )
        guard case .renamed(let product, let package) = decoded else {
            Issue.record("expected .renamed case, got \(decoded)")
            return
        }
        #expect(product == "prod")
        #expect(package == "pkg")
    }

    @Test
    func replacementSamePackageRoundTrips() throws {
        let original: Serialization.Product.Deprecation.Replacement = .renamed("Foo")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            Serialization.Product.Deprecation.Replacement.self,
            from: encoded,
        )
        guard case .renamed(let product, let package) = decoded else {
            Issue.record("expected .renamed case, got \(decoded)")
            return
        }
        #expect(product == "Foo")
        #expect(package == nil)
    }

    @Test
    func replacementCrossPackageRoundTrips() throws {
        let original: Serialization.Product.Deprecation.Replacement = .renamed(
            "q",
            package: "p",
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            Serialization.Product.Deprecation.Replacement.self,
            from: encoded,
        )
        guard case .renamed(let product, let package) = decoded else {
            Issue.record("expected .renamed case, got \(decoded)")
            return
        }
        #expect(product == "q")
        #expect(package == "p")
    }

    // MARK: - Serialization.Product.Deprecation Codable

    @Test
    func deprecationWithMessageAndReplacementRoundTrips() throws {
        let original = Serialization.Product.Deprecation(
            message: "Use New instead.",
            replacement: .renamed("New"),
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            Serialization.Product.Deprecation.self,
            from: encoded,
        )
        #expect(decoded.message == "Use New instead.")
        let replacement = try #require(decoded.replacement)
        guard case .renamed(let product, let package) = replacement else {
            Issue.record("expected .renamed replacement, got \(replacement)")
            return
        }
        #expect(product == "New")
        #expect(package == nil)
    }

    @Test
    func deprecationWithMessageOnlyRoundTrips() throws {
        let original = Serialization.Product.Deprecation(
            message: "Retired.",
            replacement: nil,
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            Serialization.Product.Deprecation.self,
            from: encoded,
        )
        #expect(decoded.message == "Retired.")
        #expect(decoded.replacement == nil)
    }

    @Test
    func deprecationEmptyRoundTrips() throws {
        let original = Serialization.Product.Deprecation(
            message: nil,
            replacement: nil,
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            Serialization.Product.Deprecation.self,
            from: encoded,
        )
        #expect(decoded.message == nil)
        #expect(decoded.replacement == nil)
    }

    // MARK: - Wire → model conversion (Serialization.Product → ProductDescription)

    @Test
    func wireProductWithoutDeprecationConvertsToModelWithNilDeprecation() throws {
        let wire = makeWireProduct(
            name: "Foo",
            productType: .library(type: .automatic),
            deprecation: nil,
        )
        let model = try ProductDescription(wire)
        #expect(model.name == "Foo")
        #expect(model.deprecation == nil)
    }

    @Test
    func wireProductWithSamePackageReplacementConvertsToModel() throws {
        let wire = makeWireProduct(
            name: "OldLib",
            productType: .library(type: .automatic),
            deprecation: .init(
                message: "Use NewLib instead.",
                replacement: .renamed("NewLib"),
            ),
        )
        let model = try ProductDescription(wire)
        let deprecation = try #require(model.deprecation)
        #expect(deprecation.message == "Use NewLib instead.")
        #expect(deprecation.replacement == .renamed("NewLib"))
    }

    @Test
    func wireProductWithCrossPackageReplacementConvertsToModel() throws {
        let wire = makeWireProduct(
            name: "old-tool",
            productType: .executable,
            deprecation: .init(
                message: "Migrate to new-tool.",
                replacement: .renamed("new-tool", package: "tools"),
            ),
        )
        let model = try ProductDescription(wire)
        let deprecation = try #require(model.deprecation)
        #expect(deprecation.message == "Migrate to new-tool.")
        #expect(deprecation.replacement == .renamed("new-tool", package: "tools"))
    }

    @Test
    func wireProductWithNoReplacementConvertsToModel() throws {
        let wire = makeWireProduct(
            name: "Retired",
            productType: .library(type: .automatic),
            deprecation: .init(
                message: "Gone.",
                replacement: nil,
            ),
        )
        let model = try ProductDescription(wire)
        let deprecation = try #require(model.deprecation)
        #expect(deprecation.message == "Gone.")
        #expect(deprecation.replacement == nil)
    }

    @Test
    func wireProductWithEmptyDeprecationConvertsToModel() throws {
        let wire = makeWireProduct(
            name: "Foo",
            productType: .library(type: .automatic),
            deprecation: .init(
                message: nil,
                replacement: nil,
            ),
        )
        let model = try ProductDescription(wire)
        let deprecation = try #require(model.deprecation)
        #expect(deprecation.message == nil)
        #expect(deprecation.replacement == nil)
    }

    @Test
    func wirePluginProductWithDeprecationConvertsToModel() throws {
        let wire = makeWireProduct(
            name: "OldPlugin",
            productType: .plugin,
            deprecation: .init(
                message: nil,
                replacement: .renamed("NewPlugin"),
            ),
        )
        let model = try ProductDescription(wire)
        #expect(model.type == .plugin)
        let deprecation = try #require(model.deprecation)
        #expect(deprecation.message == nil)
        #expect(deprecation.replacement == .renamed("NewPlugin"))
    }

    // MARK: - End-to-end wire → JSON → wire → model

    @Test
    func fullPipelineEndToEnd() throws {
        let originalWire = makeWireProduct(
            name: "OldLib",
            productType: .library(type: .automatic),
            deprecation: .init(
                message: "Use NewLib instead.",
                replacement: .renamed("NewLib"),
            ),
        )

        let jsonData = try JSONEncoder().encode(originalWire)
        let decodedWire = try JSONDecoder().decode(Serialization.Product.self, from: jsonData)
        let model = try ProductDescription(decodedWire)

        #expect(model.name == "OldLib")
        let deprecation = try #require(model.deprecation)
        #expect(deprecation.message == "Use NewLib instead.")
        #expect(deprecation.replacement == .renamed("NewLib"))
    }

    // MARK: - Helpers

    /// Constructs a `Serialization.Product` value across both `ENABLE_APPLE_PRODUCT_TYPES`
    /// build configurations so tests compile whether or not the flag is defined.
    private func makeWireProduct(
        name: String,
        productType: Serialization.Product.ProductType,
        deprecation: Serialization.Product.Deprecation?,
    ) -> Serialization.Product {
        #if ENABLE_APPLE_PRODUCT_TYPES
        return Serialization.Product(
            name: name,
            targets: [name],
            productType: productType,
            deprecation: deprecation,
            settings: [],
        )
        #else
        return Serialization.Product(
            name: name,
            targets: [name],
            productType: productType,
            deprecation: deprecation,
        )
        #endif
    }
}
