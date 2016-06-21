/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import libc
import func POSIX.getenv
import class Foundation.FileHandle

public enum TempFileError: ErrorProtocol {
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

/// This class is basically a wrapper over posix's mkstemps() function to creates disposable files.
/// The file is deleted as soon as the object of this class is deallocated.
public final class TemporaryFile {
    /// If specified during init, the temporary file name begins with this prefix.
    let prefix: String

    /// If specified during init, the temporary file name ends with this suffix.
    let suffix: String

    /// The directory in which the temporary file is created.
    public let dir: String

    /// The full path of the temporary file. For safety file operations should be done via the fileHandle instead of using this path.
    public let path: String

    /// The file descriptor of the temporary file. It is used to create NSFileHandle which is exposed to clients.
    private let fd: Int32

    /// FileHandle of the temporary file, can be used to read/write data.
    public let fileHandle: FileHandle

    /// Creates an instance of Temporary file. The temporary file will live on disk until the instance
    /// goes out of scope.
    ///
    /// - Parameters:
    ///     - dir: If specified the temporary file will be created in this directory otherwise enviornment variables
    ///            TMPDIR, TEMP and TMP will be checked for a value (in that order). If none of the env variables are
    ///            set, dir will be set to `/tmp/`.
    ///     - prefix: The prefix to the temporary file name.
    ///     - suffix: The suffix to the temporary file name.
    ///
    /// - Throws: TempFileError
    public init(dir: String? = nil, prefix: String = "TemporaryFile", suffix: String = "") throws {
        self.suffix = suffix
        self.prefix = prefix
        // Determine in which directory to create the temporary file.
        self.dir = TemporaryFile.determineTempDirectory(dir)
        // Construct path to the temporary file.
        let path = self.dir + prefix + ".XXXXXX" + suffix

        // Convert path to a C style string terminating with null char to be an valid input
        // to mkstemps method. The XXXXXX in this string will be replaced by a random string
        // which will be the actual path to the temporary file.
        var template = [UInt8](path.utf8).map{ Int8($0) } + [Int8(0)]

        fd = libc.mkstemps(&template, Int32(suffix.utf8.count))
        // If mkstemps failed then throw error.
        if fd == -1 { throw TempFileError(errno: errno) }

        self.path = String(cString: template)
        fileHandle = FileHandle(fileDescriptor: fd)
    }

    /// Remove the temporary file before deallocating.
    deinit { unlink(path) }

    /// Determines the directory in which the temporary file should be created. Also makes
    /// sure the returning path has a trailing forward slash.
    ///
    /// - Parameters:
    ///     - dir: If present this will be the temporary directory.
    ///
    /// - Returns: Path to directory in which temporary file should be created.
    private static func determineTempDirectory(_ dir: String? = nil) -> String {
        // FIXME: Add other platform specific locations.
        var tmpDir = dir ?? cachedTempDirectory
        if !tmpDir.hasSuffix("/") { tmpDir += "/" }
        precondition(tmpDir.isDirectory)
        return tmpDir
    }

    /// Returns temporary directory location by searching relevant env variables. 
    /// Evaluates once per execution.
    private static var cachedTempDirectory: String = {
        return getenv("TMPDIR") ?? getenv("TEMP") ?? getenv("TMP") ?? "/tmp/"
    }()
}

extension TemporaryFile: CustomStringConvertible {
    public var description: String {
        return "<TemporaryFile: \(path)>"
    }
}
