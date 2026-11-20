//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// Git HTTP smart protocol and protocol v2 implementation for tag discovery.
// https://git-scm.com/docs/http-protocol
// https://git-scm.com/docs/protocol-v2

import Foundation

import struct TSCUtility.Version

// MARK: - Git HTTP Protocol v2

/// HTTP-based git protocol v2 helpers for tag discovery without forking
/// a `git` process.
package enum GitHTTPProtocolV2 {
    /// Builds the pkt-line encoded request body for a protocol v2 `ls-refs`
    /// command with ref-prefix hints for semver-like tags.
    ///
    /// Uses 20 `ref-prefix` lines (`refs/tags/0` through `refs/tags/9` plus
    /// `refs/tags/v0` through `refs/tags/v9`) as an optimization hint to
    /// reduce the response size. Per the spec, `ref-prefix` is advisory —
    /// servers MAY return refs not matching the prefix, so callers must
    /// still filter results (which `resolvedTags(from:)` does via
    /// `Version(tag:)`).
    package static func makeTagRefsRequestBody(serverCapabilities: [String] = []) -> Data {
        var body = Data()
        body.append(PktLine.encode("command=ls-refs\n"))
        if serverCapabilities.contains(where: { $0.hasPrefix("agent=") }) {
            body.append(PktLine.encode("agent=SwiftPackageManager/\(SwiftVersion.current.displayString)\n"))
        }
        body.append(PktLine.delimiter)
        body.append(PktLine.encode("peel\n"))
        for digit in 0...9 {
            body.append(PktLine.encode("ref-prefix refs/tags/\(digit)\n"))
            body.append(PktLine.encode("ref-prefix refs/tags/v\(digit)\n"))
        }
        body.append(PktLine.flush)
        return body
    }

    /// Constructs the smart HTTP endpoint URLs for a repository.
    ///
    /// Returns the `info/refs` discovery URL and the `git-upload-pack` URL,
    /// or `nil` for non-HTTP schemes (ssh, git, scp-style).
    package static func makeSmartHTTPURLs(
        from repoURL: String
    ) -> (infoRefs: URL, uploadPack: URL)? {
        guard let url = URL(string: repoURL) else { return nil }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }

        let base = repoURL.hasSuffix("/") ? String(repoURL.dropLast()) : repoURL
        guard let infoRefs = URL(string: "\(base)/info/refs?service=git-upload-pack"),
              let uploadPack = URL(string: "\(base)/git-upload-pack") else { return nil }
        return (infoRefs: infoRefs, uploadPack: uploadPack)
    }

    /// Parses protocol v2 `ls-refs` response lines directly into resolved
    /// tags with their commit SHAs.
    ///
    /// Each line has the format:
    /// ```
    /// <sha> refs/tags/<name>
    /// <sha> refs/tags/<name> peeled:<commit-sha>
    /// ```
    ///
    /// For annotated tags (with `peeled:` suffix), the peeled commit SHA is
    /// used. Lightweight tags use the SHA directly. Only tags that parse as
    /// valid semantic versions are included.
    package static func resolvedTags(from lines: [String]) -> [ResolvedTag] {
        let tagsPrefix = "refs/tags/"
        let peeledPrefix = "peeled:"
        var results: [ResolvedTag] = []
        for line in lines {
            // Split on ASCII space via UTF8 view to avoid Character-level scanning.
            let utf8 = line.utf8
            guard let firstSpace = utf8.firstIndex(of: UInt8(ascii: " ")) else { continue }
            let refStart = utf8.index(after: firstSpace)
            guard refStart < utf8.endIndex else { continue }

            // Find optional second space (peeled SHA follows it).
            let secondSpace = utf8[refStart...].firstIndex(of: UInt8(ascii: " "))
            let refEnd = secondSpace ?? utf8.endIndex
            let ref = line[refStart..<refEnd]

            guard ref.hasPrefix(tagsPrefix) else { continue }
            let tagName = String(ref.dropFirst(tagsPrefix.count))

            let sha: String
            if let sp = secondSpace {
                let rest = line[line.index(after: sp)...]
                if rest.hasPrefix(peeledPrefix) {
                    sha = String(rest.dropFirst(peeledPrefix.count))
                } else {
                    sha = String(line[utf8.startIndex..<firstSpace])
                }
            } else {
                sha = String(line[utf8.startIndex..<firstSpace])
            }

            guard let version = Version(tag: tagName) else { continue }
            results.append(ResolvedTag(name: tagName, commitSHA: sha, version: version))
        }
        return results
    }
}

// MARK: - Pkt-line Framing

/// Encoder and decoder for the git pkt-line framing format.
///
/// Each pkt-line is a 4-character hex length prefix (including the prefix
/// itself) followed by the payload. Special packets use fixed values:
/// `0000` (flush) terminates a message, `0001` (delimiter) separates
/// the command from its arguments.
///
/// See https://git-scm.com/docs/protocol-common#_pkt_line_format
package enum PktLine {
    /// Encodes a string as a single pkt-line.
    package static func encode(_ s: String) -> Data {
        let payload = Data(s.utf8)
        let len = payload.count + 4
        var d = Data(String(format: "%04x", len).utf8)
        d.append(payload)
        return d
    }

    package static let flush = Data("0000".utf8)
    package static let delimiter = Data("0001".utf8)

    private static let headerSize = 4

    /// Decodes pkt-line framed data into content strings.
    /// Flush and delimiter packets are skipped. Payloads that are not
    /// valid UTF-8 are decoded with replacement characters so that
    /// server error messages (e.g. `ERR`) are never silently lost.
    package static func decode(_ data: Data) -> [String] {
        var lines: [String] = []
        var i = data.startIndex
        while i + headerSize <= data.endIndex {
            guard let hex = String(data: data[i..<i + headerSize], encoding: .ascii),
                  let len = UInt16(hex, radix: 16) else { break }
            if len <= UInt16(headerSize) { i += headerSize; continue }
            var end = min(i + Int(len), data.endIndex)
            let payloadStart = i + headerSize
            // Strip trailing newline bytes directly from the data slice
            // instead of allocating through Foundation's trimmingCharacters.
            while end > payloadStart && (data[end - 1] == 0x0A || data[end - 1] == 0x0D) {
                end -= 1
            }
            if let line = String(data: data[payloadStart..<end], encoding: .utf8) {
                lines.append(line)
            } else {
                lines.append(String(decoding: data[payloadStart..<end], as: UTF8.self))
            }
            i = min(i + Int(len), data.endIndex)
        }
        return lines
    }
}
