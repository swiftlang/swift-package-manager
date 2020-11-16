/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation

import TSCBasic
import TSCUtility

/// The canonical identifier for a package, based on its source location.
public struct PackageIdentity: LosslessStringConvertible, Hashable {
    /// A textual representation of this instance.
    public let description: String

    /// Instantiates an instance of the conforming type from a string representation.
    public init(_ url: String) {
        self.description = PackageReference.computeDefaultName(fromURL: url).lowercased()
    }
}

extension PackageIdentity: Comparable {
    public static func < (lhs: PackageIdentity, rhs: PackageIdentity) -> Bool {
        return lhs.description < rhs.description
    }
}

extension PackageIdentity: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let description = try container.decode(String.self)
        self.init(description)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.description)
    }
}

extension PackageIdentity: JSONMappable, JSONSerializable {
    public init(json: JSON) throws {
        guard case .string(let string) = json else {
            throw JSON.MapError.typeMismatch(key: "", expected: String.self, json: json)
        }

        self.init(string)
    }

    public func toJSON() -> JSON {
        return .string(self.description)
    }
}
