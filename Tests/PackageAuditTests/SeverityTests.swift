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
@testable import PackageAudit
import Testing

@Suite
struct SeverityTests {
    private let critical = "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"

    @Test
    func cvssKnownScores() {
        #expect(CVSSv3.baseScore(vector: critical) == 9.8)
        #expect(CVSSv3.baseScore(vector: "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:L/I:L/A:N") == 7.2)
        #expect(CVSSv3.baseScore(vector: "CVSS:3.1/AV:L/AC:H/PR:H/UI:R/S:U/C:L/I:N/A:N") == 1.8)
        #expect(CVSSv3.baseScore(vector: "garbage") == nil)
    }

    @Test
    func severityPrecedence() {
        let cvss = [OSVRecord.Severity(type: "CVSS_V3", score: critical)]
        #expect(AdvisorySeverity(record: OSVRecord(
            id: "A", severity: cvss, databaseSpecific: .init(severity: "MEDIUM")
        )) == .moderate)
        #expect(AdvisorySeverity(record: OSVRecord(id: "B", severity: cvss)) == .critical)
        #expect(AdvisorySeverity(record: OSVRecord(
            id: "C", severity: [.init(type: "CVSS_V4", score: "CVSS:4.0/AV:N")]
        )) == .unknown)
    }

    @Test
    func thresholds() {
        #expect(!AdvisorySeverity.moderate.meets(.high))
        #expect(AdvisorySeverity.critical.meets(.high))
        #expect(AdvisorySeverity.unknown.meets(.critical))
    }
}
