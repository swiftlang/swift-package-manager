/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation

// FIXME: This is preliminary.
public struct Path: ExpressibleByStringLiteral, Encodable, Decodable {
    public var string: String

    init(_ string: String) {
        self.string = string
    }

    public func appending(_ components: [String]) -> Path {
        return Path(self.string.appending("/").appending(components.joined(separator: "/")))
    }

    public func appending(_ components: String...) -> Path {
        return self.appending(components)
    }

    public var filename: String {
        // Check for a special case of the root directory.
        if self.string == "/" {
            // Root directory, so the basename is a single path separator (the
            // root directory is special in this regard).
            return "/"
        }
        // Find the last path separator.
        guard let idx = string.lastIndex(of: "/") else {
            // No path separators, so the basename is the whole string.
            return self.string
        }
        // Otherwise, it's the string from (but not including) the last path
        // separator.
        return String(self.string.suffix(from: self.string.index(after: idx)))
    }

    public var basename: String {
        let filename = self.filename
        if let suff = self.suffix {
            return String(filename.dropLast(suff.count))
        } else {
            return filename
        }
    }

    public var suffix: String? {
        // Find the last path separator, if any.
        let sIdx = self.string.lastIndex(of: "/")

        // Find the start of the basename.
        let bIdx = (sIdx != nil) ? self.string.index(after: sIdx!) : self.string.startIndex

        // Find the last `.` (if any), starting from the second character of
        // the basename (a leading `.` does not make the whole path component
        // a suffix).
        let fIdx = self.string.index(bIdx, offsetBy: 1, limitedBy: self.string.endIndex) ?? self.string.startIndex
        if let idx = string[fIdx...].lastIndex(of: ".") {
            // Unless it's just a `.` at the end, we have found a suffix.
            if self.string.distance(from: idx, to: self.string.endIndex) > 1 {
                return String(self.string.suffix(from: idx))
            } else {
                return nil
            }
        }
        // If we get this far, there is no suffix.
        return nil
    }

    public func hasSuffix(_ suffix: String) -> Bool {
        return self.string.hasSuffix(suffix)
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(stringLiteral: value)
    }

    public init(unicodeScalarLiteral value: String) {
        self.init(stringLiteral: value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.string)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        self.init(string)
    }
}

public extension String.StringInterpolation {
    mutating func appendInterpolation(_ path: Path) {
        self.appendInterpolation(path.string)
    }
}
