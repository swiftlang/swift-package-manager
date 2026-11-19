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

import struct TSCUtility.Version

@Suite
struct OSVRangeTests {
    private typealias Event = OSVRecord.Event

    private func record(
        name: String = "https://github.com/example/pkg.git",
        ranges: [[Event]] = [],
        versions: [String]? = nil,
        extra: [OSVRecord.Affected] = []
    ) -> OSVRecord {
        let affected = OSVRecord.Affected(
            package: .init(ecosystem: "SwiftURL", name: name),
            ranges: ranges.map { .init(type: "SEMVER", events: $0) },
            versions: versions
        )
        return OSVRecord(id: "TEST-1", affected: [affected] + extra)
    }

    @Test
    func introducedFixed() {
        let r = record(ranges: [[Event(introduced: "0"), Event(fixed: "1.4.3")]])
        #expect(r.affects(Version(1, 4, 2), packageName: nil))
        #expect(!r.affects(Version(1, 4, 3), packageName: nil))
        #expect(r.fixedVersions(after: Version(1, 4, 2), packageName: nil) == [Version(1, 4, 3)])
    }

    @Test
    func prereleaseAndLastAffected() throws {
        let r = record(ranges: [[Event(introduced: "2.0.0-alpha"), Event(lastAffected: "2.0.0-beta.2")]])
        #expect(r.affects(try #require(Version("2.0.0-beta.1")), packageName: nil))
        #expect(r.affects(try #require(Version("2.0.0-beta.2")), packageName: nil))
        #expect(!r.affects(try #require(Version("2.0.0-beta.3")), packageName: nil))
        #expect(r.affects(try #require(Version("2.0.0-alpha")), packageName: nil))
        #expect(!r.affects(Version(1, 9, 9), packageName: nil))
        #expect(!r.affects(Version(2, 0, 0), packageName: nil))

        let limited = record(ranges: [[Event(introduced: "0"), Event(limit: "3.0.0")]])
        #expect(limited.affects(Version(2, 9, 9), packageName: nil))
        #expect(!limited.affects(Version(3, 0, 0), packageName: nil))
        let ranges = limited.vulnerableRanges(packageName: nil)
        #expect(ranges.count == 1)
        #expect(ranges.first?.upperBound == Version(3, 0, 0))
    }

    @Test
    func prereleaseOfFixedVersionIsAffected() throws {
        let r = record(ranges: [[Event(introduced: "0"), Event(fixed: "1.4.3")]])
        #expect(r.affects(try #require(Version("1.4.3-rc.1")), packageName: nil))
    }

    @Test
    func nonSemverRangesAreSkipped() {
        let affected = OSVRecord.Affected(
            package: .init(ecosystem: "SwiftURL", name: "https://github.com/example/pkg.git"),
            ranges: [.init(type: "GIT", events: [Event(introduced: "0"), Event(fixed: "1.0.0")])]
        )
        let r = OSVRecord(id: "TEST-2", affected: [affected])
        #expect(!r.affects(Version(0, 5, 0), packageName: nil))
        #expect(r.vulnerableRanges(packageName: nil).isEmpty)
        #expect(r.fixedVersions(after: Version(0, 5, 0), packageName: nil).isEmpty)
    }

    @Test
    func otherEcosystemDoesNotMatch() {
        let affected = OSVRecord.Affected(
            package: .init(ecosystem: "npm", name: "https://github.com/example/pkg.git"),
            ranges: [.init(type: "SEMVER", events: [Event(introduced: "0"), Event(fixed: "1.0.0")])]
        )
        let r = OSVRecord(id: "TEST-3", affected: [affected])
        #expect(!r.affects(Version(0, 5, 0), packageName: "https://github.com/example/pkg.git"))
        #expect(r.affects(Version(0, 5, 0), packageName: nil))
    }

    @Test
    func multipleRangesAndExplicitVersions() {
        let r = record(
            ranges: [
                [Event(introduced: "1.0.0"), Event(fixed: "1.2.0")],
                [Event(introduced: "2.0.0"), Event(fixed: "2.1.0")],
            ],
            versions: ["0.9.0"]
        )
        #expect(r.affects(Version(0, 9, 0), packageName: nil))
        #expect(r.affects(Version(2, 0, 5), packageName: nil))
        #expect(!r.affects(Version(1, 5, 0), packageName: nil))
        #expect(r.vulnerableRanges(packageName: nil) == [
            Version(1, 0, 0)..<Version(1, 2, 0),
            Version(2, 0, 0)..<Version(2, 1, 0),
        ])
    }

    @Test
    func packageNameFiltering() {
        let other = OSVRecord.Affected(
            package: .init(ecosystem: "SwiftURL", name: "https://github.com/other/pkg.git"),
            ranges: [.init(type: "SEMVER", events: [Event(introduced: "0"), Event(fixed: "5.0.0")])],
            versions: nil
        )
        let r = record(ranges: [[Event(introduced: "0"), Event(fixed: "1.0.0")]], extra: [other])
        let name = "https://github.com/example/pkg.git"
        #expect(!r.affects(Version(3, 0, 0), packageName: name))
        #expect(r.affects(Version(0, 5, 0), packageName: name))
        #expect(r.affects(Version(3, 0, 0), packageName: nil))
        #expect(!r.affects(Version(1, 0, 0), packageName: "https://github.com/nobody/x.git"))
    }

    @Test
    func decodesGHSAExample() throws {
        let json = """
        {
          "schema_version": "1.4.0",
          "id": "GHSA-xxxx-yyyy-zzzz",
          "modified": "2024-01-01T00:00:00Z",
          "published": "2023-12-01T00:00:00Z",
          "aliases": ["CVE-2023-0001"],
          "summary": "Example",
          "details": "Details",
          "severity": [{"type": "CVSS_V3", "score": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"}],
          "affected": [{
            "package": {"ecosystem": "SwiftURL", "name": "https://github.com/example/pkg.git"},
            "ranges": [{"type": "SEMVER", "events": [{"introduced": "0"}, {"fixed": "1.4.3"}]}],
            "database_specific": {"source": "x"}
          }],
          "references": [{"type": "ADVISORY", "url": "https://example.com"}],
          "database_specific": {"severity": "HIGH", "cwe_ids": ["CWE-79"], "github_reviewed": true}
        }
        """
        let r = try JSONDecoder().decode(OSVRecord.self, from: Data(json.utf8))
        #expect(r.id == "GHSA-xxxx-yyyy-zzzz")
        #expect(r.aliases == ["CVE-2023-0001"])
        #expect(r.databaseSpecific?.severity == "HIGH")
        #expect(r.severity?.first?.type == "CVSS_V3")
        #expect(r.references?.first?.url == "https://example.com")
        #expect(r.affects(Version(1, 0, 0), packageName: "https://github.com/example/pkg.git"))
    }
}
