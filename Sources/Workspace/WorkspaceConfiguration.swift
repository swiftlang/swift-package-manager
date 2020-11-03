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

import PackageGraph

extension Workspace {
    /// Manages a package workspace's configuration.
    public final class Configuration {
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
        public private(set) var mirrors: DependencyMirrors = DependencyMirrors()

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
}

extension Workspace.Configuration: JSONSerializable {
    public func toJSON() -> JSON {
        return mirrors.toJSON()
    }
}

extension Workspace.Configuration: SimplePersistanceProtocol {
    public func restore(from json: JSON) throws {
        self.mirrors = try DependencyMirrors(json: json)
    }
}
