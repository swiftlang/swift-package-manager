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

/// Normalizes Swift package locations to the `SwiftURL` ecosystem package
/// name used by OSV databases: `host/path` with no scheme, credentials, port,
/// `.git` suffix or trailing slash. The host is lowercased; path case is preserved.
public enum SwiftURLName {
    /// Returns the normalized name, or nil if `location` has no scheme or scp-style host.
    public static func normalize(_ location: String) -> String? {
        var host = ""
        var path = ""

        if let schemeRange = location.range(of: "://") {
            var rest = String(location[schemeRange.upperBound...])
            let scheme = location[..<schemeRange.lowerBound]
            guard !scheme.isEmpty else { return nil }
            if scheme.lowercased() == "file" {
                host = ""
                path = rest
            } else {
                if let at = rest.firstIndex(of: "@"), at < (rest.firstIndex(of: "/") ?? rest.endIndex) {
                    rest = String(rest[rest.index(after: at)...])
                }
                let slash = rest.firstIndex(of: "/") ?? rest.endIndex
                host = String(rest[..<slash])
                path = String(rest[slash...])
                if let colon = host.firstIndex(of: ":") {
                    host = String(host[..<colon])
                }
            }
        } else if let at = location.firstIndex(of: "@"), let colon = location[at...].firstIndex(of: ":") {
            // scp-style: user@host:path
            host = String(location[location.index(after: at)..<colon])
            path = String(location[location.index(after: colon)...])
        } else {
            return nil
        }

        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix(".git") {
            path = String(path.dropLast(4))
        }
        let name = [host.lowercased(), path].filter { !$0.isEmpty }.joined(separator: "/")
        return name.isEmpty ? nil : name
    }
}
