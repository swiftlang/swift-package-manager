//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import func TSCBasic.getEnvSearchPaths
import func TSCBasic.lookupExecutablePath
import func TSCBasic.makeDirectories
import func TSCBasic.resolveSymlinks
import func TSCBasic.walk
import func TSCBasic.withTemporaryDirectory

import struct TSCBasic.FileSystemError
import class TSCBasic.LocalFileOutputByteStream
import enum TSCBasic.ProcessEnv
import class TSCBasic.RecursibleDirectoryContentsGenerator

public func resolveSymlinks(_ path: AbsolutePath) throws -> AbsolutePath {
    try AbsolutePath(TSCBasic.resolveSymlinks(path.underlying))
}

public func withTemporaryDirectory<Result>(
    dir: AbsolutePath? = nil, prefix: String = "TemporaryDirectory",
    _ body: (AbsolutePath, @escaping (AbsolutePath) -> Void) throws -> Result
) throws -> Result {
    try TSCBasic.withTemporaryDirectory(dir: dir?.underlying, prefix: prefix) { path, callback in
        let callback2 = { (path: AbsolutePath) in
            callback(path.underlying)
        }
        return try body(AbsolutePath(path), callback2)
    }
}

public func withTemporaryDirectory<Result>(
    dir: AbsolutePath? = nil, prefix: String = "TemporaryDirectory",
    _ body: (AbsolutePath, @escaping (AbsolutePath) async -> Void) async throws -> Result
) async throws -> Result {
    try await TSCBasic.withTemporaryDirectory(dir: dir?.underlying, prefix: prefix) { path, callback in
        let callback2: (AbsolutePath) async -> Void = { (path: AbsolutePath) in
            await callback(path.underlying)
        }
        return try await body(AbsolutePath(path), callback2)
    }
}

public func withTemporaryDirectory<Result>(
    dir: AbsolutePath? = nil, prefix: String = "TemporaryDirectory", removeTreeOnDeinit: Bool = false,
    _ body: (AbsolutePath) throws -> Result
) throws -> Result {
    try TSCBasic.withTemporaryDirectory(dir: dir?.underlying, prefix: prefix, removeTreeOnDeinit: removeTreeOnDeinit) {
        try body(AbsolutePath($0))
    }
}

public func withTemporaryDirectory<Result>(
    dir: AbsolutePath? = nil, prefix: String = "TemporaryDirectory", removeTreeOnDeinit: Bool = false,
    _ body: (AbsolutePath) async throws -> Result
) async throws -> Result {
    try await TSCBasic.withTemporaryDirectory(
        dir: dir?.underlying,
        prefix: prefix,
        removeTreeOnDeinit: removeTreeOnDeinit
    ) {
        try await body(AbsolutePath($0))
    }
}

/// Lookup an executable path from an environment variable value, current working
/// directory or search paths. Only return a value that is both found and executable.
///
/// This method searches in the following order:
/// * If env value is a valid absolute path, return it.
/// * If env value is relative path, first try to locate it in current working directory.
/// * Otherwise, in provided search paths.
///
/// - Parameters:
///   - filename: The name of the file to find.
///   - currentWorkingDirectory: The current working directory to look in.
///   - searchPaths: The additional search paths to look in if not found in cwd.
/// - Returns: Valid path to executable if present, otherwise nil.
public func lookupExecutablePath(
    filename: String?,
    currentWorkingDirectory: AbsolutePath? = localFileSystem.currentWorkingDirectory,
    searchPaths: [AbsolutePath] = []
) -> AbsolutePath? {
    TSCBasic.lookupExecutablePath(
        filename: filename,
        currentWorkingDirectory: currentWorkingDirectory?.underlying,
        searchPaths: searchPaths.map(\.underlying)
    ).flatMap { AbsolutePath($0) }
}

/// Create a list of AbsolutePath search paths from a string, such as the PATH environment variable.
///
/// - Parameters:
///   - pathString: The path string to parse.
///   - currentWorkingDirectory: The current working directory, the relative paths will be converted to absolute paths
///     based on this path.
/// - Returns: List of search paths.
public func getEnvSearchPaths(
    pathString: String?,
    currentWorkingDirectory: AbsolutePath?
) -> [AbsolutePath] {
    TSCBasic.getEnvSearchPaths(
        pathString: pathString,
        currentWorkingDirectory: currentWorkingDirectory?.underlying
    ).map { AbsolutePath($0) }
}

public func walk(
    _ path: AbsolutePath,
    fileSystem: FileSystem = localFileSystem,
    recursively: Bool = true
) throws -> WalkResult {
    let result = try TSCBasic.walk(
        path.underlying,
        fileSystem: fileSystem,
        recursively: recursively
    )
    return WalkResult(result)
}

public class WalkResult: IteratorProtocol, Sequence {
    private let underlying: TSCBasic.RecursibleDirectoryContentsGenerator

    init(_ underlying: TSCBasic.RecursibleDirectoryContentsGenerator) {
        self.underlying = underlying
    }

    public func next() -> AbsolutePath? {
        self.underlying.next().flatMap { AbsolutePath($0) }
    }
}

public func makeDirectories(_ path: AbsolutePath) throws {
    try TSCBasic.makeDirectories(path.underlying)
}

extension TSCBasic.LocalFileOutputByteStream {
    public convenience init(_ path: AbsolutePath, closeOnDeinit: Bool = true, buffered: Bool = true) throws {
        try self.init(path.underlying, closeOnDeinit: closeOnDeinit, buffered: buffered)
    }
}

extension TSCBasic.ProcessEnv {
    public static func chdir(_ path: AbsolutePath) throws {
        try self.chdir(path.underlying)
    }
}

extension TSCBasic.FileSystemError {
    @_disfavoredOverload
    public init(_ kind: Kind, _ path: AbsolutePath? = nil) {
        self.init(kind, path?.underlying)
    }
}
