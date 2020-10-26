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

// FIXME: We may want to move this class to some other layer once we start
// supporting more things than just mirrors.
//
/// Manages a package's configuration.
public final class SwiftPMConfig {

    /// A package configuration error.
    public enum Error: Swift.Error {
        /// No mirror was found for the specified URL.
        case mirrorNotFound
    }

    /// The path to the mirrors file.
    private let configFile: AbsolutePath?

    /// The filesystem to manage the mirrors file on.
    private var fileSystem: FileSystem?

    /// Persistence support.
    private let persistence: SimplePersistence?

    /// The schema version of the config file.
    ///
    /// * 1: Initial version.
    static let schemaVersion: Int = 1

    /// The mirrors.
    public private(set) var mirrors: DependencyMirrors = DependencyMirrors([])

    /// Creates a new, persisted package configuration with a configuration file.
    /// - Parameters:
    ///   - path: A path to the configuration file.
    ///   - fs: The filesystem on which the configuration file is located.
    /// - Throws: `StringError` if the configuration file is corrupted or malformed.
    public init(path: AbsolutePath, fs: FileSystem = localFileSystem) throws {
        self.configFile = path
        self.fileSystem = fs
        let persistence = SimplePersistence(
            fileSystem: fs,
            schemaVersion: Self.schemaVersion,
            statePath: path,
            prettyPrint: true
        )

        do {
            self.persistence = persistence
            _ = try persistence.restoreState(self)
        } catch SimplePersistence.Error.restoreFailure(_, let error) {
            throw StringError("Configuration file is corrupted or malformed; fix or delete the file to continue: \(error)")
        }
    }

    /// Initializes a new, ephemeral package configuration.
    public init() {
        self.configFile = nil
        self.fileSystem = nil
        self.persistence = nil
    }

    /// Load the configuration from disk.
    public func restoreState() throws {
        _ = try self.persistence?.restoreState(self)
    }

    /// Persists the current configuration to disk.
    ///
    /// If the configuration is empty, any persisted configuration file is removed.
    ///
    /// - Throws: If the configuration couldn't be persisted.
    public func saveState() throws {
        guard let persistence = self.persistence else { return }
        
        // Remove the configuratoin file if there aren't any mirrors.
        if mirrors.isEmpty,
           let fileSystem = self.fileSystem,
           let configFile = self.configFile
        {
            return try fileSystem.removeFileTree(configFile)
        }

        try persistence.saveState(self)
    }
}

extension SwiftPMConfig: JSONSerializable {
    public func toJSON() -> JSON {
        return mirrors.toJSON()
    }
}

extension SwiftPMConfig: SimplePersistanceProtocol {
    public func restore(from json: JSON) throws {
        let mirrors = try json.getArray().map(Mirror.init(json:))
        self.mirrors = DependencyMirrors(mirrors)
    }
}

extension SwiftPMConfig.Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .mirrorNotFound:
            return "mirror not found"
        }
    }
}

// MARK: -

/// An individual repository mirror.
public struct Mirror {
    /// The original repository path.
    let original: String

    /// The mirrored repository path.
    let mirror: String
}

extension Mirror: JSONMappable, JSONSerializable {
    public init(json: JSON) throws {
        self.original = try json.get("original")
        self.mirror = try json.get("mirror")
    }

    public func toJSON() -> JSON {
        .init([
            "original": original,
            "mirror": mirror
        ])
    }
}

/// A collection of dependency mirrors.
public final class DependencyMirrors {
    private var mirrorMap: [String: Mirror]

    init(_ mirrors: [Mirror]) {
        self.mirrorMap = Dictionary(mirrors.map({ ($0.original, $0) }), uniquingKeysWith: { first, _ in first })
    }

    /// Sets a mirror URL for the given URL.
    public func set(mirrorURL: String, forURL url: String) {
        mirrorMap[url] = Mirror(original: url, mirror: mirrorURL)
    }

    /// Unsets a mirror for the given URL.
    /// - Parameter originalOrMirrorURL: The original URL or the mirrored URL
    /// - Throws: `Error.mirrorNotFound` if no mirror exists for the provided URL.
    public func unset(originalOrMirrorURL: String) throws {
        if mirrorMap.keys.contains(originalOrMirrorURL) {
            mirrorMap[originalOrMirrorURL] = nil
        } else if let mirror = mirrorMap.first(where: { $0.value.mirror == originalOrMirrorURL }) {
            mirrorMap[mirror.key] = nil
        } else {
            throw SwiftPMConfig.Error.mirrorNotFound
        }
    }

    /// Returns the mirrored URL for a package dependency URL.
    /// - Parameter url: The original URL
    /// - Returns: The mirrored URL, if one exists.
    public func getMirror(forURL url: String) -> String? {
        return mirrorMap[url]?.mirror
    }

    /// Returns the effective URL for a package dependency URL.
    /// - Parameter url: The original URL
    /// - Returns: The mirrored URL if it exists, otherwise the original URL.
    public func effectiveURL(forURL url: String) -> String {
        return getMirror(forURL: url) ?? url
    }
}

extension DependencyMirrors: Collection {
    public typealias Index = Dictionary<String, Mirror>.Index
    public typealias Element = Mirror

    public var startIndex: Index {
        mirrorMap.startIndex
    }

    public var endIndex: Index {
        mirrorMap.endIndex
    }

    public subscript(index: Index) -> Element {
        mirrorMap[index].value
    }

    public func index(after index: Index) -> Index {
        mirrorMap.index(after: index)
    }
}

extension DependencyMirrors: JSONMappable, JSONSerializable {
    public convenience init(json: JSON) throws {
        self.init(try [Mirror](json: json))
    }

    public func toJSON() -> JSON {
        .array(mirrorMap.values.sorted(by: { $0.original < $1.mirror }).map { $0.toJSON() })
    }
}

extension DependencyMirrors: CustomStringConvertible {
    public var description: String {
        "<Mirrors: \(Array(mirrorMap.values))>"
    }
}
