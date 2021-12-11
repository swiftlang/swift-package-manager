/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import class Foundation.FileManager
import struct Foundation.Data
import struct Foundation.UUID
import TSCBasic

// MARK: - user level

extension FileSystem {
    /// SwiftPM directory under user's home directory (~/.swiftpm)
    public var dotSwiftPM: AbsolutePath {
        self.homeDirectory.appending(component: ".swiftpm")
    }
}

// MARK: - cache

extension FileSystem {
    private var idiomaticUserCacheDirectory: AbsolutePath? {
        // in TSC: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        self.cachesDirectory
    }

    /// SwiftPM cache directory under user's caches directory (if exists)
    public var swiftPMCacheDirectory: AbsolutePath {
        if let path = self.idiomaticUserCacheDirectory {
            return path.appending(component: "org.swift.swiftpm")
        } else {
            return self.dotSwiftPMCachesDirectory
        }
    }

    fileprivate var dotSwiftPMCachesDirectory: AbsolutePath {
        return self.dotSwiftPM.appending(component: "cache")
    }
}

extension FileSystem {
    public func getOrCreateSwiftPMCacheDirectory() throws -> AbsolutePath {
        let idiomaticCacheDirectory = self.swiftPMCacheDirectory
        // Create idiomatic if necessary
        if !self.exists(idiomaticCacheDirectory) {
            try self.createDirectory(idiomaticCacheDirectory, recursive: true)
        }
        // Create ~/.swiftpm if necessary
        if !self.exists(self.dotSwiftPM) {
            try self.createDirectory(self.dotSwiftPM, recursive: true)
        }
        // Create ~/.swiftpm/cache symlink if necessary
        if !self.exists(self.dotSwiftPMCachesDirectory, followSymlink: false) {
            try self.createSymbolicLink(dotSwiftPMCachesDirectory, pointingAt: idiomaticCacheDirectory, relative: false)
        }
        return idiomaticCacheDirectory
    }
}

// MARK: - config

extension FileSystem {
    private var idiomaticUserConfigDirectory: AbsolutePath? {
        return FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first.flatMap { AbsolutePath($0.path) }
    }

    /// SwiftPM config directory under user's config directory (if exists)
    public var swiftPMConfigDirectory: AbsolutePath {
        if let path = self.idiomaticUserConfigDirectory {
            return path.appending(component: "org.swift.swiftpm")
        } else {
            return self.dotSwiftPMConfigDirectory
        }
    }

    fileprivate var dotSwiftPMConfigDirectory: AbsolutePath {
        return self.dotSwiftPM.appending(component: "config")
    }
}

extension FileSystem {
    public func getOrCreateSwiftPMConfigDirectory() throws -> AbsolutePath {
        let idiomaticConfigDirectory = self.swiftPMConfigDirectory

        // temporary 5.5, remove on next version: transition from ~/.swiftpm/config to idiomatic location + symbolic link
        if idiomaticConfigDirectory != self.dotSwiftPMConfigDirectory &&
            self.exists(self.dotSwiftPMConfigDirectory) && self.isDirectory(self.dotSwiftPMConfigDirectory) &&
            !self.exists(idiomaticConfigDirectory) {
            print("transitioning \(self.dotSwiftPMConfigDirectory) to \(idiomaticConfigDirectory)")
            try self.move(from: self.dotSwiftPMConfigDirectory, to: idiomaticConfigDirectory)
        }

        // Create idiomatic if necessary
        if !self.exists(idiomaticConfigDirectory) {
            try self.createDirectory(idiomaticConfigDirectory, recursive: true)
        }
        // Create ~/.swiftpm if necessary
        if !self.exists(self.dotSwiftPM) {
            try self.createDirectory(self.dotSwiftPM, recursive: true)
        }
        // Create ~/.swiftpm/config symlink if necessary
        if !self.exists(self.dotSwiftPMConfigDirectory, followSymlink: false) {
            try self.createSymbolicLink(dotSwiftPMConfigDirectory, pointingAt: idiomaticConfigDirectory, relative: false)
        }
        return idiomaticConfigDirectory
    }
}

// MARK: - security

extension FileSystem {
    /// SwiftPM security directory
    public var swiftPMSecurityDirectory: AbsolutePath {
        self.dotSwiftPM.appending(component: "security")
    }
    
    public var swiftPMFingerprintsDirectory: AbsolutePath {
        self.swiftPMSecurityDirectory.appending(component: "fingerprints")
    }
}

// MARK: - Utilities

extension FileSystem {
    public func readFileContents(_ path: AbsolutePath) throws -> Data {
        return try Data(self.readFileContents(path).contents)
    }

    public func readFileContents(_ path: AbsolutePath) throws -> String {
        return try String(decoding: self.readFileContents(path), as: UTF8.self)
    }

    public func writeFileContents(_ path: AbsolutePath, data: Data) throws {
        return try self.writeFileContents(path, bytes: .init(data))
    }

    public func writeFileContents(_ path: AbsolutePath, string: String) throws {
        return try self.writeFileContents(path, bytes: .init(encodingAsUTF8: string))
    }

    public func writeFileContents(_ path: AbsolutePath, provider: () -> String) throws {
        return try self.writeFileContents(path, string: provider())
    }
}

extension FileSystem {
    public func forceCreateDirectory(at path: AbsolutePath) throws {
        try self.createDirectory(path.parentDirectory, recursive: true)
        if self.exists(path) {
            try self.removeFileTree(path)
        }
        try self.createDirectory(path, recursive: true)
    }
}

extension FileSystem {
    public func stripFirstLevel(of path: AbsolutePath) throws {
        let topLevelContents = try self.getDirectoryContents(path)
        guard topLevelContents.count == 1, let rootPath = topLevelContents.first.map({ path.appending(component: $0) }), self.isDirectory(rootPath) else {
            throw StringError("stripFirstLevel requires single top level directory")
        }

        let tempDirectory = path.parentDirectory.appending(component: UUID().uuidString)
        try self.move(from: rootPath, to: tempDirectory)

        let rootContents = try self.getDirectoryContents(tempDirectory)
        for entry in rootContents {
            try self.move(from: tempDirectory.appending(component: entry), to: path.appending(component: entry))
        }

        try self.removeFileTree(tempDirectory)
    }
}
