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

import struct TSCUtility.Version

/// A single package (or commit) to look up in an advisory database.
public struct AdvisoryQuery: Hashable, Sendable {
    /// Normalized `SwiftURL` package name.
    public let name: String
    public let version: Version?
    public let commit: String?

    public init(name: String, version: Version? = nil, commit: String? = nil) {
        self.name = name
        self.version = version
        self.commit = commit
    }
}

/// A source of OSV-format advisories.
public protocol AdvisoryDatabase: Sendable {
    /// A human-readable name of the source, used in diagnostics.
    var displayName: String { get }

    /// Whether the database can answer queries by commit hash.
    var supportsCommitQueries: Bool { get }

    /// Returns the non-withdrawn advisories affecting each query.
    ///
    /// Every answered query is a key in the result (with an empty array when clean).
    /// Queries a database cannot answer are absent from the result.
    func advisories(for queries: [AdvisoryQuery]) async throws -> [AdvisoryQuery: [OSVRecord]]
}

public enum AuditError: Error, CustomStringConvertible {
    case unsupportedAdvisoryDatabaseURL(URL)
    case advisorySourceFailed(source: String, package: String?, underlying: String)

    public var description: String {
        switch self {
        case .unsupportedAdvisoryDatabaseURL(let url):
            return "unsupported advisory database URL '\(url.absoluteString)'; use an https:// URL or a file:// URL"
        case .advisorySourceFailed(let source, let package, let underlying):
            let subject = package.map { " for '\($0)'" } ?? ""
            return "advisory source '\(source)' failed\(subject): \(underlying)"
        }
    }
}

/// Creates the database matching the URL scheme: `https` for an OSV API, `file` for local records.
public func makeAdvisoryDatabase(
    url: URL,
    httpClient: HTTPClient,
    fileSystem: any FileSystem
) throws -> any AdvisoryDatabase {
    switch url.scheme?.lowercased() {
    case "https":
        return OSVAPIDatabase(baseURL: url, httpClient: httpClient)
    case "file":
        return try OSVLocalDatabase(location: AbsolutePath(validating: url.path), fileSystem: fileSystem)
    default:
        throw AuditError.unsupportedAdvisoryDatabaseURL(url)
    }
}
