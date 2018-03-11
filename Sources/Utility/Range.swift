/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

extension Range: Codable where Bound: Codable {
    private enum CodingKeys: String, CodingKey {
        case lowerBound
        case upperBound
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(upperBound, forKey: .upperBound)
        try container.encode(lowerBound, forKey: .lowerBound)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let lowerBound = try values.decode(Bound.self, forKey: .lowerBound)
        let upperBound = try values.decode(Bound.self, forKey: .upperBound)
        self = lowerBound..<upperBound
    }
}
