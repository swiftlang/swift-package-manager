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
    func replacementRenamedEncodesToWireFormat() throws {
        let replacement: Serialization.Product.Deprecation.Replacement = .renamed(to: "NewName")
        let encoded = try JSONEncoder().encode(replacement)
        let json = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(json["kind"] as? String == "renamed")
        #expect(json["to"] as? String == "NewName")
        #expect(json["package"] == nil)
        #expect(json["product"] == nil)
    }

    @Test
    func replacementInPackageEncodesToWireFormat() throws {
        let replacement: Serialization.Product.Deprecation.Replacement = .inPackage(
            package: "pkg",
            product: "prod",
        )
        let encoded = try JSONEncoder().encode(replacement)
        let json = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(json["kind"] as? String == "inPackage")
        #expect(json["package"] as? String == "pkg")
        #expect(json["product"] as? String == "prod")
        #expect(json["to"] == nil)
    }

    @Test
    func replacementRenamedDecodesFromWireFormat() throws {
        let json = #"{"kind":"renamed","to":"NewName"}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(
            Serialization.Product.Deprecation.Replacement.self,
            from: data,
        )
        guard case .renamed(let newName) = decoded else {
            Issue.record("expected .renamed case, got \(decoded)")
            return
        }
        #expect(newName == "NewName")
    }

    @Test
    func replacementInPackageDecodesFromWireFormat() throws {
        let json = #"{"kind":"inPackage","package":"pkg","product":"prod"}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(
            Serialization.Product.Deprecation.Replacement.self,
            from: data,
        )
        guard case .inPackage(let package, let product) = decoded else {
            Issue.record("expected .inPackage case, got \(decoded)")
            return
        }
        #expect(package == "pkg")
        #expect(product == "prod")
    }

    @Test
    func replacementRenamedRoundTrips() throws {
        let original: Serialization.Product.Deprecation.Replacement = .renamed(to: "Foo")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            Serialization.Product.Deprecation.Replacement.self,
            from: encoded,
        )
        guard case .renamed(let newName) = decoded else {
            Issue.record("expected .renamed case, got \(decoded)")
            return
        }
        #expect(newName == "Foo")
    }

    @Test
    func replacementInPackageRoundTrips() throws {
        let original: Serialization.Product.Deprecation.Replacement = .inPackage(
            package: "p",
            product: "q",
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            Serialization.Product.Deprecation.Replacement.self,
            from: encoded,
        )
        guard case .inPackage(let package, let product) = decoded else {
            Issue.record("expected .inPackage case, got \(decoded)")
            return
        }
        #expect(package == "p")
        #expect(product == "q")
    }

    // MARK: - Serialization.Product.Deprecation Codable

    @Test
    func deprecationWithMessageAndReplacementRoundTrips() throws {
        let original = Serialization.Product.Deprecation(
            message: "Use New instead.",
            replacement: .renamed(to: "New"),
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            Serialization.Product.Deprecation.self,
            from: encoded,
        )
        #expect(decoded.message == "Use New instead.")
        let replacement = try #require(decoded.replacement)
        guard case .renamed(let newName) = replacement else {
            Issue.record("expected .renamed replacement, got \(replacement)")
            return
        }
        #expect(newName == "New")
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
    func wireProductWithRenamedReplacementConvertsToModel() throws {
        let wire = makeWireProduct(
            name: "OldLib",
            productType: .library(type: .automatic),
            deprecation: .init(
                message: "Use NewLib instead.",
                replacement: .renamed(to: "NewLib"),
            ),
        )
        let model = try ProductDescription(wire)
        let deprecation = try #require(model.deprecation)
        #expect(deprecation.message == "Use NewLib instead.")
        #expect(deprecation.replacement == .renamed(to: "NewLib"))
    }

    @Test
    func wireProductWithInPackageReplacementConvertsToModel() throws {
        let wire = makeWireProduct(
            name: "old-tool",
            productType: .executable,
            deprecation: .init(
                message: "Migrate to new-tool.",
                replacement: .inPackage(package: "tools", product: "new-tool"),
            ),
        )
        let model = try ProductDescription(wire)
        let deprecation = try #require(model.deprecation)
        #expect(deprecation.message == "Migrate to new-tool.")
        #expect(deprecation.replacement == .inPackage(package: "tools", product: "new-tool"))
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
                replacement: .renamed(to: "NewPlugin"),
            ),
        )
        let model = try ProductDescription(wire)
        #expect(model.type == .plugin)
        let deprecation = try #require(model.deprecation)
        #expect(deprecation.message == nil)
        #expect(deprecation.replacement == .renamed(to: "NewPlugin"))
    }

    // MARK: - End-to-end wire → JSON → wire → model

    @Test
    func fullPipelineEndToEnd() throws {
        let originalWire = makeWireProduct(
            name: "OldLib",
            productType: .library(type: .automatic),
            deprecation: .init(
                message: "Use NewLib instead.",
                replacement: .renamed(to: "NewLib"),
            ),
        )

        let jsonData = try JSONEncoder().encode(originalWire)
        let decodedWire = try JSONDecoder().decode(Serialization.Product.self, from: jsonData)
        let model = try ProductDescription(decodedWire)

        #expect(model.name == "OldLib")
        let deprecation = try #require(model.deprecation)
        #expect(deprecation.message == "Use NewLib instead.")
        #expect(deprecation.replacement == .renamed(to: "NewLib"))
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
