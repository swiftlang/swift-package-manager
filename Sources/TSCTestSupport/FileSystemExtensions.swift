/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func XCTest.XCTFail

import TSCBasic
import TSCUtility

#if os(macOS)
import class Foundation.Bundle
#endif

/// Convenience initializers for testing purposes.
extension InMemoryFileSystem {
    /// Create a new file system with the given files, provided as a map from
    /// file path to contents.
    public convenience init(files: [String: ByteString]) {
        self.init()

        for (path, contents) in files {
            let path = AbsolutePath(path)
            try! createDirectory(path.parentDirectory, recursive: true)
            try! writeFileContents(path, bytes: contents)
        }
    }

    /// Create a new file system with an empty file at each provided path.
    public convenience init(emptyFiles files: String...) {
        self.init(emptyFiles: files)
    }

    /// Create a new file system with an empty file at each provided path.
    public convenience init(emptyFiles files: [String]) {
        self.init()
        self.createEmptyFiles(at: .root, files: files)
    }
}

extension FileSystem {
    public func createEmptyFiles(at root: AbsolutePath, files: String...) {
        self.createEmptyFiles(at: root, files: files)
    }

    public func createEmptyFiles(at root: AbsolutePath, files: [String]) {
        do {
            try createDirectory(root, recursive: true)
            for path in files {
                let path = root.appending(RelativePath(String(path.dropFirst())))
                try createDirectory(path.parentDirectory, recursive: true)
                try writeFileContents(path, bytes: "")
            }
        } catch {
            fatalError("Failed to create empty files: \(error)")
        }
    }
}

extension FileSystem {
    /// Print the contents of the directory. Only for debugging purposes.
    public func dump(directory path: AbsolutePath) {
        do {
        print(try getDirectoryContents(path))
        } catch {
            print(String(describing: error))
        }
    }
}
