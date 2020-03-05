/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 -------------------------------------------------------------------------
 
 This file contains temporary shim functions for use during the adoption of
 AbsolutePath and RelativePath.  The eventual plan is to use the FileSystem
 API for all of this, at which time this file will go way.  But since it is
 important to have a quality FileSystem API, we will evolve it slowly.
 
 Meanwhile this file bridges the gap to let call sites be as clean as possible,
 while making it fairly easy to find those calls later.
*/

import TSCLibc
import Foundation

/// Returns the "real path" corresponding to `path` by resolving any symbolic links.
public func resolveSymlinks(_ path: AbsolutePath) -> AbsolutePath {
    let pathStr = path.pathString

    // FIXME: We can't use FileManager's destinationOfSymbolicLink because
    // that implements readlink and not realpath.
    if let resultPtr = TSCLibc.realpath(pathStr, nil) {
        let result = String(cString: resultPtr)
        // If `resolved_path` is specified as NULL, then `realpath` uses
        // malloc(3) to allocate a buffer [...].  The caller should deallocate
        // this buffer using free(3).
        //
        // String.init(cString:) creates a new string by copying the
        // null-terminated UTF-8 data referenced by the given pointer.
        resultPtr.deallocate()
        // FIXME: We should measure if it's really more efficient to compare the strings first.
        return result == pathStr ? path : AbsolutePath(result)
    }

    return path
}

/// Creates a new, empty directory at `path`.  If needed, any non-existent ancestor paths are also created.  If there is
/// already a directory at `path`, this function does nothing (in particular, this is not considered to be an error).
public func makeDirectories(_ path: AbsolutePath) throws {
    try FileManager.default.createDirectory(atPath: path.pathString, withIntermediateDirectories: true, attributes: [:])
}

/// Creates a symbolic link at `path` whose content points to `dest`.  If `relative` is true, the symlink contents will
/// be a relative path, otherwise it will be absolute.
public func createSymlink(_ path: AbsolutePath, pointingAt dest: AbsolutePath, relative: Bool = true) throws {
    let destString = relative ? dest.relative(to: path.parentDirectory).pathString : dest.pathString
    try FileManager.default.createSymbolicLink(atPath: path.pathString, withDestinationPath: destString)
}

/// The current working directory of the processs.
@available(*, deprecated, renamed: "localFileSystem.currentWorkingDirectory")
public var currentWorkingDirectory: AbsolutePath {
    let cwdStr = FileManager.default.currentDirectoryPath
    return AbsolutePath(cwdStr)
}

/**
 - Returns: a generator that walks the specified directory producing all
 files therein. If recursively is true will enter any directories
 encountered recursively.
 
 - Warning: directories that cannot be entered due to permission problems
 are silently ignored. So keep that in mind.
 
 - Warning: Symbolic links that point to directories are *not* followed.
 
 - Note: setting recursively to `false` still causes the generator to feed
 you the directory; just not its contents.
 */
public func walk(
    _ path: AbsolutePath,
    fileSystem: FileSystem = localFileSystem,
    recursively: Bool = true
) throws -> RecursibleDirectoryContentsGenerator {
    return try RecursibleDirectoryContentsGenerator(
        path: path,
        fileSystem: fileSystem,
        recursionFilter: { _ in recursively })
}

/**
 - Returns: a generator that walks the specified directory producing all
 files therein. Directories are recursed based on the return value of
 `recursing`.
 
 - Warning: directories that cannot be entered due to permissions problems
 are silently ignored. So keep that in mind.
 
 - Warning: Symbolic links that point to directories are *not* followed.
 
 - Note: returning `false` from `recursing` still produces that directory
 from the generator; just not its contents.
 */
public func walk(
    _ path: AbsolutePath,
    fileSystem: FileSystem = localFileSystem,
    recursing: @escaping (AbsolutePath) -> Bool
) throws -> RecursibleDirectoryContentsGenerator {
    return try RecursibleDirectoryContentsGenerator(path: path, fileSystem: fileSystem, recursionFilter: recursing)
}

/**
 Produced by `walk`.
 */
public class RecursibleDirectoryContentsGenerator: IteratorProtocol, Sequence {
    private var current: (path: AbsolutePath, iterator: IndexingIterator<[String]>)
    private var towalk = [AbsolutePath]()

    private let shouldRecurse: (AbsolutePath) -> Bool
    private let fileSystem: FileSystem

    fileprivate init(
        path: AbsolutePath,
        fileSystem: FileSystem,
        recursionFilter: @escaping (AbsolutePath) -> Bool
    ) throws {
        self.fileSystem = fileSystem
        // FIXME: getDirectoryContents should have an iterator version.
        current = (path, try fileSystem.getDirectoryContents(path).makeIterator())
        shouldRecurse = recursionFilter
    }

    public func next() -> AbsolutePath? {
        outer: while true {
            guard let entry = current.iterator.next() else {
                while !towalk.isEmpty {
                    // FIXME: This looks inefficient.
                    let path = towalk.removeFirst()
                    guard shouldRecurse(path) else { continue }
                    // Ignore if we can't get content for this path.
                    guard let current = try? fileSystem.getDirectoryContents(path).makeIterator() else { continue }
                    self.current = (path, current)
                    continue outer
                }
                return nil
            }

            let path = current.path.appending(component: entry)
            if fileSystem.isDirectory(path) && !fileSystem.isSymlink(path) {
                towalk.append(path)
            }
            return path
        }
    }
}

extension AbsolutePath {
    /// Returns a path suitable for display to the user (if possible, it is made
    /// to be relative to the current working directory).
    public func prettyPath(cwd: AbsolutePath? = localFileSystem.currentWorkingDirectory) -> String {
        guard let dir = cwd else {
            // No current directory, display as is.
            return self.pathString
        }
        // FIXME: Instead of string prefix comparison we should add a proper API
        // to AbsolutePath to determine ancestry.
        if self == dir {
            return "."
        } else if self.pathString.hasPrefix(dir.pathString + "/") {
            return "./" + self.relative(to: dir).pathString
        } else {
            return self.pathString
        }
    }
}
