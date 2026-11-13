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
@testable import PackageAudit
import Testing

import struct TSCBasic.StringError

import struct TSCUtility.Version

@Suite
struct OSVLocalDatabaseTests {
    private func record(id: String, name: String, fixed: String, withdrawn: String? = nil) -> String {
        """
        {"id":"\(id)",\(withdrawn.map { "\"withdrawn\":\"\($0)\"," } ?? "")"unknown":1,
         "affected":[{"package":{"ecosystem":"SwiftURL","name":"\(name)"},
         "ranges":[{"type":"SEMVER","events":[{"introduced":"0"},{"fixed":"\(fixed)"}]}]}]}
        """
    }

    private func writeFixtures(to dir: AbsolutePath) throws {
        try localFileSystem.writeFileContents(dir.appending("a.json"), string: record(id: "A-1", name: "github.com/a/b", fixed: "1.5.0"))
        try localFileSystem.writeFileContents(dir.appending("b.json"), string: record(id: "B-1", name: "github.com/other/c", fixed: "9.0.0"))
        try localFileSystem.writeFileContents(dir.appending("w.json"), string: record(id: "W-1", name: "github.com/a/b", fixed: "9.0.0", withdrawn: "2025-01-01T00:00:00Z"))
        try localFileSystem.writeFileContents(dir.appending("notes.txt"), string: "ignored")
    }

    @Test
    func localDirectoryAndZip() async throws {
        try await withTemporaryDirectory(removeTreeOnDeinit: true) { tmp in
            let dir = tmp.appending("db")
            try localFileSystem.createDirectory(dir)
            try self.writeFixtures(to: dir)
            let zip = tmp.appending("db.zip")
            try await ZipArchiver(fileSystem: localFileSystem).compress(
                paths: try localFileSystem.getDirectoryContents(dir).map { try RelativePath(validating: $0) },
                from: dir,
                to: zip
            )

            let vulnerable = AdvisoryQuery(name: "github.com/a/b", version: Version(1, 4, 0))
            let fixed = AdvisoryQuery(name: "github.com/a/b", version: Version(1, 5, 0))
            let unrelated = AdvisoryQuery(name: "github.com/nothing/here", version: Version(1, 0, 0))
            let commit = AdvisoryQuery(name: "github.com/a/b", commit: "abc")
            let queries = [vulnerable, fixed, unrelated, commit]

            let fromDir = try await OSVLocalDatabase(location: dir, fileSystem: localFileSystem).advisories(for: queries)
            let fromZip = try await OSVLocalDatabase(location: zip, fileSystem: localFileSystem).advisories(for: queries)

            #expect(fromDir == fromZip)
            #expect(fromDir[vulnerable]?.map(\.id) == ["A-1"])
            #expect(fromDir[fixed] == [])
            #expect(fromDir[unrelated] == [])
            #expect(fromDir[commit] == nil)
            #expect(try !OSVLocalDatabase(location: dir, fileSystem: localFileSystem).supportsCommitQueries)
        }.value
    }

    @Test
    func factoryBuildsLocalAndRejectsOthers() async throws {
        let client = HTTPClient(implementation: { _, _ in throw StringError("unexpected") })
        try await withTemporaryDirectory(removeTreeOnDeinit: true) { tmp in
            let db = try makeAdvisoryDatabase(url: tmp.asURL, httpClient: client, fileSystem: localFileSystem)
            #expect(db is OSVLocalDatabase)
        }.value
        #expect(throws: AuditError.self) {
            try makeAdvisoryDatabase(url: URL(string: "ftp://x/y")!, httpClient: client, fileSystem: localFileSystem)
        }
    }
}
