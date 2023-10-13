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

import Basics
import Foundation
import OrderedCollections
import PackageModel

import struct TSCBasic.StringError

/// A collection of dependency mirrors.
public final class DependencyMirrors: Equatable {
    private var index: [String: String]
    private var mirrorIndex: [PackageIdentity: PackageIdentity]
    private var reverseIndex: [String: [String]]
    private var visited: OrderedCollections.OrderedSet<String>
    private let lock = NSLock()

    public var mapping: [String: String] {
        self.lock.withLock {
            self.index
        }
    }

    public init(_ mirrors: [String: String] = [:]) throws {
        self.index = mirrors
        self.reverseIndex = [String: [String]]()
        self.mirrorIndex = [PackageIdentity: PackageIdentity]()
        for entry in mirrors {
            self.reverseIndex[entry.value, default: []].append(entry.key)
            self.mirrorIndex[try Self.parseLocation(entry.key)] = try Self.parseLocation(entry.value)
        }
        self.visited = .init()
    }

    public static func == (lhs: DependencyMirrors, rhs: DependencyMirrors) -> Bool {
        lhs.mapping == rhs.mapping
    }

    /// Sets a mirror for the given origin.
    /// - Parameters:
    ///   - mirror: The mirror
    ///   - for: The original
    public func set(mirror: String, for key: String) throws {
        try self.lock.withLock {
            self.index[key] = mirror
            self.reverseIndex[mirror, default: []].append(key)
            self.mirrorIndex[try Self.parseLocation(key)] = try Self.parseLocation(mirror)
        }
    }

    /// Unsets a mirror for the given.
    /// - Parameters:
    ///   - originalOrMirror: The original or the mirrored
    /// - Throws: `Error.mirrorNotFound` if no mirror exists for the provided origin or mirror.
    public func unset(originalOrMirror: String) throws {
        try self.lock.withLock {
            if let value = self.index[originalOrMirror] {
                self.index[originalOrMirror] = nil
                self.reverseIndex[value] = nil
                self.mirrorIndex[try Self.parseLocation(value)] = nil
            } else if let mirror = self.index.first(where: { $0.value == originalOrMirror }) {
                self.index[mirror.key] = nil
                self.reverseIndex[originalOrMirror] = nil
                self.mirrorIndex[try Self.parseLocation(originalOrMirror)] = nil
            } else {
                throw StringError("Mirror not found for '\(originalOrMirror)'")
            }
        }
    }

    /// Append the content of a different DependencyMirrors into this one
    /// - Parameters:
    ///   - contentsOf: The DependencyMirrors to append from.
    public func append(contentsOf mirrors: DependencyMirrors) throws {
        try mirrors.index.forEach {
            try self.set(mirror: $0.value, for: $0.key)
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

    /// Returns the mirrored for a package dependency.
    /// - Parameters:
    ///   - for: The original
    /// - Returns: The mirrored, if one exists.
    public func mirror(for key: String) -> String? {
        self.lock.withLock {
            let value = self.index[key]
            if value != nil {
                // record visited mirrors for reverse index lookup sorting
                self.visited.append(key)
            }
            return value
        }
    }

    /// Returns the effective value for a package dependency.
    /// - Parameters:
    ///   - for: The original
    /// - Returns: The mirrored if it exists, otherwise the original.
    public func effective(for key: String) -> String {
        self.mirror(for: key) ?? key
    }

    /// Returns the original for a mirrored package dependency.
    /// - Parameters:
    ///   - for: The mirror
    /// - Returns: The original , if one exists.
    public func original(for key: String) -> String? {
        self.lock.withLock {
            let alternatives = self.reverseIndex[key]
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

    public func effectiveIdentity(for identity: PackageIdentity) throws -> PackageIdentity {
        return mirrorIndex[identity] ?? identity
    }

    private static func parseLocation(_ location: String) throws -> PackageIdentity {
        if PackageIdentity.plain(location).isRegistry {
            return PackageIdentity.plain(location)
        } else if let path = try? AbsolutePath(validating: location) {
            return PackageIdentity(path: path)
        } else {
            return PackageIdentity(url: SourceControlURL(location))
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
