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
    /// - Parameters:
    ///   - archiveData: The raw bytes of the source archive (typically the
    ///     `source-archive` multipart part of a publish request).
    ///   - maxManifestBytes: The maximum decompressed size of a single
    ///     manifest. Entries that inflate beyond this cap throw
    ///     ``ManifestExtractorError/manifestTooLarge`` instead of being
    ///     buffered in full.
    /// - Returns: A dictionary mapping manifest keys to file contents. The
    ///   default `Package.swift` manifest is stored under the empty-string
    ///   key `""`; version-qualified manifests are stored under their
    ///   Swift version string (for example, `"5.9"`).
    /// - Throws:
    ///   - ``ManifestExtractorError/invalidArchive`` if `archiveData` is
    ///     not a readable zip archive.
    ///   - ``ManifestExtractorError/manifestMissing`` if no `Package.swift`
    ///     is found at depth 1 or 2 within the archive.
    ///   - ``ManifestExtractorError/manifestTooLarge`` if a manifest's
    ///     decompressed size exceeds `maxManifestBytes`.
    public static func extract(
        from archiveData: Data,
        maxManifestBytes: Int = 1_048_576
    ) throws -> [String: String] {
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("registry-manifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let archiveURL = workingDirectory.appendingPathComponent("source.zip", isDirectory: false)
        try archiveData.write(to: archiveURL)

        var candidates: [(depth: Int, key: String, path: String)] = []
        for path in try listEntries(in: archiveURL) {
            let components = path.split(separator: "/")
            guard let filename = components.last.map(String.init) else { continue }
            let depth = components.count
            guard depth <= 2 else { continue }
            guard let key = manifestKey(from: filename) else { continue }
            candidates.append((depth, key, path))
        }
        candidates.sort { $0.depth < $1.depth || ($0.depth == $1.depth && $0.path < $1.path) }

        var manifests: [String: String] = [:]
        for candidate in candidates where manifests[candidate.key] == nil {
            manifests[candidate.key] = try readEntry(
                candidate.path,
                from: archiveURL,
                maxBytes: maxManifestBytes
            )
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

    /// Lists every entry path stored in the archive by shelling out to the
    /// platform's zip tooling.
    ///
    /// A non-zero exit status means the tool could not read the file as a
    /// zip archive, which is surfaced as ``ManifestExtractorError/invalidArchive``.
    private static func listEntries(in archiveURL: URL) throws -> [String] {
        let result = try run(listArguments(for: archiveURL))
        guard result.exitCode == 0 else {
            throw ManifestExtractorError.invalidArchive
        }
        return String(decoding: result.standardOutput, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    /// Extracts a single archive entry to standard output, capping the
    /// number of bytes read so a maliciously inflating manifest cannot be
    /// buffered without bound.
    private static func readEntry(_ path: String, from archiveURL: URL, maxBytes: Int) throws -> String {
        let result = try run(extractArguments(for: archiveURL, entry: path), byteLimit: maxBytes)
        if result.overflowed {
            throw ManifestExtractorError.manifestTooLarge
        }
        guard result.exitCode == 0 else {
            throw ManifestExtractorError.invalidArchive
        }
        return String(decoding: result.standardOutput, as: UTF8.self)
    }

    #if os(Windows)
    /// The libarchive-based `tar` bundled with Windows, which can read zip
    /// archives. Resolved out of `System32` to avoid picking up an
    /// incompatible `tar` earlier on `PATH` (e.g. from MSYS/Git for Windows).
    private static let archiveTool: String = {
        let command = "tar.exe"
        guard let systemRoot = ProcessInfo.processInfo.environment["SystemRoot"] else {
            return command
        }
        return systemRoot + "\\System32\\" + command
    }()

    private static func listArguments(for archiveURL: URL) -> [String] {
        [archiveTool, "-tf", archiveURL.path]
    }

    private static func extractArguments(for archiveURL: URL, entry: String) -> [String] {
        [archiveTool, "-xOf", archiveURL.path, entry]
    }
    #else
    private static func listArguments(for archiveURL: URL) -> [String] {
        ["unzip", "-Z1", archiveURL.path]
    }

    private static func extractArguments(for archiveURL: URL, entry: String) -> [String] {
        ["unzip", "-p", archiveURL.path, entry]
    }
    #endif

    private struct CommandResult {
        let exitCode: Int32
        let standardOutput: Data
        /// `true` when reading was stopped because standard output exceeded
        /// the configured byte limit.
        let overflowed: Bool
    }

    /// Runs a command and captures its standard output.
    ///
    /// - Parameters:
    ///   - arguments: The command to run, where the first element is the
    ///     executable. On Unix a bare executable name is resolved via
    ///     `/usr/bin/env`, matching how `unzip` is expected to be on `PATH`.
    ///   - byteLimit: When set, reading stops once standard output would
    ///     exceed this many bytes and the process is terminated. The result's
    ///     `overflowed` flag is then `true`.
    private static func run(_ arguments: [String], byteLimit: Int? = nil) throws -> CommandResult {
        let process = Process()
        let executable = arguments[0]
        #if os(Windows)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(arguments.dropFirst())
        #else
        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Array(arguments.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = arguments
        }
        #endif

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            throw ManifestExtractorError.invalidArchive
        }

        let outputHandle = standardOutput.fileHandleForReading
        var collected = Data()
        var overflowed = false
        while true {
            let chunk = outputHandle.availableData
            if chunk.isEmpty { break }
            guard let byteLimit else {
                collected.append(chunk)
                continue
            }
            let room = byteLimit - collected.count
            if chunk.count <= room {
                collected.append(chunk)
            } else {
                overflowed = true
                process.terminate()
                break
            }
        }

        _ = try? standardError.fileHandleForReading.readToEnd()
        process.waitUntilExit()

        return CommandResult(
            exitCode: process.terminationStatus,
            standardOutput: collected,
            overflowed: overflowed
        )
    }
}
