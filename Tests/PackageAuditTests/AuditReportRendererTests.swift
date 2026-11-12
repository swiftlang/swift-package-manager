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

import Basics
import Foundation
import PackageModel
@testable import PackageAudit
import Testing

import struct TSCUtility.Version

@Suite
struct AuditReportRendererTests {
    private let regexPackage = AuditedPackage(
        identity: .plain("regex"),
        kind: .sourceControl(url: "https://github.com/example/RegEx"),
        state: .version(Version(1, 4, 2)),
        paths: [["MyApp", "PatternMatcher", "RegEx"]]
    )
    private let netKitPackage = AuditedPackage(
        identity: .plain("mona.NetKit"),
        kind: .registry(identity: .plain("mona.NetKit"), registryURL: URL(string: "https://registry.example.com")),
        state: .version(Version(2, 8, 0)),
        paths: [["MyApp", "NetKit"]]
    )

    private func twoFindingReport(extraFindings: [AuditFinding] = []) throws -> AuditReport {
        let regex = AuditFinding(
            package: self.regexPackage,
            advisory: OSVRecord(
                id: "GHSA-xxxx-xxxx-xxxx",
                aliases: ["CVE-2026-12345"],
                summary: "Regular expression denial of service in RegEx"
            ),
            severity: .high,
            sources: ["https://api.osv.dev"],
            fixedVersions: [Version(1, 4, 3)],
            ignored: false,
            fixClassification: .update
        )
        let netKit = AuditFinding(
            package: self.netKitPackage,
            advisory: OSVRecord(
                id: "GHSA-yyyy-yyyy-yyyy",
                summary: "Improper certificate validation in NetKit",
                references: [
                    .init(type: "WEB", url: "https://example.com/other"),
                    .init(type: "ADVISORY", url: "https://registry.example.com/advisories/yyyy"),
                ]
            ),
            severity: .moderate,
            sources: ["https://registry.example.com"],
            fixedVersions: [Version(3, 0, 0)],
            ignored: false,
            fixClassification: .manifest
        )
        let local = UncheckedPackage(
            package: AuditedPackage(
                identity: .plain("localkit"),
                kind: .local(path: try AbsolutePath(validating: "/work/LocalKit")),
                state: .none
            ),
            reason: "local dependency"
        )
        return AuditReport(scannedPackages: 14, findings: [regex, netKit] + extraFindings, unchecked: [local])
    }

    @Test
    func textMatchesSpecExample() throws {
        let expected = """
        High      GHSA-xxxx-xxxx-xxxx (CVE-2026-12345)
                  Regular expression denial of service in RegEx
        Package   https://github.com/example/RegEx 1.4.2
        Path      MyApp > PatternMatcher > RegEx
        Fixed in  1.4.3
        Fix       Run `swift package audit fix` (within current requirements)
        More info https://osv.dev/vulnerability/GHSA-xxxx-xxxx-xxxx

        Moderate  GHSA-yyyy-yyyy-yyyy
                  Improper certificate validation in NetKit
        Package   mona.NetKit 2.8.0 (registry)
        Path      MyApp > NetKit
        Fixed in  3.0.0
        Fix       Requires changing the requirement in Package.swift (major version)
        More info https://registry.example.com/advisories/yyyy

        Found 2 vulnerabilities (1 moderate, 1 high) in 14 scanned packages.
        1 package could not be checked; run with --verbose for details.

        """
        #expect(AuditReportRenderer.text(try self.twoFindingReport(), verbose: false) == expected)
    }

    @Test
    func textNoFindings() {
        let report = AuditReport(scannedPackages: 3, findings: [], unchecked: [])
        #expect(
            AuditReportRenderer.text(report, verbose: false)
                == "No known vulnerabilities found in 3 scanned packages.\n"
        )
    }

    @Test
    func textFixLineVariants() throws {
        func render(_ classification: FixClassification?, fixed: [Version]) -> String {
            let finding = AuditFinding(
                package: self.regexPackage,
                advisory: OSVRecord(id: "A-1"),
                severity: .low,
                sources: [],
                fixedVersions: fixed,
                ignored: false,
                fixClassification: classification
            )
            return AuditReportRenderer.text(
                AuditReport(scannedPackages: 1, findings: [finding], unchecked: []),
                verbose: false
            )
        }
        #expect(render(.upstream(blockedBy: ["A", "B"]), fixed: [Version(1, 4, 3)])
            .contains("Fix       Blocked by A, B\n"))
        // No specific blocker was found.
        #expect(render(.upstream(blockedBy: []), fixed: [Version(1, 4, 3)]).contains(
            "Fix       No resolution avoids the vulnerable versions within current requirements; try `swift package update`\n"
        ))
        #expect(render(FixClassification.none, fixed: []).contains("Fix       No patched version is available\n"))
        #expect(!render(FixClassification.none, fixed: []).contains("Fixed in"))
        // Same major: no suffix.
        #expect(render(.manifest, fixed: [Version(1, 5, 0)])
            .contains("Fix       Requires changing the requirement in Package.swift\n"))
        // Unclassified findings have no Fix line.
        #expect(!render(nil, fixed: [Version(1, 4, 3)]).contains("Fix  "))
        // Singular wording.
        #expect(render(nil, fixed: []).contains("Found 1 vulnerability (1 low) in 1 scanned package.\n"))
    }

    @Test
    func ignoredFindingsOnlyInVerboseText() throws {
        let ignored = AuditFinding(
            package: self.regexPackage,
            advisory: OSVRecord(id: "GHSA-ignored"),
            severity: .low,
            sources: [],
            fixedVersions: [],
            ignored: true
        )
        let report = try self.twoFindingReport(extraFindings: [ignored])
        #expect(!AuditReportRenderer.text(report, verbose: false).contains("GHSA-ignored"))
        let verbose = AuditReportRenderer.text(report, verbose: true)
        #expect(verbose.contains("GHSA-ignored"))
        #expect(verbose.contains("LocalKit"))
        #expect(verbose.contains("local dependency"))
    }

    private func finding(_ id: String, _ severity: AdvisorySeverity, ignored: Bool) -> AuditFinding {
        AuditFinding(
            package: self.regexPackage,
            advisory: OSVRecord(id: id),
            severity: severity,
            sources: [],
            fixedVersions: [],
            ignored: ignored
        )
    }

    @Test
    func verboseSummaryExcludesIgnoredFindings() {
        let report = AuditReport(
            scannedPackages: 5,
            findings: [self.finding("A-1", .high, ignored: false), self.finding("A-2", .moderate, ignored: true)],
            unchecked: []
        )
        let text = AuditReportRenderer.text(report, verbose: true)
        #expect(text.contains("A-2"))
        #expect(text.hasSuffix(
            "Found 1 vulnerability (1 high) in 5 scanned packages.\n1 ignored advisory not counted.\n"
        ))
    }

    @Test
    func allIgnoredNonVerboseMentionsIgnored() {
        let report = AuditReport(
            scannedPackages: 5,
            findings: [self.finding("A-1", .high, ignored: true), self.finding("A-2", .low, ignored: true)],
            unchecked: []
        )
        #expect(AuditReportRenderer.text(report, verbose: false) == """
        No known vulnerabilities found in 5 scanned packages.
        2 ignored advisories not counted. Run with --verbose to show them.

        """)
    }

    @Test
    func jsonShape() throws {
        let ignored = AuditFinding(
            package: self.regexPackage,
            advisory: OSVRecord(id: "GHSA-ignored", databaseSpecific: .init(severity: "LOW")),
            severity: .low,
            sources: [],
            fixedVersions: [],
            ignored: true
        )
        let json = try AuditReportRenderer.json(self.twoFindingReport(extraFindings: [ignored]))
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        #expect(object["version"] as? Int == 1)
        #expect(object["scannedPackages"] as? Int == 14)

        let findings = try #require(object["findings"] as? [[String: Any]])
        #expect(findings.count == 3)
        let first = findings[0]
        let package = try #require(first["package"] as? [String: Any])
        #expect(package["kind"] as? String == "remoteSourceControl")
        #expect(package["identity"] as? String == "regex")
        #expect(package["location"] as? String == "https://github.com/example/RegEx")
        #expect(package["version"] as? String == "1.4.2")
        #expect(first["fixClassification"] as? String == "update")
        #expect(first["severity"] as? String == "high")
        #expect(first["paths"] as? [[String]] == [["MyApp", "PatternMatcher", "RegEx"]])
        #expect(first["fixedVersions"] as? [String] == ["1.4.3"])
        #expect(first["ignored"] as? Bool == false)
        #expect((first["advisory"] as? [String: Any])?["id"] as? String == "GHSA-xxxx-xxxx-xxxx")

        let registryPackage = try #require(findings[1]["package"] as? [String: Any])
        #expect(registryPackage["kind"] as? String == "registry")
        #expect(registryPackage["location"] as? String == "mona.NetKit")
        #expect(findings[1]["fixClassification"] as? String == "manifest")

        #expect(findings[2]["ignored"] as? Bool == true)
        #expect(findings[2]["fixClassification"] == nil)
        let advisory = try #require(findings[2]["advisory"] as? [String: Any])
        #expect((advisory["database_specific"] as? [String: Any])?["severity"] as? String == "LOW")

        let unchecked = try #require(object["unchecked"] as? [[String: Any]])
        #expect(unchecked[0]["reason"] as? String == "local dependency")
        let uncheckedPackage = try #require(unchecked[0]["package"] as? [String: Any])
        #expect(uncheckedPackage["kind"] as? String == "fileSystem")
        #expect(uncheckedPackage["location"] as? String == "/work/LocalKit")
    }

    @Test
    func jsonAdvisoryIsTheSourceRecord() throws {
        // Fields the client does not model must be kept, at the top level and nested.
        let source = #"""
        {"id":"GHSA-raw","schema_version":"1.6.0","modified":"2026-01-01T00:00:00Z","summary":"s",
         "affected":[{"package":{"ecosystem":"SwiftURL","name":"github.com/example/regex","purl":"pkg:swift/x"},
          "ranges":[{"type":"SEMVER","events":[{"introduced":"0"},{"fixed":"1.4.3"}]}],
          "ecosystem_specific":{"flags":[1,2.5,true,null,"x"],"big":9007199254740993}}],
         "database_specific":{"severity":"HIGH","cwe_ids":["CWE-1333"]}}
        """#
        struct Wrapper: Decodable { let advisories: [OSVRecord] }
        let decoder = JSONDecoder()
        let records = [
            try decoder.decode(OSVRecord.self, from: Data(source.utf8)),
            // Registry responses nest the records.
            try decoder.decode(Wrapper.self, from: Data(#"{"advisories":[\#(source)]}"#.utf8)).advisories[0],
        ]
        let expected = try #require(JSONSerialization.jsonObject(with: Data(source.utf8)) as? NSDictionary)

        for record in records {
            #expect(record.databaseSpecific?.severity == "HIGH")
            let finding = AuditFinding(
                package: self.regexPackage,
                advisory: record,
                severity: .high,
                sources: [],
                fixedVersions: [Version(1, 4, 3)],
                ignored: false
            )
            let json = try AuditReportRenderer.json(AuditReport(scannedPackages: 1, findings: [finding], unchecked: []))
            let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            let findings = try #require(object["findings"] as? [[String: Any]])
            let advisory = try #require(findings.first?["advisory"] as? NSDictionary)
            #expect(advisory.isEqual(expected), "\(advisory)")
            #expect(json.contains("9007199254740993"))
        }
    }

    @Test
    func jsonFileURLIsLocalSourceControl() throws {
        let package = AuditedPackage(
            identity: .plain("mirror"),
            kind: .sourceControl(url: "file:///tmp/mirror"),
            state: .revision("abc123")
        )
        let report = AuditReport(
            scannedPackages: 1,
            findings: [],
            unchecked: [UncheckedPackage(package: package, reason: "revision pin")]
        )
        let json = try AuditReportRenderer.json(report)
        #expect(json.contains("\"kind\" : \"localSourceControl\""))
        #expect(json.contains("\"revision\" : \"abc123\""))
    }
}
