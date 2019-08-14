/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import SPMLibc
import class Foundation.FileHandle
import class Foundation.FileManager
import func Foundation.NSTemporaryDirectory

public enum TempFileError: Swift.Error {
    /// Could not create a unique temporary filename.
    case couldNotCreateUniqueName

    // FIXME: This should be factored out into a open error enum.
    //
    /// Some error thrown defined by posix's open().
    case other(Int32)

    /// Couldn't find a temporary directory.
    case couldNotFindTmpDir
}

private extension TempFileError {
    init(errno: Int32) {
        switch errno {
        case SPMLibc.EEXIST:
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
public func determineTempDirectory(_ dir: AbsolutePath? = nil) throws -> AbsolutePath {
    // FIXME: Add other platform specific locations.
    let tmpDir = dir ?? AbsolutePath(NSTemporaryDirectory())
    guard localFileSystem.isDirectory(tmpDir) else {
        throw TempFileError.couldNotFindTmpDir
    }
    return tmpDir
}

// NOTE: These two functions are lifted from Foundation.  They are not part of
// the public interface from Foundation, so we have replicated them here to
// provide a platform agnostic way to create temporary files and directories on
// platforms which do not provide `mkstemp` or `mkdtemp` (e.g. Windows).

private func _NSCreateTemporaryFile(_ template: String) throws -> (Int32, String) {
#if os(Windows)
  var buffer: [WCHAR] = Array<WCHAR>(repeating: 0, count: template.length)
  _ = template.withCString(encodedAs: UTF16.self, { wcscpy(&buffer, $0) })
  _ = _wmktemp(&buffer)

  let handle: HANDLE =
      CreateFileW(&buffer, GENERIC_READ | DWORD(GENERIC_WRITE),
                  DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE),
                  nil, DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
  guard handle != INVALID_HANDLE_VALUE else { return (-1, "") }

  // Don't close handle, fd is transfered ownership
  let fd: Int32 = _open_osfhandle(intptr_t(bitPattern: handle), 0)
  let result: String = String(decodingCString: &buffer, as: UTF16.self)
  return (fd, result)
#else
  let count: Int = Int(PATH_MAX) + 1
  var buffer: [CChar] = Array<CChar>(repeating: 0, count: count)
  let _ = template.getFileSystemRepresentation(&buffer, maxLength: count)
  let fd: Int32 = mkstemp(&buffer)
  guard fd != -1 else { throw TempFileError(errno: errno) }
  let result: String = FileManager.default.string(withFileSystemRepresentation: buffer, length: strlen(buffer))
  return (fd, result)
#endif
}

private func _NSCreateTemporaryDirectory(_ template: String) throws -> String {
#if os(Windows)
  var buffer: [WCHAR] = Array<WCHAR>(repeating: 0, count: template.length)
  _ = template.withCString(encodedAs: UTF16.self, { wcscpy(&buffer, $0) })
  _ = _wmktemp(&buffer)
  let location: String = String(decodingCString: &buffer, as: UTF16.self)

  try FileManager.default.createDirectory(atPath: location, withIntermediateDirectories: false)
  return location
#else
  let count: Int = Int(PATH_MAX) + 1
  var buffer: [CChar] = Array<CChar>(repeating: 0, count: count)
  let _ = template.getFileSystemRepresentation(&buffer, maxLength: count)
  if SPMLibc.mkdtemp(&buffer) == nil {
    throw MakeDirectoryError(errno: errno)
  }
  return FileManager.default.string(withFileSystemRepresentation: buffer, length: strlen(buffer))
#endif
}

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
    
    /// Whether the file should be deleted on dealloc.
    public let deleteOnClose: Bool

    /// Creates an instance of Temporary file. The temporary file will live on disk until the instance
    /// goes out of scope.
    ///
    /// - Parameters:
    ///     - dir: If specified the temporary file will be created in this directory otherwise environment variables
    ///            TMPDIR, TEMP and TMP will be checked for a value (in that order). If none of the env variables are
    ///            set, dir will be set to `/tmp/`.
    ///     - prefix: The prefix to the temporary file name.
    ///     - suffix: The suffix to the temporary file name.
    ///     - deleteOnClose: Whether the file should get deleted when the instance is deallocated.
    ///
    /// - Throws: TempFileError
    public init(dir: AbsolutePath? = nil, prefix: String = "TemporaryFile", suffix: String = "", deleteOnClose: Bool = true) throws {
        self.suffix = suffix
        self.prefix = prefix
        self.deleteOnClose = deleteOnClose
        // Determine in which directory to create the temporary file.
        self.dir = try determineTempDirectory(dir)
        // Construct path to the temporary file.
        let path = self.dir.appending(RelativePath(prefix + ".XXXXXX" + suffix))

        let (fd, location) = try _NSCreateTemporaryFile(path.pathString)

        self.fd = fd
        self.path = AbsolutePath(location)
        fileHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    /// Remove the temporary file before deallocating.
    deinit {
        if deleteOnClose {
            unlink(path.pathString)
        }
    }
}

extension TemporaryFile: CustomStringConvertible {
    public var description: String {
        return "<TemporaryFile: \(path)>"
    }
}

// FIXME: This isn't right place to declare this, probably POSIX or merge with FileSystemError?
//
/// Contains the error which can be thrown while creating a directory using POSIX's mkdir.
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
        case SPMLibc.EEXIST:
            self = .pathExists
        case SPMLibc.ENAMETOOLONG:
            self = .pathTooLong
        case SPMLibc.EACCES, SPMLibc.EFAULT, SPMLibc.EPERM, SPMLibc.EROFS:
            self = .permissionDenied
        case SPMLibc.ELOOP, SPMLibc.ENOENT, SPMLibc.ENOTDIR:
            self = .unresolvablePathComponent
        case SPMLibc.ENOMEM:
            self = .outOfMemory
#if !os(Windows)
        case SPMLibc.EDQUOT:
            self = .outOfMemory
#endif
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
        let path = try determineTempDirectory(dir).appending(RelativePath(prefix + ".XXXXXX"))

        let location = try? _NSCreateTemporaryDirectory(path.pathString)
        self.path = AbsolutePath(location!)
    }

    /// Remove the temporary file before deallocating.
    deinit {
        let isEmptyDirectory: (String) -> Bool = { path in
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else { return false }
            return contents.isEmpty
        }

        if shouldRemoveTreeOnDeinit || isEmptyDirectory(path.pathString) {
            _ = try? FileManager.default.removeItem(atPath: path.pathString)
        }
    }
}

extension TemporaryDirectory: CustomStringConvertible {
    public var description: String {
        return "<TemporaryDirectory: \(path)>"
    }
}
