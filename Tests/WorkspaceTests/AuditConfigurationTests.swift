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
import Testing
import Workspace

import _InternalTestSupport

struct AuditConfigurationTests {
    private let localFile = AbsolutePath("/package/.swiftpm/configuration/audit.json")
    private let sharedFile = AbsolutePath("/shared/configuration/audit.json")

    private func makeConfiguration(_ fs: FileSystem) throws -> Workspace.Configuration.Audit {
        try Workspace.Configuration.Audit(
            fileSystem: fs,
            localAuditFile: self.localFile,
            sharedAuditFile: self.sharedFile
        )
    }

    @Test
    func defaultLocations() {
        let configurationDirectory = AbsolutePath("/config")
        #expect(
            Workspace.DefaultLocations.auditConfigurationFile(at: configurationDirectory)
                == AbsolutePath("/config/audit.json")
        )
        #expect(
            Workspace.DefaultLocations.auditConfigurationFile(forRootPackage: AbsolutePath("/package"))
                == self.localFile
        )
    }

    @Test
    func nothingConfigured() throws {
        let fs = InMemoryFileSystem()
        let config = try self.makeConfiguration(fs)
        #expect(config.advisoryDatabase == nil)
    }

    @Test
    func sharedValueIsUsedWithoutLocalValue() throws {
        let fs = InMemoryFileSystem()
        let config = try self.makeConfiguration(fs)
        try config.updateShared { $0.advisoryDatabase = "https://shared.example.com" }

        #expect(config.advisoryDatabase == "https://shared.example.com")
        #expect(fs.exists(self.sharedFile))
        #expect(!fs.exists(self.localFile))

        // A fresh instance reads the persisted value.
        #expect(try self.makeConfiguration(fs).advisoryDatabase == "https://shared.example.com")
    }

    @Test
    func localValueTakesPrecedenceOverShared() throws {
        let fs = InMemoryFileSystem()
        let config = try self.makeConfiguration(fs)
        try config.updateShared { $0.advisoryDatabase = "https://shared.example.com" }
        try config.updateLocal { $0.advisoryDatabase = "file:///local/osv" }

        #expect(config.advisoryDatabase == "file:///local/osv")
        #expect(try self.makeConfiguration(fs).advisoryDatabase == "file:///local/osv")
    }

    @Test
    func storedFormat() throws {
        let fs = InMemoryFileSystem()
        let config = try self.makeConfiguration(fs)
        try config.updateLocal { $0.advisoryDatabase = "https://osv.example.com" }

        let data: Data = try fs.readFileContents(self.localFile)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.count == 1)
        #expect(object["advisoryDatabase"] as? String == "https://osv.example.com")
    }

    @Test
    func unsetRemovesFile() throws {
        let fs = InMemoryFileSystem()
        let config = try self.makeConfiguration(fs)
        try config.updateShared { $0.advisoryDatabase = "https://shared.example.com" }
        try config.updateLocal { $0.advisoryDatabase = "file:///local/osv" }

        try config.updateLocal { $0.advisoryDatabase = nil }
        #expect(!fs.exists(self.localFile))
        #expect(config.advisoryDatabase == "https://shared.example.com")

        try config.updateShared { $0.advisoryDatabase = nil }
        #expect(!fs.exists(self.sharedFile))
        #expect(config.advisoryDatabase == nil)
    }

    @Test
    func sharedOnlyConfiguration() throws {
        let fs = InMemoryFileSystem()
        try self.makeConfiguration(fs).updateLocal { $0.advisoryDatabase = "file:///local/osv" }

        let shared = try Workspace.Configuration.Audit(
            fileSystem: fs,
            localAuditFile: nil,
            sharedAuditFile: self.sharedFile
        )
        #expect(shared.advisoryDatabase == nil)
    }
}
