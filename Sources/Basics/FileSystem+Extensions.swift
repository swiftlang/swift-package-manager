/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic
import class Foundation.FileManager

// MARK: - user level

extension FileSystem {
    /// SwiftPM directory under user's home directory (~/.swiftpm)
    public var dotSwiftPM: AbsolutePath {
        return self.homeDirectory.appending(component: ".swiftpm")
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

extension FileSystem {
    public func makeTemplate(path: AbsolutePath, type: String) throws {
        try self.writeFileContents(path) { stream in
            stream <<< """
            {
                "directories": {
                    "sources": "./Sources",
                    "tests": "./Tests",
                    "createSubDirectoryForModule": true
                },
                "type": "\(type)",
                "dependencies": []
            }
            """
        }
    }
}
