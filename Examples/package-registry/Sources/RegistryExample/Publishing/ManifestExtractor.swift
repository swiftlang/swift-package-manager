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
import ZIPFoundation

/// Errors that can be thrown while extracting manifests from a published
/// source archive.
public enum ManifestExtractorError: Error, Equatable, Sendable {
    /// The supplied bytes could not be opened as a readable zip archive.
    case invalidArchive
    /// The archive is a valid zip but does not contain a top-level
    /// `Package.swift` manifest, so it cannot be accepted by §4.6
    /// *Create a package release*.
    case manifestMissing
    /// A manifest entry's decompressed size exceeded the configured cap.
    /// Surfaced as `422 Unprocessable Entity` and guards against
    /// zip-bomb archives whose `Package.swift` inflates without bound
    /// (SE-0321 §Tampering).
    case manifestTooLarge
}

/// Extracts Swift package manifests from the `source-archive` submitted to
/// the `PUT /{scope}/{name}/{version}` publish endpoint (§4.6 of the Swift
/// Package Registry Service Specification).
///
/// The extractor looks for manifest files at either the root of the
/// archive or exactly one directory level below it (for archives whose
/// contents are wrapped in a top-level directory, as produced by
/// `git archive`). It recognizes:
///
/// - `Package.swift`, the default manifest, stored under the empty-string
///   key in the returned dictionary.
/// - `Package@swift-{version}.swift`, a version-qualified manifest
///   (§4.3), where `{version}` is a 1-3 component numeric Swift version
///   such as `5`, `5.9`, or `5.9.0`. Stored under the `{version}` key.
///
/// When the same manifest key appears at both depth 1 and depth 2, the
/// shallower entry wins; ties at the same depth are broken by
/// lexicographic path ordering. A valid archive MUST contribute a
/// `Package.swift` entry, otherwise ``ManifestExtractorError/manifestMissing``
/// is thrown, matching the `422 Unprocessable Entity`
/// `"package doesn't contain a valid manifest"` response required by
/// §4.6.
public enum ManifestExtractor {
    /// Extracts the package manifests from a source archive.
    ///
    /// - Parameter archiveData: The raw bytes of the source archive
    ///   (typically the `source-archive` multipart part of a publish
    ///   request).
    /// - Returns: A dictionary mapping manifest keys to file contents. The
    ///   default `Package.swift` manifest is stored under the empty-string
    ///   key `""`; version-qualified manifests are stored under their
    ///   Swift version string (for example, `"5.9"`).
    /// - Throws:
    ///   - ``ManifestExtractorError/invalidArchive`` if `archiveData` is
    ///     not a readable zip archive.
    ///   - ``ManifestExtractorError/manifestMissing`` if no `Package.swift`
    ///     is found at depth 1 or 2 within the archive.
    ///   - Any error thrown by ZIPFoundation while reading entry
    ///     contents.
    public static func extract(
        from archiveData: Data,
        maxManifestBytes: Int = 1_048_576
    ) throws -> [String: String] {
        let archive: Archive
        do {
            archive = try Archive(data: archiveData, accessMode: .read)
        } catch {
            throw ManifestExtractorError.invalidArchive
        }

        var candidates: [(depth: Int, key: String, path: String, entry: Entry)] = []
        for entry in archive where entry.type == .file {
            let path = entry.path
            let components = path.split(separator: "/")
            guard let filename = components.last.map(String.init) else { continue }
            let depth = components.count
            guard depth <= 2 else { continue }
            guard let key = manifestKey(from: filename) else { continue }
            candidates.append((depth, key, path, entry))
        }
        candidates.sort { $0.depth < $1.depth || ($0.depth == $1.depth && $0.path < $1.path) }

        var manifests: [String: String] = [:]
        for candidate in candidates where manifests[candidate.key] == nil {
            let contents = try readEntry(candidate.entry, from: archive, maxBytes: maxManifestBytes)
            manifests[candidate.key] = contents
        }

        guard manifests[""] != nil else {
            throw ManifestExtractorError.manifestMissing
        }
        return manifests
    }

    private static func manifestKey(from filename: String) -> String? {
        if filename == "Package.swift" { return "" }
        let prefix = "Package@swift-"
        let suffix = ".swift"
        guard filename.hasPrefix(prefix), filename.hasSuffix(suffix) else { return nil }
        let start = filename.index(filename.startIndex, offsetBy: prefix.count)
        let end = filename.index(filename.endIndex, offsetBy: -suffix.count)
        let version = String(filename[start..<end])
        guard isValidSwiftVersion(version) else { return nil }
        return version
    }

    private static func isValidSwiftVersion(_ version: String) -> Bool {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    private static func readEntry(_ entry: Entry, from archive: Archive, maxBytes: Int) throws -> String {
        var buffer = Data()
        var overflow = false
        _ = try archive.extract(entry) { chunk in
            if overflow { return }
            let room = maxBytes - buffer.count
            if chunk.count <= room {
                buffer.append(chunk)
            } else {
                overflow = true
            }
        }
        if overflow {
            throw ManifestExtractorError.manifestTooLarge
        }
        return String(decoding: buffer, as: UTF8.self)
    }
}
