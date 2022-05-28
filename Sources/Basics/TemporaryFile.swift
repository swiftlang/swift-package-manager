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

import Foundation
import TSCBasic
import TSCLibc

/// Creates a temporary directory and evaluates a closure with the directory path as an argument.
/// The temporary directory will live on disk while the closure is evaluated and will be deleted when
/// the cleanup closure is called. This allows the temporary directory to have an arbitrary lifetime.
///
/// This function is basically a wrapper over posix's mkdtemp() function.
///
/// - Parameters:
///     - dir: If specified the temporary directory will be created in this directory otherwise environment
///            variables TMPDIR, TEMP and TMP will be checked for a value (in that order). If none of the env
///            variables are set, dir will be set to `/tmp/`.
///     - prefix: The prefix to the temporary file name.
///     - body: A closure to execute that receives the absolute path of the directory as an argument.
///           If `body` has a return value, that value is also used as the
///           return value for the `withTemporaryDirectory` function.
///           The cleanup block should be called when the temporary directory is no longer needed.
/// - Returns: `Task<Result, Error>` which can be used
/// - Throws: `MakeDirectoryError` and rethrows all errors from `body`.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public func withTemporaryDirectory<Result>(
    dir: AbsolutePath? = nil,
    prefix: String = "TemporaryDirectory",
    fileSystem: FileSystem = localFileSystem,
    _ body: @escaping (AbsolutePath, @escaping (AbsolutePath) -> Void) async throws -> Result
) throws -> Task<Result, Error> {
    let temporaryDirectory = try createTemporaryDirectory(dir: dir, prefix: prefix, fileSystem: fileSystem)
    
    let task: Task<Result, Error> = Task {
        try await withTaskCancellationHandler {
            try await body(temporaryDirectory) { path in
                try? fileSystem.removeFileTree(path)
            }
        } onCancel: {
            try? fileSystem.removeFileTree(temporaryDirectory)
        }
        
    }
    
    return task
}

/// Creates a temporary directory and evaluates a closure with the directory path as an argument.
/// The temporary directory will live on disk while the closure is evaluated and will be deleted afterwards.
///
/// This function is basically a wrapper over posix's mkdtemp() function.
///
/// - Parameters:
///     - dir: If specified the temporary directory will be created in this directory otherwise environment
///            variables TMPDIR, TEMP and TMP will be checked for a value (in that order). If none of the env
///            variables are set, dir will be set to `/tmp/`.
///     - prefix: The prefix to the temporary file name.
///     - removeTreeOnDeinit: If enabled try to delete the whole directory tree otherwise remove only if its empty.
///     - body: A closure to execute that receives the absolute path of the directory as an argument.
///             If `body` has a return value, that value is also used as the
///             return value for the `withTemporaryDirectory` function.
///
/// - Throws: `MakeDirectoryError` and rethrows all errors from `body`.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public func withTemporaryDirectory<Result>(
    dir: AbsolutePath? = nil,
    prefix: String = "TemporaryDirectory",
    fileSystem: FileSystem = localFileSystem,
    removeTreeOnDeinit: Bool = false,
    _ body: @escaping (AbsolutePath) async throws -> Result
) throws -> Task<Result, Error> {
    try withTemporaryDirectory(dir: dir, prefix: prefix, fileSystem: fileSystem) { path, cleanup in
        defer { if removeTreeOnDeinit { cleanup(path) } }
        return try await body(path)
    }
}

private func createTemporaryDirectory(dir: AbsolutePath?, prefix: String, fileSystem: FileSystem) throws -> AbsolutePath {
    // This random generation is needed so that
    // it is more or less equal to generation using `mkdtemp` function
    let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

    let randomSuffix = String((0..<6).map { _ in letters.randomElement()! })
    
    // Construct path to the temporary directory.
    let templatePath = try AbsolutePath(prefix + ".\(randomSuffix)", relativeTo: determineTempDirectory(dir))

    try fileSystem.createDirectory(templatePath, recursive: true)
    return templatePath
}

private extension MakeDirectoryError {
    init(errno: Int32) {
        switch errno {
        case TSCLibc.EEXIST:
            self = .pathExists
        case TSCLibc.ENAMETOOLONG:
            self = .pathTooLong
        case TSCLibc.EACCES, TSCLibc.EFAULT, TSCLibc.EPERM, TSCLibc.EROFS:
            self = .permissionDenied
        case TSCLibc.ELOOP, TSCLibc.ENOENT, TSCLibc.ENOTDIR:
            self = .unresolvablePathComponent
        case TSCLibc.ENOMEM:
            self = .outOfMemory
#if !os(Windows)
        case TSCLibc.EDQUOT:
            self = .outOfMemory
#endif
        default:
            self = .other(errno)
        }
    }
}
