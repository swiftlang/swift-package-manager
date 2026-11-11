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

/// A vulnerability record in the Open Source Vulnerability (OSV) schema.
/// Unknown keys in the source JSON are ignored.
public struct OSVRecord: Codable, Equatable, Sendable {
    public var id: String
    public var aliases: [String]?
    public var summary: String?
    public var details: String?
    public var withdrawn: String?
    public var affected: [Affected]?
    public var severity: [Severity]?
    public var references: [Reference]?
    public var databaseSpecific: DatabaseSpecific?

    enum CodingKeys: String, CodingKey {
        case id, aliases, summary, details, withdrawn, affected, severity, references
        case databaseSpecific = "database_specific"
    }

    public init(
        id: String,
        aliases: [String]? = nil,
        summary: String? = nil,
        details: String? = nil,
        withdrawn: String? = nil,
        affected: [Affected]? = nil,
        severity: [Severity]? = nil,
        references: [Reference]? = nil,
        databaseSpecific: DatabaseSpecific? = nil
    ) {
        self.id = id
        self.aliases = aliases
        self.summary = summary
        self.details = details
        self.withdrawn = withdrawn
        self.affected = affected
        self.severity = severity
        self.references = references
        self.databaseSpecific = databaseSpecific
    }

    public struct Affected: Codable, Equatable, Sendable {
        public var package: Package?
        public var ranges: [Range]?
        public var versions: [String]?

        public init(package: Package? = nil, ranges: [Range]? = nil, versions: [String]? = nil) {
            self.package = package
            self.ranges = ranges
            self.versions = versions
        }
    }

    public struct Package: Codable, Equatable, Sendable {
        public var ecosystem: String
        public var name: String

        public init(ecosystem: String, name: String) {
            self.ecosystem = ecosystem
            self.name = name
        }
    }

    public struct Range: Codable, Equatable, Sendable {
        public var type: String
        public var events: [Event]

        public init(type: String, events: [Event]) {
            self.type = type
            self.events = events
        }
    }

    public struct Event: Codable, Equatable, Sendable {
        public var introduced: String?
        public var fixed: String?
        public var lastAffected: String?
        public var limit: String?

        enum CodingKeys: String, CodingKey {
            case introduced, fixed, limit
            case lastAffected = "last_affected"
        }

        public init(
            introduced: String? = nil,
            fixed: String? = nil,
            lastAffected: String? = nil,
            limit: String? = nil
        ) {
            self.introduced = introduced
            self.fixed = fixed
            self.lastAffected = lastAffected
            self.limit = limit
        }
    }

    public struct Severity: Codable, Equatable, Sendable {
        public var type: String
        public var score: String

        public init(type: String, score: String) {
            self.type = type
            self.score = score
        }
    }

    public struct Reference: Codable, Equatable, Sendable {
        public var type: String
        public var url: String

        public init(type: String, url: String) {
            self.type = type
            self.url = url
        }
    }

    public struct DatabaseSpecific: Codable, Equatable, Sendable {
        public var severity: String?

        public init(severity: String? = nil) {
            self.severity = severity
        }
    }
}
