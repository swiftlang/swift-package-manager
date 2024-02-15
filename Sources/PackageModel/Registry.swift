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

import Basics
import struct Foundation.URL

public struct Registry: Hashable, CustomStringConvertible, Sendable {
    public var url: URL
    public var supportsAvailability: Bool

    public init(url: URL, supportsAvailability: Bool) {
        self.url = url
        self.supportsAvailability = supportsAvailability
    }

    public var description: String {
        self.url.absoluteString
    }
}
