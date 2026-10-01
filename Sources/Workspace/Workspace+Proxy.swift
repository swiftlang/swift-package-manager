//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation

import class TSCBasic.FileLock

// MARK: - Proxy Configuration Storage

extension Workspace.Configuration {
    /// Storage for proxy configuration with file locking.
    ///
    /// Follows the same pattern as `MirrorsStorage`: shared locks for reads, exclusive locks for writes.
    public struct ProxyStorage {
        private let path: AbsolutePath
        private let fileSystem: FileSystem
        private let deleteWhenEmpty: Bool

        public init(path: AbsolutePath, fileSystem: FileSystem, deleteWhenEmpty: Bool = true) {
            self.path = path
            self.fileSystem = fileSystem
            self.deleteWhenEmpty = deleteWhenEmpty
        }

        /// Load the proxy configuration from disk.
        ///
        /// Returns `nil` if the file does not exist.
        public func get() throws -> HTTPProxyConfiguration? {
            guard self.fileSystem.exists(self.path) else {
                return nil
            }
            return try self.fileSystem.withLock(on: self.path.parentDirectory, type: .shared) {
                try Self.load(self.path, fileSystem: self.fileSystem)
            }
        }

        /// Apply a mutation to the proxy configuration with exclusive file locking.
        ///
        /// The handler receives the current configuration (or a fresh one if no file exists).
        /// After the handler returns, the updated configuration is saved to disk.
        @discardableResult
        public func apply(handler: (inout HTTPProxyConfiguration) throws -> Void) throws -> HTTPProxyConfiguration {
            if !self.fileSystem.exists(self.path.parentDirectory) {
                try self.fileSystem.createDirectory(self.path.parentDirectory, recursive: true)
            }
            return try self.fileSystem.withLock(on: self.path.parentDirectory, type: .exclusive) {
                var config = (try? Self.load(self.path, fileSystem: self.fileSystem)) ?? HTTPProxyConfiguration()
                try handler(&config)
                try Self.save(config, to: self.path, fileSystem: self.fileSystem, deleteWhenEmpty: self.deleteWhenEmpty)
                return config
            }
        }

        /// Remove the proxy configuration file.
        public func remove() throws {
            if self.fileSystem.exists(self.path) {
                try self.fileSystem.withLock(on: self.path.parentDirectory, type: .exclusive) {
                    try self.fileSystem.removeFileTree(self.path)
                }
            }
        }

        // MARK: - Private

        private static func load(_ path: AbsolutePath, fileSystem: FileSystem) throws -> HTTPProxyConfiguration? {
            guard fileSystem.exists(path) else {
                return nil
            }
            let data: Data = try fileSystem.readFileContents(path)
            let decoder = JSONDecoder.makeWithDefaults()
            let config = try decoder.decode(HTTPProxyConfiguration.self, from: data)
            try config.validate()
            return config
        }

        private static func save(
            _ config: HTTPProxyConfiguration,
            to path: AbsolutePath,
            fileSystem: FileSystem,
            deleteWhenEmpty: Bool
        ) throws {
            if config.isEmpty {
                if deleteWhenEmpty && fileSystem.exists(path) {
                    return try fileSystem.removeFileTree(path)
                } else if !fileSystem.exists(path) {
                    return
                }
            }

            try config.validate()

            let encoder = JSONEncoder.makeWithDefaults()
            let data = try encoder.encode(config)
            if !fileSystem.exists(path.parentDirectory) {
                try fileSystem.createDirectory(path.parentDirectory, recursive: true)
            }
            try fileSystem.writeFileContents(path, data: data)
        }
    }
}

// MARK: - Merge operations

extension Workspace.Configuration.ProxyStorage {
    /// Sets proxy fields additively — only updates fields that are provided.
    ///
    /// - Parameters:
    ///   - httpProxy: The HTTP proxy URL to set, or `nil` to leave unchanged.
    ///   - httpsProxy: The HTTPS proxy URL to set, or `nil` to leave unchanged.
    ///   - noProxy: The noProxy patterns to set, or `nil` to leave unchanged.
    @discardableResult
    public func set(httpProxy: String? = nil, httpsProxy: String? = nil, noProxy: [String]? = nil) throws -> HTTPProxyConfiguration {
        // Validate URLs before writing
        if let httpProxy {
            try HTTPProxyConfiguration.validateProxyURL(httpProxy)
        }
        if let httpsProxy {
            try HTTPProxyConfiguration.validateProxyURL(httpsProxy)
        }

        return try self.apply { config in
            if let httpProxy {
                config.http = .init(proxy: httpProxy)
            }
            if let httpsProxy {
                config.https = .init(proxy: httpsProxy)
            }
            if let noProxy {
                config.noProxy = noProxy
            }
        }
    }

    /// Unsets specific proxy fields. If all fields are `false`, removes the entire configuration.
    ///
    /// - Parameters:
    ///   - http: Whether to remove the HTTP proxy setting.
    ///   - https: Whether to remove the HTTPS proxy setting.
    ///   - noProxy: Whether to remove the noProxy patterns.
    public func unset(http: Bool = false, https: Bool = false, noProxy: Bool = false) throws {
        let removeAll = !http && !https && !noProxy

        if removeAll {
            try self.remove()
        } else {
            try self.apply { config in
                if http {
                    config.http = nil
                }
                if https {
                    config.https = nil
                }
                if noProxy {
                    config.noProxy = nil
                }
            }
        }
    }
}
