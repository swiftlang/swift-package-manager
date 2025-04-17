//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Wrapper type representing serialized escaped JSON strings providing helpers
/// for escaped string interpolations for common types such as `AbsolutePath`.
public struct SerializedJSON {
    let underlying: String
}

extension SerializedJSON: ExpressibleByStringLiteral {
    public init(stringLiteral: String) {
        self.underlying = stringLiteral
    }
}

extension SerializedJSON: ExpressibleByStringInterpolation {
    public init(stringInterpolation: StringInterpolation) {
        self.init(underlying: stringInterpolation.value)
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        fileprivate var value: String = ""

        private func escape(_ string: String) -> String {
            string.replacing(#"\"#, with: #"\\"#)
        }

        public init(literalCapacity: Int, interpolationCount: Int) {
            self.value.reserveCapacity(literalCapacity)
        }

        public mutating func appendLiteral(_ literal: String) {
            self.value.append(self.escape(literal))
        }

        public mutating func appendInterpolation(_ value: some CustomStringConvertible) {
            self.value.append(self.escape(value.description))
        }
    }
}
