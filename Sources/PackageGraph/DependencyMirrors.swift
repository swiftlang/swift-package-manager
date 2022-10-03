//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import OrderedCollections
import TSCBasic

/// A collection of dependency mirrors.
public final class DependencyMirrors: Equatable {
    private var index: [String: String]
    private var reverseIndex: [String: [String]]
    private var visited: OrderedCollections.OrderedSet<String>
    private let lock = NSLock()

    public var mapping: [String: String] {
        self.lock.withLock {
            return self.index
        }
    }

    public init(_ mirrors: [String: String]) {
        self.index = mirrors
        self.reverseIndex = [String: [String]]()
        for entry in mirrors {
            self.reverseIndex[entry.value, default: []].append(entry.key)
        }
        self.visited = .init()
    }

    @available(*, deprecated)
    private convenience init(_ mirrors: [Mirror]) {
        self.init(Dictionary(mirrors.map({ ($0.original, $0.mirror) }), uniquingKeysWith: { first, _ in first }))
    }

    public static func == (lhs: DependencyMirrors, rhs: DependencyMirrors) -> Bool {
        return lhs.mapping == rhs.mapping
    }

    /// Sets a mirror URL for the given URL.
    /// - Parameters:
    ///   - mirrorURL: The mirrored URL
    ///   - forURL: The original URL
    public func set(mirrorURL: String, forURL url: String) {
        self.lock.withLock {
            self.index[url] = mirrorURL
            self.reverseIndex[mirrorURL, default: []].append(url)
        }
    }

    /// Unsets a mirror for the given URL.
    /// - Parameters:
    ///   - originalOrMirrorURL: The original URL or the mirrored URL
    /// - Throws: `Error.mirrorNotFound` if no mirror exists for the provided URL.
    public func unset(originalOrMirrorURL: String) throws {
        try self.lock.withLock {
            if let value = self.index[originalOrMirrorURL] {
                self.index[originalOrMirrorURL] = nil
                self.reverseIndex[value] = nil
            } else if let mirror = self.index.first(where: { $0.value == originalOrMirrorURL }) {
                self.index[mirror.key] = nil
                self.reverseIndex[originalOrMirrorURL] = nil
            } else {
                throw StringError("Mirror not found for '\(originalOrMirrorURL)'")
            }
        }
    }

    /// Append the content of a different DependencyMirrors into this one
    /// - Parameters:
    ///   - contentsOf: The DependencyMirrors to append from.
    public func append(contentsOf mirrors: DependencyMirrors) {
        mirrors.index.forEach {
            self.set(mirrorURL: $0.value, forURL: $0.key)
        }
    }

    // Removes all mirrors
    public func removeAll() {
        self.lock.withLock {
            self.index.removeAll()
            self.reverseIndex.removeAll()
        }
    }

    // Count
    public var count: Int {
        self.lock.withLock {
            self.index.count
        }
    }

    // Is empty
    public var isEmpty: Bool {
        self.lock.withLock {
            self.index.isEmpty
        }
    }

    /// Returns the mirrored URL for a package dependency URL.
    /// - Parameters:
    ///   - url: The original URL
    /// - Returns: The mirrored URL, if one exists.
    public func mirrorURL(for url: String) -> String? {
        self.lock.withLock {
            let value = self.index[url]
            if value != nil {
                // record visited mirrors for reverse index lookup sorting
                self.visited.append(url)
            }
            return value
        }
    }

    /// Returns the effective URL for a package dependency URL.
    /// - Parameters:
    ///   - url: The original URL
    /// - Returns: The mirrored URL if it exists, otherwise the original URL.
    public func effectiveURL(for url: String) -> String {
        return self.mirrorURL(for: url) ?? url
    }

    /// Returns the original URL for a mirrored package dependency URL.
    /// - Parameters:
    ///   - url: The mirror URL
    /// - Returns: The original URL, if one exists.
    public func originalURL(for url: String) -> String? {
        self.lock.withLock {
            let alternatives = self.reverseIndex[url]
            // since there are potentially multiple mapping, we need to sort them to produce deterministic results
            let sorted = alternatives?.sorted(by: { lhs, rhs in
                // check if it was visited (which means it used by the package)
                switch (self.visited.firstIndex(of: lhs), self.visited.firstIndex(of: rhs)) {
                case (.some(let lhsIndex), .some(let rhsIndex)):
                    return lhsIndex < rhsIndex
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    // otherwise sort alphabetically
                    return lhs < rhs
                }
            })
            return sorted?.first
        }
    }
}

extension DependencyMirrors: Collection {
    public typealias Index = Dictionary<String, String>.Index
    public typealias Element = String

    public var startIndex: Index {
        self.lock.withLock {
            self.index.startIndex
        }
    }

    public var endIndex: Index {
        self.lock.withLock {
            self.index.endIndex
        }
    }

    public subscript(index: Index) -> Element {
        self.lock.withLock {
            self.index[index].value
        }
    }

    public func index(after index: Index) -> Index {
        self.lock.withLock {
            self.index.index(after: index)
        }
    }
}

extension DependencyMirrors: ExpressibleByDictionaryLiteral {
    public convenience init(dictionaryLiteral elements: (String, String)...) {
        self.init(Dictionary(elements, uniquingKeysWith: { first, _ in first }))
    }
}

@available(*, deprecated)
extension DependencyMirrors: JSONMappable, JSONSerializable {
    public convenience init(json: JSON) throws {
        self.init(try [Mirror](json: json))
    }

    public func toJSON() -> JSON {
        let mirrors = self.index.map { Mirror(original: $0.key, mirror: $0.value) }
        return .array(mirrors.sorted(by: { $0.original < $1.mirror }).map { $0.toJSON() })
    }
}

/// An individual repository mirror.
@available(*, deprecated)
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

@available(*, deprecated)
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
