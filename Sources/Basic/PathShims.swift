/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import libc
import POSIX
import Foundation


/// This file contains temporary shim functions for use during the adoption of
/// AbsolutePath and RelativePath.  The eventual plan is to use the FileSystem
/// API for all of this, at which time this file will go way.  But since it is
/// important to have a quality FileSystem API, we will evolve it slowly.
///
/// Meanwhile this file bridges the gap to let call sites be as clean as pos-
/// sible, while making it fairly easy to find those calls later.

/// Returns a structure containing information about the file system entity at `path`, or nil
/// if that path doesn't exist in the file system.  Read, write or execute permission of the 
/// file system entity at `path` itself is not required, but all ancestor directories must be searchable.
/// If they are not, or if any other file system error occurs, this function throws a SystemError.
/// If `followSymlink` is true and the file system entity at `path` is a symbolic link, it is traversed;
/// otherwise it is not (any symbolic links in path components other than the last one are always traversed).
/// If symbolic links are followed and the file system entity at `path` is a symbolic link that points to a
/// non-existent path, then this function returns nil.
private func stat(_ path: AbsolutePath, followSymlink: Bool = true) throws -> libc.stat {
    if followSymlink {
        return try stat(path.asString)
    }
    return try lstat(path.asString)
}

/// Returns true if and only if `path` refers to an existent file system entity.
/// If `followSymlink` is true, and the last path component is a symbolic link, the result pertains
/// to the destination of the symlink; otherwise it pertains to the symlink itself.
/// If any file system error other than non-existence occurs, this function throws an error.
public func exists(_ path: AbsolutePath, followSymlink: Bool = true) -> Bool {
    return (try? stat(path, followSymlink: followSymlink)) != nil
}

/// Returns true if and only if `path` refers to an existent file system entity and that entity is a regular file.
/// If `followSymlink` is true, and the last path component is a symbolic link, the result pertains to the destination 
/// of the symlink; otherwise it pertains to the symlink itself. If any file system error other than non-existence occurs,
/// this function throws an error.
public func isFile(_ path: AbsolutePath, followSymlink: Bool = true) -> Bool {
    guard let status = try? stat(path, followSymlink: followSymlink), status.kind == .file else {
        return false
    }
    return true
}  

/// Returns true if and only if `path` refers to an existent file system entity and that entity is a directory.
/// If `followSymlink` is true, and the last path component is a symbolic link, the result pertains to the destination
/// of the symlink; otherwise it pertains to the symlink itself.  If any file system error other than non-existence occurs,
/// this function throws an error.
public func isDirectory(_ path: AbsolutePath, followSymlink: Bool = true) -> Bool {
    guard let status = try? stat(path, followSymlink: followSymlink), status.kind == .directory else {
        return false
    }
    return true
}

/// Returns true if and only if `path` refers to an existent file system entity and that entity is a symbolic link.
/// If any file system error other than non-existence occurs, this function throws an error.
public func isSymlink(_ path: AbsolutePath) -> Bool {
    guard let status = try? stat(path, followSymlink: false), status.kind == .symlink else {
        return false
    }
    return true
}

/// Returns the "real path" corresponding to `path` by resolving any symbolic links.
public func resolveSymlinks(_ path: AbsolutePath) -> AbsolutePath {
    let pathStr = path.asString
    guard let resolvedPathStr = try? POSIX.realpath(pathStr) else { return path }
    // FIXME: We should measure if it's really more efficient to compare the strings first.
    return (resolvedPathStr == pathStr) ? path : AbsolutePath(resolvedPathStr)
}

/// Creates a new, empty directory at `path`.  If needed, any non-existent ancestor paths are also created.  If there is already a directory at `path`, this function does nothing (in particular, this is not considered to be an error).
public func makeDirectories(_ path: AbsolutePath) throws {
  #if os(Linux)
    try FileManager.default().createDirectory(atPath: path.asString, withIntermediateDirectories: true, attributes: [:])
  #else
    try FileManager.default.createDirectory(atPath: path.asString, withIntermediateDirectories: true, attributes: [:])
  #endif
}

/// Recursively deletes the file system entity at `path`.  If there is no file system entity at `path`, this function does nothing (in particular, this is not considered to be an error).
public func removeFileTree(_ path: AbsolutePath) throws {
  #if os(Linux)
    try FileManager.default().removeItem(atPath: path.asString)
  #else
    try FileManager.default.removeItem(atPath: path.asString)
  #endif
}

/// Creates a symbolic link at `path` whose content points to `dest`.  If `relative` is true, the symlink contents will be a relative path, otherwise it will be absolute.
public func symlink(_ path: AbsolutePath, pointingAt dest: AbsolutePath, relative: Bool = true) throws {
    let destString = relative ? dest.relative(to: path.parentDirectory).asString : dest.asString
    let rv = libc.symlink(destString, path.asString)
    guard rv == 0 else { throw SystemError.symlink(errno, path.asString, dest: destString) }
}

public func rename(_ path: AbsolutePath, to dest: AbsolutePath) throws {
    let rv = libc.rename(path.asString, dest.asString)
    guard rv == 0 else { throw SystemError.rename(errno, old: path.asString, new: dest.asString) }
}

public func unlink(_ path: AbsolutePath) throws {
    let rv = libc.unlink(path.asString)
    guard rv == 0 else { throw SystemError.unlink(errno, path.asString) }
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
public func walk(_ path: AbsolutePath, fileSystem: FileSystem = localFileSystem, recursively: Bool = true) throws -> RecursibleDirectoryContentsGenerator {
    return try RecursibleDirectoryContentsGenerator(path: path, fileSystem: fileSystem, recursionFilter: { _ in recursively })
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
public func walk(_ path: AbsolutePath, fileSystem: FileSystem = localFileSystem, recursing: (AbsolutePath) -> Bool) throws -> RecursibleDirectoryContentsGenerator {
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
    
    private init(path: AbsolutePath, fileSystem: FileSystem, recursionFilter: (AbsolutePath) -> Bool) throws {
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
