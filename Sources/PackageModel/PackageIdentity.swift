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

import Basics
import Foundation
import TSCBasic

/// The canonical identifier for a package, based on its source location.
public struct PackageIdentity: CustomStringConvertible, Sendable {
    /// A textual representation of this instance.
    public let description: String

    /// Creates a package identity from a string.
    /// - Parameter value: A string used to identify a package.
    init(_ value: String) {
        self.description = value
    }

    /// Creates a package identity from a URL.
    /// - Parameter url: The package's URL.
    public init(url: SourceControlURL) {
        self.init(urlString: url.absoluteString)
    }

    /// Creates a package identity from a URL.
    /// - Parameter urlString: The package's URL.
    // FIXME: deprecate this
    public init(urlString: String) {
        self.description = PackageIdentityParser(urlString).description
    }

    /// Creates a package identity from a file path.
    /// - Parameter path: An absolute path to the package.
    public init(path: Basics.AbsolutePath) {
        self.description = PackageIdentityParser(path.pathString).description
    }

    /// Creates a plain package identity for a root package
    /// - Parameter value: A string used to identify a package, will be used unmodified
    public static func plain(_ value: String) -> PackageIdentity {
        PackageIdentity(value)
    }

    @available(*, deprecated, message: "use .registry instead")
    public var scopeAndName: (scope: Scope, name: Name)? {
        self.registry.flatMap { (scope: $0.scope, name: $0.name) }
    }

    public var registry: RegistryIdentity? {
        let components = self.description.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
        guard components.count == 2,
              let scope = Scope(components.first),
              let name = Name(components.last)
        else {
            return .none
        }

        return RegistryIdentity(
            scope: scope,
            name: name,
            underlying: self
        )
    }

    public var isRegistry: Bool {
        self.registry != nil
    }

    public struct RegistryIdentity: Hashable, CustomStringConvertible, Sendable {
        public let scope: PackageIdentity.Scope
        public let name: PackageIdentity.Name
        public let underlying: PackageIdentity

        public var description: String {
            self.underlying.description
        }
    }
}

extension PackageIdentity: Equatable, Comparable {
    private func compare(to other: PackageIdentity) -> ComparisonResult {
        self.description.caseInsensitiveCompare(other.description)
    }

    public static func == (lhs: PackageIdentity, rhs: PackageIdentity) -> Bool {
        lhs.compare(to: rhs) == .orderedSame
    }

    public static func < (lhs: PackageIdentity, rhs: PackageIdentity) -> Bool {
        lhs.compare(to: rhs) == .orderedAscending
    }

    public static func > (lhs: PackageIdentity, rhs: PackageIdentity) -> Bool {
        lhs.compare(to: rhs) == .orderedDescending
    }
}

extension PackageIdentity: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.description.lowercased())
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

// MARK: -

extension PackageIdentity {
    /// Provides a namespace for related packages within a package registry.
    public struct Scope: LosslessStringConvertible, Hashable, Equatable, Comparable, ExpressibleByStringLiteral,
        Sendable
    {
        public let description: String

        public init(validating description: String) throws {
            guard !description.isEmpty else {
                throw StringError("The minimum length of a package scope is 1 character.")
            }

            guard description.count <= 39 else {
                throw StringError("The maximum length of a package scope is 39 characters.")
            }

            for (index, character) in zip(description.indices, description) {
                guard character.isASCII,
                      character.isLetter ||
                      character.isNumber ||
                      character == "-"
                else {
                    throw StringError("A package scope consists of alphanumeric characters and hyphens.")
                }

                if character.isPunctuation {
                    switch (index, description.index(after: index)) {
                    case (description.startIndex, _):
                        throw StringError("Hyphens may not occur at the beginning of a scope.")
                    case (_, description.endIndex):
                        throw StringError("Hyphens may not occur at the end of a scope.")
                    case (_, let nextIndex) where description[nextIndex].isPunctuation:
                        throw StringError("Hyphens may not occur consecutively within a scope.")
                    default:
                        continue
                    }
                }
            }

            self.description = description
        }

        public init?(_ description: String) {
            guard let scope = try? Scope(validating: description) else { return nil }
            self = scope
        }

        fileprivate init?(_ substring: String.SubSequence?) {
            guard let substring else { return nil }
            self.init(String(substring))
        }

        // MARK: - Equatable & Comparable

        private func compare(to other: Scope) -> ComparisonResult {
            // Package scopes are case-insensitive (for example, `mona` ≍ `MONA`).
            self.description.caseInsensitiveCompare(other.description)
        }

        public static func == (lhs: Scope, rhs: Scope) -> Bool {
            lhs.compare(to: rhs) == .orderedSame
        }

        public static func < (lhs: Scope, rhs: Scope) -> Bool {
            lhs.compare(to: rhs) == .orderedAscending
        }

        public static func > (lhs: Scope, rhs: Scope) -> Bool {
            lhs.compare(to: rhs) == .orderedDescending
        }

        // MARK: - Hashable

        public func hash(into hasher: inout Hasher) {
            hasher.combine(self.description.lowercased())
        }

        // MARK: - ExpressibleByStringLiteral

        public init(stringLiteral value: StringLiteralType) {
            try! self.init(validating: value)
        }
    }

    /// Uniquely identifies a package in a scope
    public struct Name: LosslessStringConvertible, Hashable, Equatable, Comparable, ExpressibleByStringLiteral,
        Sendable
    {
        public let description: String

        public init(validating description: String) throws {
            guard !description.isEmpty else {
                throw StringError("The minimum length of a package name is 1 character.")
            }

            guard description.count <= 100 else {
                throw StringError("The maximum length of a package name is 100 characters.")
            }

            for (index, character) in zip(description.indices, description) {
                guard character.isASCII,
                      character.isLetter ||
                      character.isNumber ||
                      character == "-" ||
                      character == "_"
                else {
                    throw StringError("A package name consists of alphanumeric characters, underscores, and hyphens.")
                }

                if character.isPunctuation {
                    switch (index, description.index(after: index)) {
                    case (description.startIndex, _):
                        throw StringError("Hyphens and underscores may not occur at the beginning of a name.")
                    case (_, description.endIndex):
                        throw StringError("Hyphens and underscores may not occur at the end of a name.")
                    case (_, let nextIndex) where description[nextIndex].isPunctuation:
                        throw StringError("Hyphens and underscores may not occur consecutively within a name.")
                    default:
                        continue
                    }
                }
            }

            self.description = description
        }

        public init?(_ description: String) {
            guard let name = try? Name(validating: description) else { return nil }
            self = name
        }

        fileprivate init?(_ substring: String.SubSequence?) {
            guard let substring else { return nil }
            self.init(String(substring))
        }

        // MARK: - Equatable & Comparable

        private func compare(to other: Name) -> ComparisonResult {
            // Package scopes are case-insensitive (for example, `LinkedList` ≍ `LINKEDLIST`).
            self.description.caseInsensitiveCompare(other.description)
        }

        public static func == (lhs: Name, rhs: Name) -> Bool {
            lhs.compare(to: rhs) == .orderedSame
        }

        public static func < (lhs: Name, rhs: Name) -> Bool {
            lhs.compare(to: rhs) == .orderedAscending
        }

        public static func > (lhs: Name, rhs: Name) -> Bool {
            lhs.compare(to: rhs) == .orderedDescending
        }

        // MARK: - Hashable

        public func hash(into hasher: inout Hasher) {
            hasher.combine(self.description.lowercased())
        }

        // MARK: - ExpressibleByStringLiteral

        public init(stringLiteral value: StringLiteralType) {
            try! self.init(validating: value)
        }
    }
}

// MARK: -

struct PackageIdentityParser {
    /// A textual representation of this instance.
    public let description: String

    /// Instantiates an instance of the conforming type from a string representation.
    public init(_ string: String) {
        self.description = Self.computeDefaultName(fromLocation: string).lowercased()
    }

    /// Compute the default name of a package given its URL.
    public static func computeDefaultName(fromURL url: SourceControlURL) -> String {
        Self.computeDefaultName(fromLocation: url.absoluteString)
    }

    /// Compute the default name of a package given its path.
    public static func computeDefaultName(fromPath path: Basics.AbsolutePath) -> String {
        Self.computeDefaultName(fromLocation: path.pathString)
    }

    /// Compute the default name of a package given its location.
    public static func computeDefaultName(fromLocation url: String) -> String {
        #if os(Windows)
        let isSeparator: (Character) -> Bool = { $0 == "/" || $0 == "\\" }
        #else
        let isSeparator: (Character) -> Bool = { $0 == "/" }
        #endif

        // Get the last path component of the URL.
        // Drop the last character in case it's a trailing slash.
        var endIndex = url.endIndex
        if let lastCharacter = url.last, isSeparator(lastCharacter) {
            endIndex = url.index(before: endIndex)
        }

        let separatorIndex = url[..<endIndex].lastIndex(where: isSeparator)
        let startIndex = separatorIndex.map { url.index(after: $0) } ?? url.startIndex
        var lastComponent = url[startIndex ..< endIndex]

        // Strip `.git` suffix if present.
        if lastComponent.hasSuffix(".git") {
            lastComponent = lastComponent.dropLast(4)
        }

        return String(lastComponent)
    }
}

/// A canonicalized package location.
///
/// A package may declare external packages as dependencies in its manifest.
/// Each external package is uniquely identified by the location of its source code.
///
/// An external package dependency may itself have one or more external package dependencies,
/// known as _transitive dependencies_.
/// When multiple packages have dependencies in common,
/// Swift Package Manager determines which version of that package should be used
/// (if any exist that satisfy all specified requirements)
/// in a process called package resolution.
///
/// External package dependencies are located by a URL
/// (which may be an implicit `file://` URL in the form of a file path).
/// For the purposes of package resolution,
/// package URLs are case-insensitive (mona ≍ MONA)
/// and normalization-insensitive (n + ◌̃ ≍ ñ).
/// Swift Package Manager takes additional steps to canonicalize URLs
/// to resolve insignificant differences between URLs.
/// For example,
/// the URLs `https://example.com/Mona/LinkedList` and `git@example.com:mona/linkedlist`
/// are equivalent, in that they both resolve to the same source code repository,
/// despite having different scheme, authority, and path components.
///
/// The `PackageIdentity` type canonicalizes package locations by
/// performing the following operations:
///
/// * Removing the scheme component, if present
///   ```
///   https://example.com/mona/LinkedList → example.com/mona/LinkedList
///   ```
/// * Removing the userinfo component (preceded by `@`), if present:
///   ```
///   git@example.com/mona/LinkedList → example.com/mona/LinkedList
///   ```
/// * Removing the port subcomponent, if present:
///   ```
///   example.com:443/mona/LinkedList → example.com/mona/LinkedList
///   ```
/// * Replacing the colon (`:`) preceding the path component in "`scp`-style" URLs:
///   ```
///   git@example.com:mona/LinkedList.git → example.com/mona/LinkedList
///   ```
/// * Expanding the tilde (`~`) to the provided user, if applicable:
///   ```
///   ssh://mona@example.com/~/LinkedList.git → example.com/~mona/LinkedList
///   ```
/// * Removing percent-encoding from the path component, if applicable:
///   ```
///   example.com/mona/%F0%9F%94%97List → example.com/mona/🔗List
///   ```
/// * Removing the `.git` file extension from the path component, if present:
///   ```
///   example.com/mona/LinkedList.git → example.com/mona/LinkedList
///   ```
/// * Removing the trailing slash (`/`) in the path component, if present:
///   ```
///   example.com/mona/LinkedList/ → example.com/mona/LinkedList
///   ```
/// * Removing the fragment component (preceded by `#`), if present:
///   ```
///   example.com/mona/LinkedList#installation → example.com/mona/LinkedList
///   ```
/// * Removing the query component (preceded by `?`), if present:
///   ```
///   example.com/mona/LinkedList?utm_source=forums.swift.org → example.com/mona/LinkedList
///   ```
/// * Adding a leading slash (`/`) for `file://` URLs and absolute file paths:
///   ```
///   file:///Users/mona/LinkedList → /Users/mona/LinkedList
///   ```
public struct CanonicalPackageLocation: Equatable, CustomStringConvertible, Hashable {
    /// A textual representation of this instance.
    public let description: String

    /// Instantiates an instance of the conforming type from a string representation.
    public init(_ string: String) {
        self.description = computeCanonicalLocation(string).description
    }
}

/// Similar to `CanonicalPackageLocation` but differentiates based on the scheme.
public struct CanonicalPackageURL: Equatable, CustomStringConvertible {
    public let description: String
    public let scheme: String?

    public init(_ string: String) {
        let location = computeCanonicalLocation(string)
        self.description = location.description
        self.scheme = location.scheme
    }
}

private func computeCanonicalLocation(_ string: String) -> (description: String, scheme: String?) {
    var description = string.precomposedStringWithCanonicalMapping.lowercased()

    // Remove the scheme component, if present.
    let detectedScheme = description.dropSchemeComponentPrefixIfPresent()
    var scheme = detectedScheme

    // Remove the userinfo subcomponent (user / password), if present.
    if case (let user, _)? = description.dropUserinfoSubcomponentPrefixIfPresent() {
        // If a user was provided, perform tilde expansion, if applicable.
        description.replaceFirstOccurrenceIfPresent(of: "/~/", with: "/~\(user)/")

        if user == "git", scheme == nil {
            scheme = "ssh"
        }
    }

    // Remove the port subcomponent, if present.
    description.removePortComponentIfPresent()

    // Remove the fragment component, if present.
    description.removeFragmentComponentIfPresent()

    // Remove the query component, if present.
    description.removeQueryComponentIfPresent()

    // Accommodate "`scp`-style" SSH URLs
    if detectedScheme == nil || detectedScheme == "ssh" {
        description.replaceFirstOccurrenceIfPresent(of: ":", before: description.firstIndex(of: "/"), with: "/")
    }

    // Split the remaining string into path components,
    // filtering out empty path components and removing valid percent encodings.
    var components = description.split(omittingEmptySubsequences: true, whereSeparator: isSeparator)
        .compactMap { $0.removingPercentEncoding ?? String($0) }

    // Remove the `.git` suffix from the last path component.
    var lastPathComponent = components.popLast() ?? ""
    lastPathComponent.removeSuffixIfPresent(".git")
    components.append(lastPathComponent)

    description = components.joined(separator: "/")

    // Prepend a leading slash for file URLs and paths
    if detectedScheme == "file" || string.first.flatMap(isSeparator) ?? false {
        scheme = "file"
        description.insert("/", at: description.startIndex)
    }

    return (description, scheme)
}

#if os(Windows)
fileprivate let isSeparator: (Character) -> Bool = { $0 == "/" || $0 == "\\" }
#else
fileprivate let isSeparator: (Character) -> Bool = { $0 == "/" }
#endif

extension Character {
    fileprivate var isDigit: Bool {
        switch self {
        case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
            return true
        default:
            return false
        }
    }

    fileprivate var isAllowedInURLScheme: Bool {
        isLetter || self.isDigit || self == "+" || self == "-" || self == "."
    }
}

extension String {
    @discardableResult
    private mutating func removePrefixIfPresent<T: StringProtocol>(_ prefix: T) -> Bool {
        guard hasPrefix(prefix) else { return false }
        removeFirst(prefix.count)
        return true
    }

    @discardableResult
    fileprivate mutating func removeSuffixIfPresent<T: StringProtocol>(_ suffix: T) -> Bool {
        guard hasSuffix(suffix) else { return false }
        removeLast(suffix.count)
        return true
    }

    @discardableResult
    fileprivate mutating func dropSchemeComponentPrefixIfPresent() -> String? {
        if let rangeOfDelimiter = range(of: "://"),
           self[startIndex].isLetter,
           self[..<rangeOfDelimiter.lowerBound].allSatisfy(\.isAllowedInURLScheme)
        {
            defer { self.removeSubrange(..<rangeOfDelimiter.upperBound) }

            return String(self[..<rangeOfDelimiter.lowerBound])
        }

        return nil
    }

    @discardableResult
    fileprivate mutating func dropUserinfoSubcomponentPrefixIfPresent() -> (user: String, password: String?)? {
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
    fileprivate mutating func removePortComponentIfPresent() -> Bool {
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
    fileprivate mutating func removeFragmentComponentIfPresent() -> Bool {
        if let index = firstIndex(of: "#") {
            self.removeSubrange(index...)
        }

        return false
    }

    @discardableResult
    fileprivate mutating func removeQueryComponentIfPresent() -> Bool {
        if let index = firstIndex(of: "?") {
            self.removeSubrange(index...)
        }

        return false
    }

    @discardableResult
    fileprivate mutating func replaceFirstOccurrenceIfPresent<T: StringProtocol, U: StringProtocol>(
        of string: T,
        before index: Index? = nil,
        with replacement: U
    ) -> Bool {
        guard let range = range(of: string) else { return false }

        if let index, range.lowerBound >= index {
            return false
        }

        self.replaceSubrange(range, with: replacement)
        return true
    }
}
