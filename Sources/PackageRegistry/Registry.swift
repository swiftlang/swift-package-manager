/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct Foundation.URL

public struct Registry: Hashable, Codable {
    public var url: Foundation.URL

    public init(url: Foundation.URL) {
        self.url = url
    }
}
