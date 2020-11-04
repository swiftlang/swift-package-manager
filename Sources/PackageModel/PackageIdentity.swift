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

public struct PackageIdentity: LosslessStringConvertible {
    public let description: String
    public let computedName: String

    public init(_ string: String) {
        var string = string.precomposedStringWithCanonicalMapping.lowercased()

        var detectedScheme: Scheme?
        for scheme in Scheme.allCases {
            if string.removePrefixIfPresent("\(scheme):") {
                detectedScheme = scheme
                string.removePrefixIfPresent("//")
                string.removePortComponentIfPresent(scheme.defaultPort)
                break
            }
        }

        if string.removeUserComponentIfPresent() || detectedScheme != .ssh {
            string.replaceFirstOccurenceIfPresent(of: ":", with: "/")
        }
        assert(!string.contains(":"))

        var components = string.split(omittingEmptySubsequences: true, whereSeparator: isSeparator)

        var lastPathComponent = components.popLast() ?? ""
        lastPathComponent.removeSuffixIfPresent(".git")
        components.append(lastPathComponent)

        self.description = components.joined(separator: "/")
        self.computedName = String(lastPathComponent)
    }
}

extension PackageIdentity: Equatable {
    public static func == (lhs: PackageIdentity, rhs: PackageIdentity) -> Bool {
        return lhs.description == rhs.description
    }
}

extension PackageIdentity: Comparable {
    public static func < (lhs: PackageIdentity, rhs: PackageIdentity) -> Bool {
        return lhs.description < rhs.description
    }
}

extension PackageIdentity: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.description)
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

extension PackageIdentity: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

// MARK: -

private enum Scheme: String, CustomStringConvertible, CaseIterable {
    case ssh
    case https
    case git

    var defaultPort: Int {
        switch self {
        case .ssh:
            return 22
        case .https:
            return 443
        case .git:
            return 9418
        }
    }

    public var description: String {
        return self.rawValue
    }
}

#if os(Windows)
fileprivate let isSeparator: (Character) -> Bool = { $0 == "/" || $0 == "\\" }
#else
fileprivate let isSeparator: (Character) -> Bool = { $0 == "/" }
#endif

private extension StringProtocol where Self == Self.SubSequence {
    @discardableResult
    mutating func removeSuffixIfPresent<T: StringProtocol>(_ suffix: T) -> Bool {
        guard hasSuffix(suffix) else { return false }
        removeLast(suffix.count)
        return true
    }
}

private extension String {
    @discardableResult
    mutating func removePrefixIfPresent<T: StringProtocol>(_ prefix: T) -> Bool {
        guard hasPrefix(prefix) else { return false }
        removeFirst(prefix.count)
        return true
    }

    @discardableResult
    mutating func removeUserComponentIfPresent() -> Bool {
        if let indexOfAtSign = firstIndex(of: "@"),
           let indexOfFirstPathComponent = firstIndex(where: isSeparator),
           indexOfAtSign < indexOfFirstPathComponent
        {
            removeSubrange(...indexOfAtSign)
            return true
        }

        return false
    }

    @discardableResult
    mutating func removePortComponentIfPresent(_ port: Int) -> Bool {
        if let indexOfFirstPathComponent = firstIndex(where: isSeparator),
           let rangeOfPort = range(of: ":\(port)"),
           rangeOfPort.upperBound < indexOfFirstPathComponent
        {
            removeSubrange(rangeOfPort)
            return true
        }

        return false
    }

    @discardableResult
    mutating func replaceFirstOccurenceIfPresent<T: StringProtocol, U: StringProtocol>(of string: T, with replacement: U) -> Bool {
        guard let range = range(of: string) else { return false }
        replaceSubrange(range, with: replacement)
        return true
    }
}
