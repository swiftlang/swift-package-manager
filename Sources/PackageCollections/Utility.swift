/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import class Foundation.FileManager
import TSCBasic

import PackageModel
import SourceControl

// FIXME: Need a better place to put this + maybe better name
struct Paths {
    static func cache(fileSystem: FileSystem) -> AbsolutePath {
        // use the idiomatic cache directory defined by FileManager when using the local file system
        // otherwise use ~/.swiftpm/cache
        if fileSystem.isLocalFileSystem, let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            return AbsolutePath(cache.path).appending(components: "org.swift.swiftpm")
        }
        return Self.dotSwiftPM(fileSystem: fileSystem).appending(component: "cache")
    }

    static func dotSwiftPM(fileSystem: FileSystem) -> AbsolutePath {
        return fileSystem.homeDirectory.appending(component: ".swiftpm")
    }
}

// FIXME: this is most likely wrong. is there a way to tell if an FS is the local FS / real FS?
// it matters for things like SQLite or FileLock which expect to work on real FS
extension FileSystem {
    var isLocalFileSystem: Bool {
        return ObjectIdentifier(self) == ObjectIdentifier(localFileSystem)
    }
}

// FIXME: Need a better place to put this + maybe better name
protocol Closable {
    func close() throws
}

struct MultipleErrors: Error {
    let errors: [Error]

    init(_ errors: [Error]) {
        self.errors = errors
    }
}

struct NotFoundError: Error {
    let item: String

    init(_ item: String) {
        self.item = item
    }
}
