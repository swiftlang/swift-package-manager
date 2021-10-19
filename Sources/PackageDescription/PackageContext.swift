/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import class Foundation.JSONDecoder
import class Foundation.JSONEncoder
import class Foundation.ProcessInfo
import struct Foundation.URL

// copy-pasta from Basics, which we evidently can't import.
extension JSONDecoder {
    public func decode<T>(_ type: T.Type, from string: String) throws -> T where T : Decodable {
        guard let data = string.data(using: .utf8) else {
            let context = DecodingError.Context(codingPath: [], debugDescription: "invalid UTF-8 string")
            throw DecodingError.dataCorrupted(context)
        }

        return try decode(type, from: data)
    }
}

/// The context a Swift package is running in. This encapsulates states that are known at runtime.
/// For example where in the file system the current package resides.
extension Package {
    public struct Context: Codable {
        public let packageRoot : URL
        
        public init(_ packageRoot : URL) {
            self.packageRoot = packageRoot
        }
        
        public var encoded : String {
            let encoder = JSONEncoder()
            // encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try! encoder.encode(self)
            return String(data: data, encoding: .utf8)!
        }

        public static var current : Context? = {
            // TODO: Look at ProcessInfo.processInfo
            var args = Array(ProcessInfo.processInfo.arguments[1...]).makeIterator()
            while let arg = args.next() {
                if arg == "-context", let json = args.next() {
                    let decoder = JSONDecoder()
                    return (try? decoder.decode(Context.self, from: json))
                }
            }
            return nil
        }()
    }
}
