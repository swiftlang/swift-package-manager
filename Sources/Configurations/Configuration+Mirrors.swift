/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import Foundation
import TSCBasic

extension Configuration {
    public struct Mirrors {
        private let fileSystem: FileSystem
        private let path: AbsolutePath

        public init(fileSystem: FileSystem, path: AbsolutePath? = nil) {
            self.fileSystem = fileSystem
            self.path = path ?? fileSystem.swiftPMConfigDirectory.appending(component: "mirrors.json")
        }

        public struct Mapping: Equatable {
            fileprivate var index: [String: String]
            fileprivate var reverseIndex: [String: String]

            fileprivate init(_ index: [String: String]) {
                self.index = index
                self.reverseIndex = Dictionary(index.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            }

            /// Sets a mirror URL for the given URL.
            mutating public func set(mirrorURL: String, forURL url: String) {
                self.index[url] = mirrorURL
                self.reverseIndex[mirrorURL] = url
            }

            /// Unsets a mirror for the given URL.
            /// - Parameter originalOrMirrorURL: The original URL or the mirrored URL
            /// - Throws: `Error.mirrorNotFound` if no mirror exists for the provided URL.
            mutating public func unset(originalOrMirrorURL: String) throws {
                if let value = self.index[originalOrMirrorURL] {
                    self.index[originalOrMirrorURL] = nil
                    self.reverseIndex[value] = nil
                } else if let mirror = self.index.first(where: { $0.value == originalOrMirrorURL }) {
                    self.index[mirror.key] = nil
                    self.reverseIndex[originalOrMirrorURL] = nil
                } else {
                    throw StringError("Mirror not found: '\(originalOrMirrorURL)'")
                }
            }
        }
    }
}

extension Configuration.Mirrors {
    @discardableResult
    public func withMapping(handler: (inout Mapping) throws -> Void) throws -> Mapping {
        if !self.fileSystem.exists(self.path.parentDirectory) {
            try self.fileSystem.createDirectory(self.path.parentDirectory, recursive: true)
        }
        return try self.fileSystem.withLock(on: self.path.parentDirectory, type: .exclusive) {
            let mapping = Mapping(try Self.load(self.path, fileSystem: self.fileSystem))
            var updatedMapping = mapping
            try handler(&updatedMapping)
            if updatedMapping != mapping {
                try Self.save(updatedMapping.index, to: self.path, fileSystem: self.fileSystem)
            }
            return updatedMapping
        }
    }

    /// Returns the mirrored URL for a package dependency URL.
    /// - Parameter url: The original URL
    /// - Returns: The mirrored URL, if one exists.
    public func mirrorURL(for url: String) -> String? {
        return self.mapping().index[url]
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
        return self.mapping().reverseIndex[url]
    }

    private func mapping() -> Mapping {
        // FIXME: try?
        return (try? self.withMapping{ _ in }) ?? Mapping([:])
    }
}

extension Configuration.Mirrors {
    private static func load(_ path: AbsolutePath, fileSystem: FileSystem) throws -> [String: String] {
        guard fileSystem.exists(path) else {
            return [:]
        }
        let data: Data = try fileSystem.readFileContents(path)
        let decoder = JSONDecoder.makeWithDefaults()
        let mirrors = try decoder.decode(Mirrors.self, from: data)
        let mirrorsMap = Dictionary(mirrors.object.map({ ($0.original, $0.mirror) }), uniquingKeysWith: { first, _ in first })
        return mirrorsMap
    }

    private static func save(_ mirrors: [String: String], to path: AbsolutePath, fileSystem: FileSystem) throws {
        if mirrors.isEmpty {
            if fileSystem.exists(path) {
                try fileSystem.removeFileTree(path)
            }
            return
        }

        let encoder = JSONEncoder.makeWithDefaults()
        let mirrors = Mirrors(version: 1, object: mirrors.map { Mirror(original: $0, mirror: $1) })
        let data = try encoder.encode(mirrors)
        if !fileSystem.exists(path.parentDirectory) {
            try fileSystem.createDirectory(path.parentDirectory, recursive: true)
        }
        try fileSystem.writeFileContents(path, data: data)
    }

    // FIXME: for backwards compatibility, do something nicer
    private struct Mirrors: Codable {
        var version: Int
        var object: [Mirror]
    }

    private struct Mirror: Codable {
        var original: String
        var mirror: String
    }
}
