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

/// The severity of an advisory, ordered from least to most severe.
/// `unknown` is used when a record carries no usable severity.
public enum AdvisorySeverity: String, Codable, Sendable, CaseIterable {
    case low, moderate, high, critical, unknown

    /// Derives the severity of a record. The GitHub-style `database_specific.severity`
    /// label takes precedence; otherwise a CVSS v3 vector is scored and banded.
    /// CVSS v4 and other score types are not interpreted.
    public init(record: OSVRecord) {
        if let label = record.databaseSpecific?.severity, let severity = Self.fromLabel(label) {
            self = severity
            return
        }
        for entry in record.severity ?? [] where entry.type == "CVSS_V3" {
            if let score = CVSSv3.baseScore(vector: entry.score) {
                switch score {
                case 9.0...: self = .critical
                case 7.0...: self = .high
                case 4.0...: self = .moderate
                case 0.1...: self = .low
                default: self = .unknown
                }
                return
            }
        }
        self = .unknown
    }

    private static func fromLabel(_ label: String) -> AdvisorySeverity? {
        switch label.uppercased() {
        case "LOW": .low
        case "MODERATE", "MEDIUM": .moderate
        case "HIGH": .high
        case "CRITICAL": .critical
        default: nil
        }
    }

    /// Whether this severity is at or above `threshold`. `unknown` always
    /// meets a threshold so that unrated advisories are never silently hidden.
    public func meets(_ threshold: AdvisorySeverity) -> Bool {
        guard self != .unknown else { return true }
        return self.rank >= threshold.rank
    }

    private var rank: Int {
        switch self {
        case .unknown, .low: 0
        case .moderate: 1
        case .high: 2
        case .critical: 3
        }
    }
}
