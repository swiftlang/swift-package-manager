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
        var string = string.precomposedStringWithCanonicalMapping

        var detectedScheme: Scheme?
        for scheme in Scheme.allCases {
            if string.removePrefixIfPresent("\(scheme):") {
                detectedScheme = scheme
                string.removePrefixIfPresent("//")
                break
            }
        }

        if case (let user, _)? = string.dropUserinfoSubcomponentPrefixIfPresent() {
            string.replaceFirstOccurenceIfPresent(of: "/~/", with: "/~\(user)/")
        }

        switch detectedScheme {
        case .file:
            break
        case .ftp, .ftps:
            string.removePortComponentIfPresent()
        case .http, .https:
            string.removeFragmentComponentIfPresent()
            string.removeQueryComponentIfPresent()
            string.removePortComponentIfPresent()
        case nil, .git, .ssh:
            string.removePortComponentIfPresent()
            string.replaceFirstOccurenceIfPresent(of: ":", before: string.firstIndex(of: "/"), with: "/")
        }

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
    case file
    case ftp
    case ftps
    case git
    case http
    case https
    case ssh

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

private extension Character {
    var isDigit: Bool {
        isHexDigit && !isLetter
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
    mutating func dropUserinfoSubcomponentPrefixIfPresent() -> (user: String, password: String?)? {
        if let indexOfAtSign = firstIndex(of: "@"),
           let indexOfFirstPathComponent = firstIndex(where: isSeparator),
           indexOfAtSign < indexOfFirstPathComponent
        {
            defer { self.removeSubrange(...indexOfAtSign) }

            let userinfo = self[..<indexOfAtSign]
            var components = userinfo.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard components.count > 0 else { return nil }
            let user = String(components.removeFirst())
            let password = components.last.map(String.init)

            return (user, password)
        }

        return nil
    }

    @discardableResult
    mutating func removePortComponentIfPresent() -> Bool {
        if let indexOfFirstPathComponent = firstIndex(where: isSeparator),
           let startIndexOfPort = firstIndex(of: ":"),
           startIndexOfPort < endIndex,
           let endIndexOfPort = self[index(after: startIndexOfPort)...].lastIndex(where: { $0.isDigit }),
           endIndexOfPort <= indexOfFirstPathComponent
        {
            self.removeSubrange(startIndexOfPort ... endIndexOfPort)
            return true
        }

        return false
    }

    @discardableResult
    mutating func removeFragmentComponentIfPresent() -> Bool {
        if let index = firstIndex(of: "#") {
            self.removeSubrange(index...)
        }

        return false
    }

    @discardableResult
    mutating func removeQueryComponentIfPresent() -> Bool {
        if let index = firstIndex(of: "?") {
            self.removeSubrange(index...)
        }

        return false
    }

    @discardableResult
    mutating func replaceFirstOccurenceIfPresent<T: StringProtocol, U: StringProtocol>(
        of string: T,
        before index: Index? = nil,
        with replacement: U
    ) -> Bool {
        guard let range = range(of: string) else { return false }

        if let index = index, range.lowerBound >= index {
            return false
        }

        self.replaceSubrange(range, with: replacement)
        return true
    }
}
