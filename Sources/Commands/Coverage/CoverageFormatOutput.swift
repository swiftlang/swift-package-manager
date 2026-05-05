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

import struct TSCBasic.StringError
import struct Basics.AbsolutePath

package struct CoverageFormatOutput: Encodable {
    private var _underlying: [CoverageFormat : AbsolutePath]

    package init() {
        self._underlying = [CoverageFormat : AbsolutePath]()
    }

    package init(data: [CoverageFormat : AbsolutePath]) {
        self._underlying = data
    }

    // Custom encoding to ensure the dictionary is encoded as a JSON object, not an array
    public func encode(to encoder: Encoder) throws {
        // Use keyed container to encode each format and its path
        // This will create proper JSON objects and proper plain text "key: value" format
        var container = encoder.container(keyedBy: DynamicCodingKey.self)

        // Sort entries for consistent output
        let sortedEntries = _underlying.sorted { $0.key.rawValue < $1.key.rawValue }

        for (format, path) in sortedEntries {
            let key = DynamicCodingKey(stringValue: format.rawValue)!
            try container.encode(path.pathString, forKey: key)
        }
    }

    // Dynamic coding keys for the formats
    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    /// Adds a key/value pair to the underlying dictionary.
    /// - Parameters:
    ///   - format: The coverage format key
    ///   - path: The absolute path value
    /// - Throws: `StringError` if the key already exists
    package mutating func addFormat(_ format: CoverageFormat, path: AbsolutePath) throws {
        guard !_underlying.keys.contains(format) else {
            throw StringError("Coverage format '\(format.rawValue)' already exists")
        }
        _underlying[format] = path
    }

    /// Access paths by format. Returns nil if format doesn't exist.
    package subscript(format: CoverageFormat) -> AbsolutePath? {
        return _underlying[format]
    }

    /// Gets the path for a format, throwing an error if it doesn't exist.
    /// - Parameter format: The coverage format
    /// - Returns: The absolute path for the format
    /// - Throws: `StringError` if the format is not found
    package func getPath(for format: CoverageFormat) throws -> AbsolutePath {
        guard let path = _underlying[format] else {
            throw StringError("Missing coverage format output path for '\(format.rawValue)'")
        }
        return path
    }

    /// Returns all formats currently stored
    package var formats: [CoverageFormat] {
        return Array(_underlying.keys).sorted()
    }

    /// Iterate over format/path pairs
    package func forEach(_ body: (CoverageFormat, AbsolutePath) throws -> Void) rethrows {
        try _underlying.forEach(body)
    }

}
