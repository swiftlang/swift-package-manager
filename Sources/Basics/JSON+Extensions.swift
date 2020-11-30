/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

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
    public static func makeWithDefaults(prettified: Bool = true, dateEncodingStrategy: DateEncodingStrategy = .safeISO8601) -> JSONEncoder {
        let encoder = JSONEncoder()
        if prettified {
            // output formatting
            #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
                encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            } else if #available(macOS 10.13, iOS 11.0, watchOS 4.0, tvOS 11.0, *) {
                encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            } else {
                encoder.outputFormatting = [.prettyPrinted]
            }
            #elseif compiler(>=5.3)
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            #else
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            #endif
        }
        // date
        encoder.dateEncodingStrategy = dateEncodingStrategy
        return encoder
    }
}
