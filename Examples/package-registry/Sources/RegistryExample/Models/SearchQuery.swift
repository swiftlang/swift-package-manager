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

/// An error thrown while parsing a ``SearchQuery``.
public enum SearchQueryError: Error, Equatable, Sendable {
    /// A term used a `qualifier:value` form whose qualifier isn't one of the
    /// recognized ``SearchQuery/Field`` keys. The associated value is that
    /// qualifier.
    case unknownQualifier(String)
}

/// A parsed package search query, as accepted by the `q` parameter of the
/// *Search packages* endpoint (`GET /search`).
///
/// A query is a whitespace-separated list of *terms*. Each term is either a
/// free-text term or a `qualifier:value` term that restricts matching to a
/// single field:
///
/// - **Free text** matches case-insensitively against a package's identity,
///   description, or author name.
/// - **`scope:`**, **`name:`**, **`author:`**, and **`description:`** match
///   only against the named field.
///
/// A value that spans multiple words may be wrapped in double quotes, for
/// example `author:"Mona Lisa"` or `"linked list"`. All terms must match for
/// a package to be included (implicit logical *AND*); an empty query matches
/// nothing. The `OR`/`NOT`/`-` operators and the `pkg:` (package-URL)
/// qualifier described by the proposal are intentionally out of scope for this
/// reference implementation.
public struct SearchQuery: Sendable {
    /// The fields that a `qualifier:value` term may target.
    enum Field: String, Sendable, CaseIterable {
        case scope
        case name
        case author
        case description
    }

    /// A single parsed term of a ``SearchQuery``.
    ///
    /// Both cases carry case-normalized (lowercased) needles, so matching only
    /// needs to lowercase the fields it compares against.
    enum Term: Sendable {
        /// A free-text term matched against identity, description, and author.
        case freeText(String)
        /// A `qualifier:value` term matched against a single ``Field``.
        case qualifier(field: Field, value: String)
    }

    let terms: [Term]

    /// Whether the query carries no terms and therefore matches nothing.
    public var isEmpty: Bool { terms.isEmpty }

    /// Parses a raw query string into its terms.
    ///
    /// - Parameter raw: The raw value of the `q` query parameter.
    /// - Throws: ``SearchQueryError/unknownQualifier(_:)`` if a term uses an
    ///   unrecognized qualifier (for example `foo:bar`).
    public init(parsing raw: String) throws {
        self.terms = try Self.tokenize(raw).map(Self.parseTerm)
    }

    /// Splits a raw query into tokens, treating double-quoted spans as a single
    /// token and discarding the quote characters.
    private static func tokenize(_ raw: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        var inToken = false
        for character in raw {
            if character == "\"" {
                inQuotes.toggle()
                inToken = true
                continue
            }
            if character.isWhitespace, !inQuotes {
                if inToken {
                    tokens.append(current)
                    current = ""
                    inToken = false
                }
                continue
            }
            current.append(character)
            inToken = true
        }
        if inToken { tokens.append(current) }
        return tokens
    }

    /// Classifies a token as a free-text or qualifier term, normalizing its
    /// needle to lowercase for case-insensitive matching.
    ///
    /// A token whose portion before the first colon is a run of ASCII letters
    /// is treated as a qualifier; an unrecognized qualifier key is rejected.
    private static func parseTerm(_ token: String) throws -> Term {
        guard let colon = token.firstIndex(of: ":") else {
            return .freeText(token.lowercased())
        }
        let key = token[token.startIndex..<colon]
        guard !key.isEmpty, key.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            return .freeText(token.lowercased())
        }
        guard let field = Field(rawValue: key.lowercased()) else {
            throw SearchQueryError.unknownQualifier(String(key))
        }
        return .qualifier(field: field, value: token[token.index(after: colon)...].lowercased())
    }

    /// Reports whether a package with the given fields satisfies every term.
    ///
    /// - Parameters:
    ///   - scope: The package scope.
    ///   - name: The package name.
    ///   - description: The package's free-form description, if any.
    ///   - author: The package author's name, if any.
    /// - Returns: `true` if the query is non-empty and all of its terms match.
    func matches(scope: String, name: String, description: String?, author: String?) -> Bool {
        guard !terms.isEmpty else { return false }
        let identity = "\(scope).\(name)"
        return terms.allSatisfy { term in
            switch term {
            case .freeText(let needle):
                return [identity, description, author].contains { $0?.lowercased().contains(needle) ?? false }
            case .qualifier(let field, let needle):
                let haystack: String?
                switch field {
                case .scope: haystack = scope
                case .name: haystack = name
                case .author: haystack = author
                case .description: haystack = description
                }
                return haystack?.lowercased().contains(needle) ?? false
            }
        }
    }
}
