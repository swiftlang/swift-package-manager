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

@Suite(
    .tags(
        .TestSize.small,
        .FunctionalArea.Manifest,
        .Feature.Deprecation,
    ),
)
struct ProductDeprecationTests {

    // MARK: - ProductDescription.deprecation storage

    @Test
    func productDescriptionWithoutDeprecation() throws {
        let product = try ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"])
        #expect(product.deprecation == nil)
    }

    @Test
    func productDescriptionWithDeprecationRenamed() throws {
        let deprecation = ProductDeprecation(
            message: "Use Bar instead.",
            replacement: .renamed(to: "Bar")
        )
        let product = try ProductDescription(
            name: "Foo",
            type: .library(.automatic),
            targets: ["Foo"],
            deprecation: deprecation,
        )
        let productDeprecation = try #require(product.deprecation)
        #expect(productDeprecation.message == "Use Bar instead.")
        #expect(productDeprecation.replacement == .renamed(to: "Bar"))
    }

    @Test
    func productDescriptionWithDeprecationInPackage() throws {
        let deprecation = ProductDeprecation(
            message: "Migrate to other-package.",
            replacement: .inPackage(package: "other-package", product: "OtherProduct")
        )
        let product = try ProductDescription(
            name: "Foo",
            type: .library(.automatic),
            targets: ["Foo"],
            deprecation: deprecation,
        )
        let productDeprecation = try #require(product.deprecation)
        #expect(productDeprecation.replacement == .inPackage(package: "other-package", product: "OtherProduct"))
    }

    @Test
    func productDescriptionWithDeprecationNoMessageNoReplacement() throws {
        let deprecation = ProductDeprecation(message: nil, replacement: nil)
        let product = try ProductDescription(
            name: "Foo",
            type: .library(.automatic),
            targets: ["Foo"],
            deprecation: deprecation,
        )
        let productDeprecation = try #require(product.deprecation)
        #expect(productDeprecation.message == nil)
        #expect(productDeprecation.replacement == nil)
    }

    // MARK: - ProductDescription Codable round-trip

    @Test
    func productDescriptionRoundTripNoDeprecation() throws {
        let product = try ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"])
        let encoded = try JSONEncoder().encode(product)
        let decoded = try JSONDecoder().decode(ProductDescription.self, from: encoded)
        #expect(decoded.name == product.name)
        #expect(decoded.deprecation == nil)
    }

    @Test
    func productDescriptionRoundTripRenamedReplacement() throws {
        let deprecation = ProductDeprecation(
            message: "Use Bar instead.",
            replacement: .renamed(to: "Bar")
        )
        let product = try ProductDescription(
            name: "Foo",
            type: .library(.automatic),
            targets: ["Foo"],
            deprecation: deprecation,
        )
        let encoded = try JSONEncoder().encode(product)
        let decoded = try JSONDecoder().decode(ProductDescription.self, from: encoded)

        let decodedDeprecation = try #require(decoded.deprecation)
        #expect(decodedDeprecation.message == "Use Bar instead.")
        #expect(decodedDeprecation.replacement == .renamed(to: "Bar"))
    }

    @Test
    func productDescriptionRoundTripInPackageReplacement() throws {
        let deprecation = ProductDeprecation(
            message: "Move to other package.",
            replacement: .inPackage(package: "pkg", product: "prod")
        )
        let product = try ProductDescription(
            name: "Foo",
            type: .executable,
            targets: ["Foo"],
            deprecation: deprecation,
        )
        let encoded = try JSONEncoder().encode(product)
        let decoded = try JSONDecoder().decode(ProductDescription.self, from: encoded)
        let decodedDeprecation = try #require(decoded.deprecation)
        #expect(decodedDeprecation.replacement == .inPackage(package: "pkg", product: "prod"))
    }

    @Test
    func productDescriptionRoundTripNoMessageNoReplacement() throws {
        let deprecation = ProductDeprecation(message: nil, replacement: nil)
        let product = try ProductDescription(
            name: "Foo",
            type: .library(.automatic),
            targets: ["Foo"],
            deprecation: deprecation,
        )
        let encoded = try JSONEncoder().encode(product)
        let decoded = try JSONDecoder().decode(ProductDescription.self, from: encoded)
        let decodedDeprecation = try #require(decoded.deprecation)
        #expect(decodedDeprecation.message == nil)
        #expect(decodedDeprecation.replacement == nil)
    }

    // MARK: - Legacy JSON without deprecation field

    @Test
    func legacyJSONWithoutDeprecationFieldDecodes() throws {
        let legacyJSON = #"{"name":"Foo","targets":["Foo"],"type":{"library":["automatic"]},"settings":[]}"#
        let data = Data(legacyJSON.utf8)
        let decoded = try JSONDecoder().decode(ProductDescription.self, from: data)
        #expect(decoded.name == "Foo")
        #expect(decoded.deprecation == nil)
    }

    // MARK: - Replacement discriminated Codable wire format

    @Test
    func replacementRenamedEncodesAsKindAndTo() throws {
        let replacement: ProductDeprecation.Replacement = .renamed(to: "NewName")
        let encoded = try JSONEncoder().encode(replacement)
        let json = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(json["kind"] as? String == "renamed")
        #expect(json["to"] as? String == "NewName")
        #expect(json["package"] == nil)
        #expect(json["product"] == nil)
    }

    @Test
    func replacementInPackageEncodesAsKindPackageAndProduct() throws {
        let replacement: ProductDeprecation.Replacement = .inPackage(package: "pkg", product: "prod")
        let encoded = try JSONEncoder().encode(replacement)
        let json = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(json["kind"] as? String == "inPackage")
        #expect(json["package"] as? String == "pkg")
        #expect(json["product"] as? String == "prod")
        #expect(json["to"] == nil)
    }

    @Test
    func replacementDecodesRenamedWireFormat() throws {
        let json = #"{"kind":"renamed","to":"NewName"}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ProductDeprecation.Replacement.self, from: data)
        #expect(decoded == .renamed(to: "NewName"))
    }

    @Test
    func replacementDecodesInPackageWireFormat() throws {
        let json = #"{"kind":"inPackage","package":"pkg","product":"prod"}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ProductDeprecation.Replacement.self, from: data)
        #expect(decoded == .inPackage(package: "pkg", product: "prod"))
    }

    // MARK: - Hashable and Equatable

    @Test
    func productDeprecationEquality() {
        let a = ProductDeprecation(message: "m", replacement: .renamed(to: "N"))
        let b = ProductDeprecation(message: "m", replacement: .renamed(to: "N"))
        let c = ProductDeprecation(message: "m", replacement: .renamed(to: "Other"))
        #expect(a == b)
        #expect(a != c)
    }

    @Test
    func productDeprecationHashable() {
        let a = ProductDeprecation(message: "m", replacement: .renamed(to: "N"))
        let b = ProductDeprecation(message: "m", replacement: .renamed(to: "N"))
        var set = Set<ProductDeprecation>()
        set.insert(a)
        set.insert(b)
        #expect(set.count == 1)
    }
}
