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
///
/// - Throws: `MakeDirectoryError` and rethrows all errors from `body`.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public func withTemporaryDirectory<Result>(
  dir: AbsolutePath? = nil, prefix: String = "TemporaryDirectory" , _ body: (AbsolutePath, @escaping (AbsolutePath) -> Void) async throws -> Result
) async throws -> Result {
    let template = try createTemporaryDirectoryTemplate(dir: dir, prefix: prefix)
  return try await body(AbsolutePath(String(cString: template))) { path in
    _ = try? FileManager.default.removeItem(atPath: path.pathString)
  }
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
  dir: AbsolutePath? = nil, prefix: String = "TemporaryDirectory", removeTreeOnDeinit: Bool = false , _ body: (AbsolutePath) async throws -> Result
) async throws -> Result {
  try await withTemporaryDirectory(dir: dir, prefix: prefix) { path, cleanup in
    defer { if removeTreeOnDeinit { cleanup(path) } }
    return try await body(path)
  }
}

private func createTemporaryDirectoryTemplate(dir: AbsolutePath?, prefix: String) throws -> [Int8] {
    // Construct path to the temporary directory.
    let templatePath = try AbsolutePath(prefix + ".XXXXXX", relativeTo: determineTempDirectory(dir))

    // Convert templatePath to a C style string terminating with null char to be an valid input
    // to mkdtemp method. The XXXXXX in this string will be replaced by a random string
    // which will be the actual path to the temporary directory.
    var template = [UInt8](templatePath.pathString.utf8).map({ Int8($0) }) + [Int8(0)]

    if TSCLibc.mkdtemp(&template) == nil {
        throw MakeDirectoryError(errno: errno)
    }
    return template
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
