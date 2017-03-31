/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import libc
import func POSIX.getenv
import class Foundation.FileHandle
import class Foundation.FileManager

public enum TempFileError: Swift.Error {
    /// Could not create a unique temporary filename.
    case couldNotCreateUniqueName
    /// Some error thrown defined by posix's open().
    // FIXME: This should be factored out into a open error enum.
    case other(Int32)
}

private extension TempFileError {
    init(errno: Int32) {
        switch errno {
        case libc.EEXIST:
            self = .couldNotCreateUniqueName
        default:
            self = .other(errno)
        }
    }
}

/// Determines the directory in which the temporary file should be created. Also makes
/// sure the returning path has a trailing forward slash.
///
/// - Parameters:
///     - dir: If present this will be the temporary directory.
///
/// - Returns: Path to directory in which temporary file should be created.
public func determineTempDirectory(_ dir: AbsolutePath? = nil) -> AbsolutePath {
    // FIXME: Add other platform specific locations.
    let tmpDir = dir ?? cachedTempDirectory
    // FIXME: This is a runtime condition, so it should throw and not crash.
    precondition(localFileSystem.isDirectory(tmpDir))
    return tmpDir
}

/// Returns temporary directory location by searching relevant env variables.
/// Evaluates once per execution.
private var cachedTempDirectory: AbsolutePath = {
    return AbsolutePath(getenv("TMPDIR") ?? getenv("TEMP") ?? getenv("TMP") ?? "/tmp/")
}()

/// This class is basically a wrapper over posix's mkstemps() function to creates disposable files.
/// The file is deleted as soon as the object of this class is deallocated.
public final class TemporaryFile {
    /// If specified during init, the temporary file name begins with this prefix.
    let prefix: String

    /// If specified during init, the temporary file name ends with this suffix.
    let suffix: String

    /// The directory in which the temporary file is created.
    public let dir: AbsolutePath

    /// The full path of the temporary file. For safety file operations should be done via the fileHandle instead of
    /// using this path.
    public let path: AbsolutePath

    /// The file descriptor of the temporary file. It is used to create NSFileHandle which is exposed to clients.
    private let fd: Int32

    /// FileHandle of the temporary file, can be used to read/write data.
    public let fileHandle: FileHandle

    /// Creates an instance of Temporary file. The temporary file will live on disk until the instance
    /// goes out of scope.
    ///
    /// - Parameters:
    ///     - dir: If specified the temporary file will be created in this directory otherwise environment variables
    ///            TMPDIR, TEMP and TMP will be checked for a value (in that order). If none of the env variables are
    ///            set, dir will be set to `/tmp/`.
    ///     - prefix: The prefix to the temporary file name.
    ///     - suffix: The suffix to the temporary file name.
    ///
    /// - Throws: TempFileError
    public init(dir: AbsolutePath? = nil, prefix: String = "TemporaryFile", suffix: String = "") throws {
        self.suffix = suffix
        self.prefix = prefix
        // Determine in which directory to create the temporary file.
        self.dir = determineTempDirectory(dir)
        // Construct path to the temporary file.
        let path = self.dir.appending(RelativePath(prefix + ".XXXXXX" + suffix))

        // Convert path to a C style string terminating with null char to be an valid input
        // to mkstemps method. The XXXXXX in this string will be replaced by a random string
        // which will be the actual path to the temporary file.
        var template = [UInt8](path.asString.utf8).map({ Int8($0) }) + [Int8(0)]

        fd = libc.mkstemps(&template, Int32(suffix.utf8.count))
        // If mkstemps failed then throw error.
        if fd == -1 { throw TempFileError(errno: errno) }

        self.path = AbsolutePath(String(cString: template))
        fileHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    /// Remove the temporary file before deallocating.
    deinit {
        unlink(path.asString)
    }
}

extension TemporaryFile: CustomStringConvertible {
    public var description: String {
        return "<TemporaryFile: \(path)>"
    }
}

/// Contains the error which can be thrown while creating a directory using POSIX's mkdir.
//
// FIXME: This isn't right place to declare this, probably POSIX or merge with FileSystemError?
public enum MakeDirectoryError: Swift.Error {
    /// The given path already exists as a directory, file or symbolic link.
    case pathExists
    /// The path provided was too long.
    case pathTooLong
    /// Process does not have permissions to create directory.
    /// Note: Includes read-only filesystems or if file system does not support directory creation.
    case permissionDenied
    /// The path provided is unresolvable because it has too many symbolic links or a path component is invalid.
    case unresolvablePathComponent
    /// Exceeded user quota or kernel is out of memory.
    case outOfMemory
    /// All other system errors with their value.
    case other(Int32)
}

private extension MakeDirectoryError {
    init(errno: Int32) {
        switch errno {
        case libc.EEXIST:
            self = .pathExists
        case libc.ENAMETOOLONG:
            self = .pathTooLong
        case libc.EACCES, libc.EFAULT, libc.EPERM, libc.EROFS:
            self = .permissionDenied
        case libc.ELOOP, libc.ENOENT, libc.ENOTDIR:
            self = .unresolvablePathComponent
        case libc.ENOMEM, libc.EDQUOT:
            self = .outOfMemory
        default:
            self = .other(errno)
        }
    }
}

/// A class to create disposable directories using POSIX's mkdtemp() method.
public final class TemporaryDirectory {
    /// If specified during init, the temporary directory name begins with this prefix.
    let prefix: String

    /// The full path of the temporary directory.
    public let path: AbsolutePath

    /// If true, try to remove the whole directory tree before deallocating.
    let shouldRemoveTreeOnDeinit: Bool

    /// Creates a temporary directory which is automatically removed when the object of this class goes out of scope.
    ///
    /// - Parameters:
    ///     - dir: If specified the temporary directory will be created in this directory otherwise environment
    ///            variables TMPDIR, TEMP and TMP will be checked for a value (in that order). If none of the env
    ///            variables are set, dir will be set to `/tmp/`.
    ///     - prefix: The prefix to the temporary file name.
    ///     - removeTreeOnDeinit: If enabled try to delete the whole directory tree otherwise remove only if its empty.
    ///
    /// - Throws: MakeDirectoryError
    public init(
        dir: AbsolutePath? = nil,
        prefix: String = "TemporaryDirectory",
        removeTreeOnDeinit: Bool = false
    ) throws {
        self.shouldRemoveTreeOnDeinit = removeTreeOnDeinit
        self.prefix = prefix
        // Construct path to the temporary directory.
        let path = determineTempDirectory(dir).appending(RelativePath(prefix + ".XXXXXX"))

        // Convert path to a C style string terminating with null char to be an valid input
        // to mkdtemp method. The XXXXXX in this string will be replaced by a random string
        // which will be the actual path to the temporary directory.
        var template = [UInt8](path.asString.utf8).map({ Int8($0) }) + [Int8(0)]

        if libc.mkdtemp(&template) == nil {
            throw MakeDirectoryError(errno: errno)
        }

        self.path = AbsolutePath(String(cString: template))
    }

    /// Remove the temporary file before deallocating.
    deinit {
        if shouldRemoveTreeOnDeinit {
            _ = try? FileManager.default.removeItem(atPath: path.asString)
        } else {
            rmdir(path.asString)
        }
    }
}

extension TemporaryDirectory: CustomStringConvertible {
    public var description: String {
        return "<TemporaryDirectory: \(path)>"
    }
}
