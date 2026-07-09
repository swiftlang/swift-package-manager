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

import Testing
@testable import RegistryExample

@Suite("PackageIdentifier")
struct PackageIdentifierTests {
    @Test func `parses valid scope and name`() throws {
        let id = try PackageIdentifier(scope: "mona", name: "LinkedList")
        #expect(id.scope == "mona")
        #expect(id.name == "LinkedList")
    }

    @Test func `scope and name comparisons are case-insensitive`() throws {
        let a = try PackageIdentifier(scope: "Mona", name: "LinkedList")
        let b = try PackageIdentifier(scope: "mona", name: "linkedlist")
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test func `preserves original casing for display`() throws {
        let id = try PackageIdentifier(scope: "CatalogDev", name: "HelloWorld")
        #expect(id.scope == "CatalogDev")
        #expect(id.name == "HelloWorld")
    }

    @Test func `renders as scope.name`() throws {
        let id = try PackageIdentifier(scope: "exampleregistry", name: "HelloWorld")
        #expect(id.description == "exampleregistry.HelloWorld")
    }

    @Test(
        arguments: [
            "",
            "-mona",
            "mona-",
            "mona--lisa",
            "mona.lisa",
            "mona_lisa",
            String(repeating: "a", count: 40),
            "Аpple",
            "Αpple",
            "café",
            "mona\u{200B}lisa",
            "mon\u{0430}",
            "١٢٣",
        ]
    )
    func `rejects invalid scopes`(_ scope: String) {
        #expect(throws: PackageIdentifierError.invalidScope) {
            _ = try PackageIdentifier(scope: scope, name: "LinkedList")
        }
    }

    @Test(
        arguments: [
            "",
            "-LinkedList",
            "LinkedList-",
            "_LinkedList",
            "LinkedList_",
            "Linked--List",
            "Linked__List",
            "Linked.List",
            String(repeating: "a", count: 101),
            "Linked\u{0130}ist",
            "Βeta",
            "Linked\u{200B}List",
            "café",
            "Linked١List",
        ]
    )
    func `rejects invalid names`(_ name: String) {
        #expect(throws: PackageIdentifierError.invalidName) {
            _ = try PackageIdentifier(scope: "mona", name: name)
        }
    }

    @Test func `case-insensitive equality still holds after ASCII tightening`() throws {
        let upper = try PackageIdentifier(scope: "MONA", name: "LINKEDLIST")
        let lower = try PackageIdentifier(scope: "mona", name: "linkedlist")
        #expect(upper == lower)
        #expect(upper.storageKey == "mona.linkedlist")
        #expect(lower.storageKey == "mona.linkedlist")
    }

    @Test func `accepts maximum-length scope and name`() throws {
        let scope39 = String(repeating: "a", count: 39)
        let name100 = String(repeating: "a", count: 100)
        _ = try PackageIdentifier(scope: scope39, name: name100)
    }

    @Test func `names may contain underscores and hyphens between alphanumerics`() throws {
        _ = try PackageIdentifier(scope: "scope", name: "some_name-value")
    }

    @Test func `storageKey is lowercased`() throws {
        let id = try PackageIdentifier(scope: "Mona", name: "LinkedList")
        #expect(id.storageKey == "mona.linkedlist")
    }
}