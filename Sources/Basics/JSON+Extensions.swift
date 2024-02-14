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

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
extension DateFormatter {
    public static let iso8601: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return dateFormatter
    }()
}

extension JSONEncoder.DateEncodingStrategy {
    public static let customISO8601 = custom {
        var container = $1.singleValueContainer()
        try container.encode(DateFormatter.iso8601.string(from: $0))
    }
}

extension JSONDecoder.DateDecodingStrategy {
    public static let customISO8601 = custom {
        let container = try $0.singleValueContainer()
        let string = try container.decode(String.self)
        if let date = DateFormatter.iso8601.date(from: string) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
    }
}
#endif

extension JSONEncoder.DateEncodingStrategy {
    public static var safeISO8601: JSONEncoder.DateEncodingStrategy {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        if #available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *) {
            return .iso8601
        } else {
            return .customISO8601
        }
        #else
        return .iso8601
        #endif
    }
}

extension JSONDecoder.DateDecodingStrategy {
    public static var safeISO8601: JSONDecoder.DateDecodingStrategy {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        if #available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *) {
            return .iso8601
        } else {
            return .customISO8601
        }
        #else
        return .iso8601
        #endif
    }
}

extension JSONDecoder {
    public static func makeWithDefaults(dateDecodingStrategy: DateDecodingStrategy = .safeISO8601) -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dateDecodingStrategy
        return decoder
    }
}

extension JSONEncoder {
    public static func makeWithDefaults(
        prettified: Bool = true,
        dateEncodingStrategy: DateEncodingStrategy = .safeISO8601
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
        dateEncodingStrategy: DateEncodingStrategy = .safeISO8601
    ) -> JSONEncoder {
        let encoder = JSONEncoder()
        var outputFormatting: JSONEncoder.OutputFormatting = []

        if sortKeys {
            #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            if #available(macOS 10.15, iOS 11.0, watchOS 4.0, tvOS 11.0, *) {
                outputFormatting.insert(.sortedKeys)
            }
            #else
            outputFormatting.insert(.sortedKeys)
            #endif
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
