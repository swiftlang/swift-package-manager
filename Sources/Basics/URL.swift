//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Foundation.URL

extension URL {
    /// Returns the path of the file URL.
    ///
    /// This should always be used whenever the file path equivalent of a URL is needed. DO NOT use ``path`` or ``path(percentEncoded:)``, as these deal in terms of the path portion of the URL representation per RFC8089, which on Windows would include a leading slash.
    ///
    /// - throws: ``FileURLError`` if the URL does not represent a file or its path is otherwise not representable.
    public var filePath: AbsolutePath {
        get throws {
            guard isFileURL else {
                throw FileURLError.notRepresentable(self)
            }
            return try withUnsafeFileSystemRepresentation { cString in
                guard let cString else {
                    throw FileURLError.notRepresentable(self)
                }
                return try AbsolutePath(validating: String(cString: cString))
            }
        }
    }

    /// Whether this URL and `other` address the same web origin: identical scheme, host, and
    /// effective port, per RFC 6454.
    ///
    /// Hostless URLs have no origin and never match, including against themselves.
    package func hasSameOrigin(as other: URL) -> Bool {
        guard let host = self.host?.lowercased(), let otherHost = other.host?.lowercased() else {
            return false
        }
        return host == otherHost
            && self.scheme?.lowercased() == other.scheme?.lowercased()
            && self.effectivePort == other.effectivePort
    }

    private var effectivePort: Int? {
        if let port = self.port {
            return port
        }
        switch self.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}

fileprivate enum FileURLError: Error {
    case notRepresentable(URL)
}
