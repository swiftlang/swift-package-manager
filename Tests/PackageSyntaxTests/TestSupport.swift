/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

// FIXME: Find a way to share this with SwiftPM
import TSCBasic
import XCTest

extension InMemoryFileSystem {
  /// Create a new file system with an empty file at each provided path.
  convenience init(emptyFiles files: String...) {
      self.init(emptyFiles: files)
  }

  /// Create a new file system with an empty file at each provided path.
  convenience init(emptyFiles files: [String]) {
      self.init()
      self.createEmptyFiles(at: .root, files: files)
  }
}

extension FileSystem {
    func createEmptyFiles(at root: AbsolutePath, files: String...) {
        self.createEmptyFiles(at: root, files: files)
    }

    func createEmptyFiles(at root: AbsolutePath, files: [String]) {
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

func XCTAssertThrows<T: Swift.Error>(
  _ expectedError: T,
  file: StaticString = #file,
  line: UInt = #line,
  _ body: () throws -> Void
) where T: Equatable {
  do {
    try body()
    XCTFail("body completed successfully", file: file, line: line)
  } catch let error as T {
    XCTAssertEqual(error, expectedError, file: file, line: line)
  } catch {
    XCTFail("unexpected error thrown: \(error)", file: file, line: line)
  }
}
