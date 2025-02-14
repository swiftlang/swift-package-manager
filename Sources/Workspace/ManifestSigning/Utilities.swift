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

extension DataProtocol {
    func copyBytes() -> [UInt8] {
        [UInt8](unsafeUninitializedCapacity: self.count) { buffer, initializedCount in
            self.copyBytes(to: buffer)
            initializedCount = self.count
        }
    }
}

extension UInt8 {
    static var period: UInt8 {
        UInt8(ascii: ".")
    }
}

/// Cannot use `extension Data` if `period` is going to be used with
/// `+` operator via leading-dot syntax, for example: `Data(...) + .period`
/// because `+` is declared as `(Self, Other) -> Self` where
/// `Other: RangeReplaceableCollection, Other.Element == Self.Element`
/// which means that `.period` couldn't get `Data` inferred from the first argument.
extension RangeReplaceableCollection where Self == Data {
    static var period: Data {
        Data([UInt8.period])
    }
}
