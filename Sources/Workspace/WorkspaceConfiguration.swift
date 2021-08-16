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
    /// Workspace location configuration
    public struct Location {
        /// Path to working directory for this workspace.
        public var workingDirectory: AbsolutePath

        /// Path to store the editable versions of dependencies.
        public var editsDirectory: AbsolutePath

        /// Path to the Package.resolved file.
        public var resolvedVersionsFilePath: AbsolutePath

        /// Path to the shared cache
        public var sharedCacheDirectory: AbsolutePath?

        /// Path to the repositories shared cache.
        public var repositoriesSharedCacheDirectory: AbsolutePath? {
            self.sharedCacheDirectory.map { $0.appending(component: "repositories") }
        }

        /// Path to the repositories clones.
        public var repositoriesDirectory: AbsolutePath {
            self.workingDirectory.appending(component: "repositories")
        }

        /// Path to the repository checkouts.
        public var repositoriesCheckoutsDirectory: AbsolutePath {
            self.workingDirectory.appending(component: "checkouts")
        }

        /// Path to the downloaded binary artifacts.
        public var artifactsDirectory: AbsolutePath {
            self.workingDirectory.appending(component: "artifacts")
        }

        /// Create a new workspace location.
        ///
        /// - Parameters:
        ///   - workingDirectory: Path to working directory for this workspace.
        ///   - editsDirectory: Path to store the editable versions of dependencies.
        ///   - resolvedVersionsFile: Path to the Package.resolved file.
        ///   - sharedCachePath: Path to the sharedCache
        public init(
            workingDirectory: AbsolutePath,
            editsDirectory: AbsolutePath,
            resolvedVersionsFilePath: AbsolutePath,
            sharedCacheDirectory: AbsolutePath? = .none
        ) {
            self.workingDirectory = workingDirectory
            self.editsDirectory = editsDirectory
            self.resolvedVersionsFilePath = resolvedVersionsFilePath
            self.sharedCacheDirectory = sharedCacheDirectory
        }

        /// Create a new workspace location.
        ///
        /// - Parameters:
        ///   - rootPath: Path to the root of the package, from which other locations can be derived.
        public init(forRootPackage rootPath: AbsolutePath) {
            self.init(
                workingDirectory: rootPath.appending(component: ".build"),
                editsDirectory: rootPath.appending(component: "Packages"),
                resolvedVersionsFilePath: rootPath.appending(component: "Package.resolved")
            )
        }
    }

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


        @available(*, deprecated)
        public convenience init(path: AbsolutePath, fs: FileSystem = localFileSystem) throws {
            try self.init(path: path, fileSystem: fs)
        }

        /// Creates a new, persisted package configuration with a configuration file.
        /// - Parameters:
        ///   - path: A path to the configuration file.
        ///   - fileSystem: The filesystem on which the configuration file is located.
        /// - Throws: `StringError` if the configuration file is corrupted or malformed.
        public init(path: AbsolutePath, fileSystem: FileSystem) throws {
            self.configFile = path
            self.fileSystem = fileSystem
            let persistence = SimplePersistence(
                fileSystem: fileSystem,
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
