/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import libc
import POSIX


/// This file contains temporary shim functions for use during the adoption of
/// AbsolutePath and RelativePath.  The eventual plan is to use the FileSystem
/// API for all of this, at which time this file will go way.  But since it is
/// important to have a quality FileSystem API, we will evolve it slowly.
///
/// Meanwhile this file bridges the gap to let call sites be as clean as pos-
/// sible, while making it fairly easy to find those calls later.
///
/// The basic pattern of all of these functions is to stay close to the POSIX
/// names, taking AbsolutePath parameters instead of strings for paths.  Paths
/// are usually the first parameters and do not have a `path` keyword.  Where
/// appropriate, optional parameters (with default values) are used in order
/// to make one function fill the role of multiple C functions.  For example,
/// instead of `mkdir` and `mkdirs`, there is a `recursive` parameter to the
/// `mkdir` function.

/// Extensions to the LibC `stat` structure to interpret the contents in more readable ways.
extension libc.stat {
    /// File system entity kind.
    enum Kind : mode_t {
        // FIXME: It would be great to make these constants equal to S_IFREG, S_IFDIR etc as raw value, but that yields an error since they are not considered constants by the Swift compiler.
        case file, directory, symlink, fifo, blockdev, chardev, socket, unknown
    }
    /// Kind of file system entity.
    var kind: Kind {
        switch (st_mode & S_IFMT) {
            case S_IFREG:  return .file
            case S_IFDIR:  return .directory
            case S_IFLNK:  return .symlink
            case S_IFBLK:  return .blockdev
            case S_IFCHR:  return .chardev
            case S_IFSOCK: return .socket
            default:       return .unknown
        }
    }
    /// True if the file system entity is a regular file.
    var isFile: Bool {
        return kind == .file
    }
    /// True if the file system entity is a directory.
    var isDirectory: Bool {
        return kind == .directory
    }
    /// True if the file system entity is a symbolic link.
    var isSymlink: Bool {
        return kind == .symlink
    }
}

/// Returns a structure containing information about the file system entity at `path`, or nil if that path doesn't exist in the file system.  Read, write or execute permission of the file system entity at `path` itself is not required, but all ancestor directories must be searchable.  If they are not, or if any other file system error occurs, this function throws a SystemError.  If `followSymlink` is true and the file system entity at `path` is a symbolic link, it is traversed;  otherwise it is not (any symbolic links in path components other than the last one are always traversed).  If symbolic links are followed and the file system entity at `path` is a symbolic link that points to a non-existent path, then this function returns nil.  By default, `followSymlink` is true.
public func stat(_ path: AbsolutePath, followSymlink: Bool = true) throws -> libc.stat? {
    var sbuf = libc.stat()
    let rv = followSymlink ? stat(path.asString, &sbuf) : lstat(path.asString, &sbuf)
    guard rv == 0 || errno == ENOENT else { throw SystemError.stat(errno, path.asString) }
    return rv == 0 ? sbuf : nil
}

/// Returns true if and only if `path` refers to an existent file system entity.  If `followSymlink` is true, and the last path component is a symbolic link, the result pertains to the destination of the symlink; otherwise it pertains to the symlink itself.  If any file system error other than non-existence occurs, this function throws an error.
public func exists(_ path: AbsolutePath, followSymlink: Bool = true) throws -> Bool {
    return try stat(path, followSymlink: followSymlink) != nil
}

/// Returns true if and only if `path` refers to an existent file system entity and that entity is a regular file.  If `followSymlink` is true, and the last path component is a symbolic link, the result pertains to the destination of the symlink; otherwise it pertains to the symlink itself.  If any file system error other than non-existence occurs, this function throws an error.
public func isFile(_ path: AbsolutePath, followSymlink: Bool = true) throws -> Bool {
    return try stat(path, followSymlink: followSymlink)?.isFile ?? false
}

/// Returns true if and only if `path` refers to an existent file system entity and that entity is a directory.  If `followSymlink` is true, and the last path component is a symbolic link, the result pertains to the destination of the symlink; otherwise it pertains to the symlink itself.  If any file system error other than non-existence occurs, this function throws an error.
public func isDirectory(_ path: AbsolutePath, followSymlink: Bool = true) throws -> Bool {
    return try stat(path, followSymlink: followSymlink)?.isDirectory ?? false
}

/// Returns true if and only if `path` refers to an existent file system entity and that entity is a symbolic link.  If any file system error other than non-existence occurs, this function throws an error.
public func isSymlink(_ path: AbsolutePath) throws -> Bool {
    return try stat(path, followSymlink: false)?.isSymlink ?? false
}

/// Returns the "real path" corresponding to `path` by resolving any symbolic links.
public func realpath(_ path: AbsolutePath) throws -> AbsolutePath {
    guard let rv = libc.realpath(path.asString, nil) else { throw SystemError.realpath(errno, path.asString) }
    defer { free(rv) }
    guard let rvv = String(validatingUTF8: rv) else { throw SystemError.realpath(-1, path.asString) }
    return AbsolutePath(rvv)
}

/// Creates a new, empty directory at `path`.  If there is already a file system entity at `path, a `EEXIST` error is thrown.  If `recursive` is true, any intermediate ancestor directories of `path` that don't exist are also created; if it is false, and the immediate parent directory of `path` doesn't exist, a `ENOENT` error is thrown.
public func mkdir(_ path: AbsolutePath, permissions mode: mode_t = S_IRWXU|S_IRWXG|S_IRWXO, recursive: Bool = true) throws {
    var rv = libc.mkdir(path.asString, mode)
    if rv < 0 && errno == ENOENT && recursive {
        assert(!path.isRoot)
        try mkdir(path.parentDirectory, permissions: mode, recursive: true)
        rv = libc.mkdir(path.asString, mode)
    }
    guard (rv == 0 || errno == EEXIST) else { throw SystemError.mkdir(errno, path.asString) }
}

/// Creates a symbolic link at `path` whose content points to `dest`.  If `relative` is true, the symlink contents will be a relative path (by making `dest` relative to `path`, using as many `..` path components as needed); otherwise the symlink path will be absolute.
public func symlink(_ path: AbsolutePath, pointingAt dest: AbsolutePath, relative: Bool = true) throws {
    let dstr = relative ? dest.relative(to: path.parentDirectory).asString : dest.asString
    let rv = libc.symlink(dstr, path.asString)
    guard rv == 0 else { throw SystemError.symlink(errno, path.asString, dest: dstr) }
}

/// Moves the file system entity at `path` to the new path `dest`.  If there is already a file system entity at `dest`, it is first removed.  Both `path` and `dest` must reside on the same file system.
public func move(_ path: AbsolutePath, to dest: AbsolutePath) throws {
    let rv = libc.rename(path.asString, dest.asString)
    guard rv == 0 else { throw SystemError.rename(errno, old: path.asString, new: dest.asString) }
}

/// Removes the file system entity at `path`.  If that was the last reference to the underlying file system object, and no process has the file open, then all resources associated with the file system object are reclaimed.  If `path` is a directory and `recursive` is not true, an `ENOTEMPTY` error is thrown if the directory isn't empty.  If `recursive` is true, the directory contents are recursively removed before the directory itself is removed.  This function doesn't throw an error if `path` doesn't exist.
public func remove(_ path: AbsolutePath, recursive: Bool = true) throws {
    // First try removing it as a directory (but treat non-existence as success).
    if libc.rmdir(path.asString) == 0 || errno == ENOENT {
        return
    }
    // Couldn't remove as a directory; see if the reason was that it wasn't empty.
    else if errno == ENOTEMPTY {
        // Not empty, so if we've been asked to remove recursively, we remove directory contents and try again.
        if (recursive) {
            // Open the directory and remove the contents.
            guard let dir = libc.opendir(path.asString) else {
                throw SystemError.opendir(errno, path.asString)
            }
            defer { _ = libc.closedir(dir) }
            var entry = dirent()
            while true {
                // Read the next directory entry.
                var entryPtr: UnsafeMutablePointer<dirent>? = nil
                if readdir_r(dir, &entry, &entryPtr) < 0 {
                    // FIXME: Are there ever situation where we would want to continue here?
                    throw SystemError.readdir(errno, path.asString)
                }
                
                // If the entry pointer is null, we reached the end of the directory.
                if entryPtr == nil {
                    break
                }
                
                // Otherwise, the entry pointer should point at the storage we provided.
                assert(entryPtr == &entry)
                
                // Decode the directory entry name.
                guard let entryName = entry.name else {
                    throw SystemError.readdir(errno, path.asString)
                }
                
                // Ignore the pseudo-entries.
                if entryName == "." || entryName == ".." {
                    continue
                }
                
                // Remove the entry recursively.
                try remove(path.appending(component: entryName), recursive: true)
            }
            
            // At this point the directory should be empty, so we remove it.
            if libc.rmdir(path.asString) != 0 {
                // Still couldn't remove it, so time to throw an error.
                throw SystemError.rmdir(errno, path.asString)
            }
        }
        else {
            // Unable to remove, and not removing recursively, so throw an error.
            throw SystemError.rmdir(errno, path.asString)
        }
    }
    // Couldn't remove as a directory; if reason is anything except not-a-directory, throw error.
    else if errno != ENOTDIR {
        throw SystemError.rmdir(errno, path.asString)
    }
    // We get here if the path wasn't a directory; if so, we just try unlinking.
    // FIXME:  It would be more efficient to do this first, before trying the rmdir(), since most entries aren't directories.
    else if libc.unlink(path.asString) != 0 {
        throw SystemError.unlink(errno, path.asString)
    }
}
