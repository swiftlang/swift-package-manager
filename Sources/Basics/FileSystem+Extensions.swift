//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import class Foundation.FileManager
import struct Foundation.Data
import struct Foundation.UUID
import SystemPackage
import TSCBasic

// MARK: - user level

extension FileSystem {
    /// SwiftPM directory under user's home directory (~/.swiftpm)
    public var dotSwiftPM: AbsolutePath {
        self.homeDirectory.appending(component: ".swiftpm")
    }

    fileprivate var idiomaticSwiftPMDirectory: AbsolutePath? {
        return FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first.flatMap { AbsolutePath($0.path) }?.appending(component: "org.swift.swiftpm")
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
        // locking ~/.swiftpm to protect from concurrent access
        try self.withLock(on: self.dotSwiftPM, type: .exclusive) {
            if !self.exists(self.dotSwiftPMCachesDirectory, followSymlink: false) {
                try self.createSymbolicLink(dotSwiftPMCachesDirectory, pointingAt: idiomaticCacheDirectory, relative: false)
            }
        }
        return idiomaticCacheDirectory
    }
}

// MARK: - configuration

extension FileSystem {
    /// SwiftPM config directory under user's config directory (if exists)
    public var swiftPMConfigurationDirectory: AbsolutePath {
        if let path = self.idiomaticSwiftPMDirectory {
            return path.appending(component: "configuration")
        } else {
            return self.dotSwiftPMConfigurationDirectory
        }
    }

    fileprivate var dotSwiftPMConfigurationDirectory: AbsolutePath {
        return self.dotSwiftPM.appending(component: "configuration")
    }
}

extension FileSystem {
    public func getOrCreateSwiftPMConfigurationDirectory(warningHandler: (String) -> Void) throws -> AbsolutePath {
        let idiomaticConfigurationDirectory = self.swiftPMConfigurationDirectory

        // temporary 5.6, remove on next version: transition from previous configuration location
        if !self.exists(idiomaticConfigurationDirectory) {
            try self.createDirectory(idiomaticConfigurationDirectory, recursive: true)
        }

        // in the case where ~/.swiftpm/configuration is not the idiomatic location (eg on macOS where its /Users/<user>/Library/org.swift.swiftpm/configuration)
        if idiomaticConfigurationDirectory != self.dotSwiftPMConfigurationDirectory {
            // copy the configuration files from old location (eg /Users/<user>/Library/org.swift.swiftpm) to new one (eg /Users/<user>/Library/org.swift.swiftpm/configuration)
            // but leave them there for backwards compatibility (eg older xcode)
            let oldConfigDirectory = idiomaticConfigurationDirectory.parentDirectory
            if self.exists(oldConfigDirectory, followSymlink: false) && self.isDirectory(oldConfigDirectory) {
                let configurationFiles = try self.getDirectoryContents(oldConfigDirectory)
                    .map{ oldConfigDirectory.appending(component: $0) }
                    .filter{ self.isFile($0) && !self.isSymlink($0) && $0.extension != "lock" && ((try? self.readFileContents($0)) ?? []).count > 0 }
                for file in configurationFiles {
                    let destination = idiomaticConfigurationDirectory.appending(component: file.basename)
                    if !self.exists(destination) {
                        try self.copy(from: file, to: destination)
                    }
                    warningHandler("Usage of \(file) has been deprecated. Please delete it and use the new \(destination) instead.")
                }
            }
        // in the case where ~/.swiftpm/configuration is the idiomatic location (eg on Linux)
        } else {
            // copy the configuration files from old location (~/.swiftpm/config) to new one (~/.swiftpm/configuration)
            // but leave them there for backwards compatibility (eg older toolchain)
            let oldConfigDirectory = self.dotSwiftPM.appending(component: "config")
            if self.exists(oldConfigDirectory, followSymlink: false) && self.isDirectory(oldConfigDirectory) {
                let configurationFiles = try self.getDirectoryContents(oldConfigDirectory)
                    .map{ oldConfigDirectory.appending(component: $0) }
                    .filter{ self.isFile($0) && !self.isSymlink($0) && $0.extension != "lock" && ((try? self.readFileContents($0)) ?? []).count > 0 }
                for file in configurationFiles {
                    let destination = idiomaticConfigurationDirectory.appending(component: file.basename)
                    if !self.exists(destination) {
                        try self.copy(from: file, to: destination)
                    }
                    warningHandler("Usage of \(file) has been deprecated. Please delete it and use the new \(destination) instead.")
                }
            }
        }
        // ~temporary 5.6 migration

        // Create idiomatic if necessary
        if !self.exists(idiomaticConfigurationDirectory) {
            try self.createDirectory(idiomaticConfigurationDirectory, recursive: true)
        }
        // Create ~/.swiftpm if necessary
        if !self.exists(self.dotSwiftPM) {
            try self.createDirectory(self.dotSwiftPM, recursive: true)
        }
        // Create ~/.swiftpm/configuration symlink if necessary
        // locking ~/.swiftpm to protect from concurrent access
        try self.withLock(on: self.dotSwiftPM, type: .exclusive) {
            if !self.exists(self.dotSwiftPMConfigurationDirectory, followSymlink: false) {
                try self.createSymbolicLink(dotSwiftPMConfigurationDirectory, pointingAt: idiomaticConfigurationDirectory, relative: false)
            }
        }

        return idiomaticConfigurationDirectory
    }
}

// MARK: - security

extension FileSystem {
    /// SwiftPM security directory under user's security directory (if exists)
    public var swiftPMSecurityDirectory: AbsolutePath {
        if let path = self.idiomaticSwiftPMDirectory {
            return path.appending(component: "security")
        } else {
            return self.dotSwiftPMSecurityDirectory
        }
    }

    fileprivate var dotSwiftPMSecurityDirectory: AbsolutePath {
        return self.dotSwiftPM.appending(component: "security")
    }
}

extension FileSystem {
    public func getOrCreateSwiftPMSecurityDirectory() throws -> AbsolutePath {
        let idiomaticSecurityDirectory = self.swiftPMSecurityDirectory

        // temporary 5.6, remove on next version: transition from ~/.swiftpm/security to idiomatic location + symbolic link
        if idiomaticSecurityDirectory != self.dotSwiftPMSecurityDirectory &&
            self.exists(self.dotSwiftPMSecurityDirectory) &&
            self.isDirectory(self.dotSwiftPMSecurityDirectory) {
            try self.removeFileTree(self.dotSwiftPMSecurityDirectory)
        }
        // ~temporary 5.6 migration

        // Create idiomatic if necessary
        if !self.exists(idiomaticSecurityDirectory) {
            try self.createDirectory(idiomaticSecurityDirectory, recursive: true)
        }
        // Create ~/.swiftpm if necessary
        if !self.exists(self.dotSwiftPM) {
            try self.createDirectory(self.dotSwiftPM, recursive: true)
        }
        // Create ~/.swiftpm/security symlink if necessary
        // locking ~/.swiftpm to protect from concurrent access
        try self.withLock(on: self.dotSwiftPM, type: .exclusive) {
            if !self.exists(self.dotSwiftPMSecurityDirectory, followSymlink: false) {
                try self.createSymbolicLink(dotSwiftPMSecurityDirectory, pointingAt: idiomaticSecurityDirectory, relative: false)
            }
        }
        return idiomaticSecurityDirectory
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
        let topLevelDirectories = try self.getDirectoryContents(path)
            .map{ path.appending(component: $0) }
            .filter{ self.isDirectory($0) }

        guard topLevelDirectories.count == 1, let rootDirectory = topLevelDirectories.first else {
            throw StringError("stripFirstLevel requires single top level directory")
        }

        let tempDirectory = path.parentDirectory.appending(component: UUID().uuidString)
        try self.move(from: rootDirectory, to: tempDirectory)

        let rootContents = try self.getDirectoryContents(tempDirectory)
        for entry in rootContents {
            try self.move(from: tempDirectory.appending(component: entry), to: path.appending(component: entry))
        }

        try self.removeFileTree(tempDirectory)
    }
}
