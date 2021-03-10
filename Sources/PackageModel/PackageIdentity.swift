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

/// When set to `false`,
/// `PackageIdentity` uses the canonical location of package dependencies as its identity.
/// Otherwise, only the last path component is used to identify package dependencies.
public var _useLegacyIdentities: Bool = true {
    willSet {
        PackageIdentity.provider = newValue ? LegacyPackageIdentity.self : CanonicalPackageIdentity.self
    }
}

internal protocol PackageIdentityProvider: CustomStringConvertible {
    init(_ string: String)
}

/// The canonical identifier for a package, based on its source location.
public struct PackageIdentity: Hashable, CustomStringConvertible {
    /// The underlying type used to create package identities.
    internal static var provider: PackageIdentityProvider.Type = LegacyPackageIdentity.self

    /// A textual representation of this instance.
    public let description: String

    /// Creates a package identity from a string.
    /// - Parameter string: A string used to identify a package.
    init(_ description: String) {
        self.description = description
    }

    /// Creates a package identity from a URL.
    /// - Parameter url: The package's URL.
    public init(url: String) { // TODO: Migrate to Foundation.URL
        self.description = Self.provider.init(url).description
    }

    /// Creates a package identity from a file path.
    /// - Parameter path: An absolute path to the package.
    public init(path: AbsolutePath) {
        self.description = Self.provider.init(path.pathString).description
    }

    /// Creates a package identity for a root package
    /// - Parameter name: The name of the package, will be used unmodified
    public static func root(name: String) -> PackageIdentity {
        PackageIdentity(name)
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

// MARK: -

struct LegacyPackageIdentity: PackageIdentityProvider, Equatable {
    /// A textual representation of this instance.
    public let description: String

    /// Instantiates an instance of the conforming type from a string representation.
    public init(_ string: String) {
        self.description = Self.computeDefaultName(fromURL: string).lowercased()
    }

    /// Compute the default name of a package given its URL.
    public static func computeDefaultName(fromURL url: String) -> String {
        #if os(Windows)
        let isSeparator : (Character) -> Bool = { $0 == "/" || $0 == "\\" }
        #else
        let isSeparator : (Character) -> Bool = { $0 == "/" }
        #endif

        // Get the last path component of the URL.
        // Drop the last character in case it's a trailing slash.
        var endIndex = url.endIndex
        if let lastCharacter = url.last, isSeparator(lastCharacter) {
            endIndex = url.index(before: endIndex)
        }

        let separatorIndex = url[..<endIndex].lastIndex(where: isSeparator)
        let startIndex = separatorIndex.map { url.index(after: $0) } ?? url.startIndex
        var lastComponent = url[startIndex..<endIndex]

        // Strip `.git` suffix if present.
        if lastComponent.hasSuffix(".git") {
            lastComponent = lastComponent.dropLast(4)
        }

        return String(lastComponent)
    }
}

/// A canonicalized package identity.
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
struct CanonicalPackageIdentity: PackageIdentityProvider, Equatable {
    /// A textual representation of this instance.
    public let description: String

    /// Instantiates an instance of the conforming type from a string representation.
    public init(_ string: String) {
        var description = string.precomposedStringWithCanonicalMapping.lowercased()

        // Remove the scheme component, if present.
        let detectedScheme = description.dropSchemeComponentPrefixIfPresent()

        // Remove the userinfo subcomponent (user / password), if present.
        if case (let user, _)? = description.dropUserinfoSubcomponentPrefixIfPresent() {
            // If a user was provided, perform tilde expansion, if applicable.
            description.replaceFirstOccurenceIfPresent(of: "/~/", with: "/~\(user)/")
        }

        // Remove the port subcomponent, if present.
        description.removePortComponentIfPresent()

        // Remove the fragment component, if present.
        description.removeFragmentComponentIfPresent()

        // Remove the query component, if present.
        description.removeQueryComponentIfPresent()

        // Accomodate "`scp`-style" SSH URLs
        if detectedScheme == nil || detectedScheme == "ssh" {
            description.replaceFirstOccurenceIfPresent(of: ":", before: description.firstIndex(of: "/"), with: "/")
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
            description.insert("/", at: description.startIndex)
        }

        self.description = description
    }
}

#if os(Windows)
fileprivate let isSeparator: (Character) -> Bool = { $0 == "/" || $0 == "\\" }
#else
fileprivate let isSeparator: (Character) -> Bool = { $0 == "/" }
#endif

private extension Character {
    var isDigit: Bool {
        switch self {
        case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
            return true
        default:
            return false
        }
    }

    var isAllowedInURLScheme: Bool {
        return isLetter || self.isDigit || self == "+" || self == "-" || self == "."
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
    mutating func removeSuffixIfPresent<T: StringProtocol>(_ suffix: T) -> Bool {
        guard hasSuffix(suffix) else { return false }
        removeLast(suffix.count)
        return true
    }

    @discardableResult
    mutating func dropSchemeComponentPrefixIfPresent() -> String? {
        if let rangeOfDelimiter = range(of: "://"),
           self[startIndex].isLetter,
           self[..<rangeOfDelimiter.lowerBound].allSatisfy({ $0.isAllowedInURLScheme })
        {
            defer { self.removeSubrange(..<rangeOfDelimiter.upperBound) }

            return String(self[..<rangeOfDelimiter.lowerBound])
        }

        return nil
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

