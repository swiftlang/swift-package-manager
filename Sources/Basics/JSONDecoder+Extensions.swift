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

import Foundation

extension JSONDecoder {
    public func decode<T>(_ type: T.Type, from string: String) throws -> T where T : Decodable {
        guard let data = string.data(using: .utf8) else {
            let context = DecodingError.Context(codingPath: [], debugDescription: "invalid UTF-8 string")
            throw DecodingError.dataCorrupted(context)
        }

        return try decode(type, from: data)
    }
}
