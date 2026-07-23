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

@Suite("Search query parsing")
struct SearchQueryTests {
    @Test func `empty query has no terms and matches nothing`() throws {
        let query = try SearchQuery(parsing: "   ")
        #expect(query.isEmpty)
        #expect(!query.matches(scope: "mona", name: "LinkedList", description: "links", author: "Mona"))
    }

    @Test func `free text matches identity and description case-insensitively`() throws {
        let query = try SearchQuery(parsing: "LINK")
        #expect(query.matches(scope: "mona", name: "LinkedList", description: nil, author: nil))
        #expect(query.matches(scope: "acme", name: "Widget", description: "a Linkable thing", author: nil))
        #expect(!query.matches(scope: "acme", name: "Widget", description: "unrelated", author: nil))
    }

    @Test func `multiple free-text terms all must match`() throws {
        let query = try SearchQuery(parsing: "linked list")
        #expect(query.matches(scope: "mona", name: "LinkedList", description: nil, author: nil))
        let unmet = try SearchQuery(parsing: "linked queue")
        #expect(!unmet.matches(scope: "mona", name: "LinkedList", description: nil, author: nil))
    }

    @Test func `scope qualifier matches only the scope`() throws {
        let query = try SearchQuery(parsing: "scope:mona")
        #expect(query.matches(scope: "mona", name: "LinkedList", description: nil, author: nil))
        #expect(!query.matches(scope: "apple", name: "mona-tools", description: nil, author: nil))
    }

    @Test func `author qualifier with quoted multi-word value`() throws {
        let query = try SearchQuery(parsing: "author:\"Mona Lisa\"")
        #expect(query.matches(scope: "mona", name: "LinkedList", description: nil, author: "Mona Lisa Octocat"))
        #expect(!query.matches(scope: "mona", name: "LinkedList", description: nil, author: "Bob"))
    }

    @Test func `description qualifier matches only the description`() throws {
        let query = try SearchQuery(parsing: "description:another")
        #expect(query.matches(scope: "mona", name: "LinkedList", description: "one thing links to another", author: nil))
        #expect(!query.matches(scope: "another", name: "pkg", description: "unrelated", author: nil))
    }

    @Test func `unknown qualifier is rejected`() throws {
        #expect(throws: SearchQueryError.unknownQualifier("foo")) {
            _ = try SearchQuery(parsing: "foo:bar")
        }
    }

    @Test func `token with non-qualifier colon is treated as free text`() throws {
        let query = try SearchQuery(parsing: "1.0:beta")
        #expect(!query.isEmpty)
        #expect(query.matches(scope: "acme", name: "pkg", description: "the 1.0:beta build", author: nil))
    }
}
