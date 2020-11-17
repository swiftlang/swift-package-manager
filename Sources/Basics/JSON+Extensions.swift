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
