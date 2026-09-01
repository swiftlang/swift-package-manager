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
    private let paths: [CoverageFormat: AbsolutePath]

    package init(data: [CoverageFormat: AbsolutePath]) {
        self.paths = data
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (format, path) in self.paths.sorted(by: { $0.key < $1.key }) {
            try container.encode(path.pathString, forKey: DynamicCodingKey(format))
        }
    }

    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(_ format: CoverageFormat) {
            self.stringValue = format.rawValue
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }
}
