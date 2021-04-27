/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

import TSCBasic
import TSCUtility

/// A collection of dependency mirrors.
public final class DependencyMirrors {

    /// A dependency mirror error.
    public enum Error: Swift.Error {
        /// No mirror was found for the specified URL.
        case mirrorNotFound
    }

    private var index: [String: String]
    private var reverseIndex: [String: String]

    private init(_ mirrors: [Mirror]) {
        self.index = Dictionary(mirrors.map({ ($0.original, $0.mirror) }), uniquingKeysWith: { first, _ in first })
        self.reverseIndex = Dictionary(mirrors.map({ ($0.mirror, $0.original) }), uniquingKeysWith: { first, _ in first })
    }

    /// Sets a mirror URL for the given URL.
    public func set(mirrorURL: String, forURL url: String) {
        self.index[url] = mirrorURL
        self.reverseIndex[mirrorURL] = url
    }

    /// Unsets a mirror for the given URL.
    /// - Parameter originalOrMirrorURL: The original URL or the mirrored URL
    /// - Throws: `Error.mirrorNotFound` if no mirror exists for the provided URL.
    public func unset(originalOrMirrorURL: String) throws {
        if let value = self.index[originalOrMirrorURL] {
            self.index[originalOrMirrorURL] = nil
            self.reverseIndex[value] = nil
        } else if let mirror = self.index.first(where: { $0.value == originalOrMirrorURL }) {
            self.index[mirror.key] = nil
            self.reverseIndex[originalOrMirrorURL] = nil
        } else {
            throw Error.mirrorNotFound
        }
    }

    /// Returns the mirrored URL for a package dependency URL.
    /// - Parameter url: The original URL
    /// - Returns: The mirrored URL, if one exists.
    public func mirrorURL(for url: String) -> String? {
        return self.index[url]
    }

    /// Returns the effective URL for a package dependency URL.
    /// - Parameter url: The original URL
    /// - Returns: The mirrored URL if it exists, otherwise the original URL.
    public func effectiveURL(for url: String) -> String {
        return self.mirrorURL(for: url) ?? url
    }

    /// Returns the original URL for a mirrored package dependency URL.
    /// - Parameter url: The mirror URL
    /// - Returns: The original URL, if one exists.
    public func originalURL(for url: String) -> String? {
        return self.reverseIndex[url]
    }

}

extension DependencyMirrors: Collection {
    public typealias Index = Dictionary<String, String>.Index
    public typealias Element = String

    public var startIndex: Index {
        self.index.startIndex
    }

    public var endIndex: Index {
        self.index.endIndex
    }

    public subscript(index: Index) -> Element {
        self.index[index].value
    }

    public func index(after index: Index) -> Index {
        self.index.index(after: index)
    }
}

extension DependencyMirrors: ExpressibleByDictionaryLiteral {
    public convenience init(dictionaryLiteral elements: (String, String)...) {
        self.init(elements.map { Mirror(original: $0.0, mirror: $0.1) })
    }
}

extension DependencyMirrors: JSONMappable, JSONSerializable {
    public convenience init(json: JSON) throws {
        self.init(try [Mirror](json: json))
    }

    public func toJSON() -> JSON {
        let mirrors = self.index.map { Mirror(original: $0.key, mirror: $0.value) }
        return .array(mirrors.sorted(by: { $0.original < $1.mirror }).map { $0.toJSON() })
    }
}

extension DependencyMirrors.Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .mirrorNotFound:
            return "mirror not found"
        }
    }
}

// MARK: -

/// An individual repository mirror.
private struct Mirror {
    /// The original repository path.
    let original: String

    /// The mirrored repository path.
    let mirror: String

    init(original: String, mirror: String) {
        self.original = original
        self.mirror = mirror
    }
}

extension Mirror: JSONMappable, JSONSerializable {
    init(json: JSON) throws {
        self.original = try json.get("original")
        self.mirror = try json.get("mirror")
    }

    func toJSON() -> JSON {
        .init([
            "original": original,
            "mirror": mirror
        ])
    }
}
