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

import struct TSCBasic.StringError

/// An `AdvisoryDatabase` backed by a directory of OSV `*.json` records, or a `.zip` of them.
public struct OSVLocalDatabase: AdvisoryDatabase {
    private let location: AbsolutePath
    private let fileSystem: any FileSystem

    public init(location: AbsolutePath, fileSystem: any FileSystem) throws {
        guard fileSystem.exists(location) else {
            throw AuditError.advisorySourceFailed(
                source: location.pathString,
                package: nil,
                underlying: "no such file or directory"
            )
        }
        self.location = location
        self.fileSystem = fileSystem
    }

    public var displayName: String { self.location.pathString }
    public var supportsCommitQueries: Bool { false }

    public func advisories(for queries: [AdvisoryQuery]) async throws -> [AdvisoryQuery: [OSVRecord]] {
        let records = try await self.loadRecords()
        var output: [AdvisoryQuery: [OSVRecord]] = [:]
        for query in queries {
            // Commit queries cannot be answered locally; leave them out so callers report them unchecked.
            guard let version = query.version else { continue }
            output[query] = records.filter { $0.affects(version, packageName: query.name) }
        }
        return output
    }

    private func loadRecords() async throws -> [OSVRecord] {
        do {
            if self.fileSystem.isDirectory(self.location) {
                return try self.readRecords(in: self.location)
            }
            guard self.location.extension?.lowercased() == "zip" else {
                throw StringError("expected a directory or a .zip file")
            }
            let location = self.location
            let fileSystem = self.fileSystem
            return try await withTemporaryDirectory(
                fileSystem: fileSystem,
                prefix: "audit-db",
                removeTreeOnDeinit: true
            ) { directory in
                try await ZipArchiver(fileSystem: fileSystem).extract(from: location, to: directory)
                return try Self.readRecords(in: directory, fileSystem: fileSystem)
            }.value
        } catch {
            throw AuditError.advisorySourceFailed(
                source: self.displayName,
                package: nil,
                underlying: "\(error)"
            )
        }
    }

    private func readRecords(in directory: AbsolutePath) throws -> [OSVRecord] {
        try Self.readRecords(in: directory, fileSystem: self.fileSystem)
    }

    private static func readRecords(in directory: AbsolutePath, fileSystem: any FileSystem) throws -> [OSVRecord] {
        let decoder = JSONDecoder.makeWithDefaults()
        var records: [OSVRecord] = []
        for name in try fileSystem.getDirectoryContents(directory).sorted() {
            let path = directory.appending(component: name)
            if fileSystem.isDirectory(path) {
                records.append(contentsOf: try readRecords(in: path, fileSystem: fileSystem))
            } else if path.extension?.lowercased() == "json" {
                let data: Data = try fileSystem.readFileContents(path)
                do {
                    let record = try decoder.decode(OSVRecord.self, from: data)
                    if record.withdrawn == nil { records.append(record) }
                } catch {
                    throw StringError("\(path.pathString): \(error)")
                }
            }
        }
        return records
    }
}
