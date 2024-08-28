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
    public func decode<T>(_ type: T.Type, from string: String) throws -> T where T: Decodable {
        let data = Data(string.utf8)
        return try self.decode(type, from: data)
    }
}
