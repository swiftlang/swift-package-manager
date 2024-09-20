//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
@preconcurrency package import SystemPackage

public actor OSFileSystem: AsyncFileSystem {
  public static let defaultChunkSize = 512 * 1024

  let readChunkSize: Int
  private let ioQueue = DispatchQueue(label: "org.swift.sdk-generator-io")

  package init(readChunkSize: Int = defaultChunkSize) {
    self.readChunkSize = readChunkSize
  }

  package func withOpenReadableFile<T: Sendable>(
    _ path: FilePath,
    _ body: (OpenReadableFile) async throws -> T
  ) async throws -> T {
    let fd = try FileDescriptor.open(path, .readOnly)
    // Can't use ``FileDescriptor//closeAfter` here, as that doesn't support async closures.
    do {
      let result = try await body(.init(chunkSize: readChunkSize, fileHandle: .real(fd, self.ioQueue)))
      try fd.close()
      return result
    } catch {
      try fd.close()
      throw error.attach(path)
    }
  }

  package func withOpenWritableFile<T: Sendable>(
    _ path: FilePath,
    _ body: (OpenWritableFile) async throws -> T
  ) async throws -> T {
      let fd = try FileDescriptor.open(
        path,
        .writeOnly,
        options: [.create, .truncate],
        permissions: [
            .groupRead,
            .otherRead,
            .ownerReadWrite
        ]
      )
    do {
      let result = try await body(.init(storage: .real(fd, self.ioQueue), path: path))
      try fd.close()
      return result
    } catch {
      try fd.close()
      throw error.attach(path)
    }
  }

  package func exists(_ path: SystemPackage.FilePath) async -> Bool {
    FileManager.default.fileExists(atPath: path.string)
  }
}
