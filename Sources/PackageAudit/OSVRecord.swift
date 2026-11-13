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
///
/// Only the fields the client evaluates are modeled. A decoded record keeps its source JSON, including fields that are
/// not modeled, and encodes as that JSON so that reports can show the record as published.
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

    /// The JSON this record was decoded from, if any. Not considered for equality.
    private(set) var sourceJSON: JSONValue?

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
        self.sourceJSON = nil
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.aliases = try container.decodeIfPresent([String].self, forKey: .aliases)
        self.summary = try container.decodeIfPresent(String.self, forKey: .summary)
        self.details = try container.decodeIfPresent(String.self, forKey: .details)
        self.withdrawn = try container.decodeIfPresent(String.self, forKey: .withdrawn)
        self.affected = try container.decodeIfPresent([Affected].self, forKey: .affected)
        self.severity = try container.decodeIfPresent([Severity].self, forKey: .severity)
        self.references = try container.decodeIfPresent([Reference].self, forKey: .references)
        self.databaseSpecific = try container.decodeIfPresent(DatabaseSpecific.self, forKey: .databaseSpecific)
        self.sourceJSON = try JSONValue(from: decoder)
    }

    public func encode(to encoder: any Encoder) throws {
        if let sourceJSON = self.sourceJSON {
            try sourceJSON.encode(to: encoder)
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encodeIfPresent(self.aliases, forKey: .aliases)
        try container.encodeIfPresent(self.summary, forKey: .summary)
        try container.encodeIfPresent(self.details, forKey: .details)
        try container.encodeIfPresent(self.withdrawn, forKey: .withdrawn)
        try container.encodeIfPresent(self.affected, forKey: .affected)
        try container.encodeIfPresent(self.severity, forKey: .severity)
        try container.encodeIfPresent(self.references, forKey: .references)
        try container.encodeIfPresent(self.databaseSpecific, forKey: .databaseSpecific)
    }

    public static func == (lhs: OSVRecord, rhs: OSVRecord) -> Bool {
        lhs.id == rhs.id
            && lhs.aliases == rhs.aliases
            && lhs.summary == rhs.summary
            && lhs.details == rhs.details
            && lhs.withdrawn == rhs.withdrawn
            && lhs.affected == rhs.affected
            && lhs.severity == rhs.severity
            && lhs.references == rhs.references
            && lhs.databaseSpecific == rhs.databaseSpecific
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

/// An arbitrary JSON value, used to keep a record's source JSON.
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(UInt64.self) {
            self = .unsignedInteger(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .unsignedInteger(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
