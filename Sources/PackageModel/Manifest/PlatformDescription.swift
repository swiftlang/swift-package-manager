//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public struct PlatformDescription: Codable, Hashable, Sendable {
    public let platformName: String
    public let version: String
    public let options: [String]

    public init(name: String, version: String, options: [String] = []) {
        self.platformName = name
        self.version = version
        self.options = options
    }
}
