//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Foundation.Data
import class Foundation.DateFormatter
import class Foundation.JSONDecoder
import class Foundation.JSONEncoder

extension JSONDecoder {
    public static func makeWithDefaults(dateDecodingStrategy: DateDecodingStrategy = .iso8601) -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dateDecodingStrategy
        return decoder
    }
}

extension JSONEncoder {
    public static func makeWithDefaults(
        prettified: Bool = true,
        dateEncodingStrategy: DateEncodingStrategy = .iso8601
    ) -> JSONEncoder {
        Self.makeWithDefaults(
            sortKeys: prettified,
            prettyPrint: prettified,
            escapeSlashes: !prettified,
            dateEncodingStrategy: dateEncodingStrategy
        )
    }

    public static func makeWithDefaults(
        sortKeys: Bool,
        prettyPrint: Bool,
        escapeSlashes: Bool,
        dateEncodingStrategy: DateEncodingStrategy = .iso8601
    ) -> JSONEncoder {
        let encoder = JSONEncoder()
        var outputFormatting: JSONEncoder.OutputFormatting = []

        if sortKeys {
            outputFormatting.insert(.sortedKeys)
        }
        if prettyPrint {
            outputFormatting.insert(.prettyPrinted)
        }
        if !escapeSlashes {
            outputFormatting.insert(.withoutEscapingSlashes)
        }

        encoder.outputFormatting = outputFormatting
        encoder.dateEncodingStrategy = dateEncodingStrategy
        return encoder
    }
}

extension JSONDecoder {
    public func decode<T: Decodable>(path: AbsolutePath, fileSystem: FileSystem, as kind: T.Type) throws -> T {
        let data: Data = try fileSystem.readFileContents(path)
        return try self.decode(kind, from: data)
    }
}

extension JSONEncoder {
    public func encode<T: Encodable>(path: AbsolutePath, fileSystem: FileSystem, _ value: T) throws {
        let data = try self.encode(value)
        try fileSystem.writeFileContents(path, data: data)
    }
}
