//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

public struct SourceControlURL: Codable, Equatable, Hashable, Sendable {
    private let urlString: String

    public init(stringLiteral: String) {
        self.urlString = stringLiteral
    }

    public init(_ urlString: String) {
        self.urlString = urlString
    }

    public init(_ url: URL) {
        self.urlString = url.absoluteString
    }

    public var absoluteString: String {
        return self.urlString
    }

    public var lastPathComponent: String {
        return (self.urlString as NSString).lastPathComponent
    }

    public var url: URL? {
        return URL(string: self.urlString)
    }

    /// Whether this URL appears to be a valid source control URL.
    ///
    /// Valid source control URLs must:
    /// - Be parseable as a URL (or match SSH-style git URL format)
    /// - Have a non-empty host
    /// - Not contain whitespace (which would indicate a malformed URL,
    ///   e.g., one concatenated with an error message)
    public var isValid: Bool {
        // URLs with whitespace are invalid (typically indicates concatenated error messages)
        guard !self.urlString.contains(where: \.isWhitespace) else {
            return false
        }

        // Check for standard URL format (http://, https://, ssh://, etc.)
        if let url = self.url,
           let host = url.host,
           !host.isEmpty {
            return true
        }

        // Check for SSH-style git URLs: git@host:path or user@host:path
        // These don't parse as standard URLs but are valid git URLs
        let sshPattern = #/^[\w.-]+@[\w.-]+:.+/#
        return self.urlString.contains(sshPattern)
    }
}

extension SourceControlURL: CustomStringConvertible {
    public var description: String {
        return self.urlString
    }
}

extension SourceControlURL: ExpressibleByStringInterpolation {
}

extension SourceControlURL: ExpressibleByStringLiteral {
}
