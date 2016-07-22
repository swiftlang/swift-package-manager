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

public func isDirectory(_ path: AbsolutePath) -> Bool {
    // Copied from Utilities.Path.
    var mystat = stat()
    let rv = stat(path.asString, &mystat)
    return rv == 0 && (mystat.st_mode & S_IFMT) == S_IFDIR
}

public func isFile(_ path: AbsolutePath) -> Bool {
    // Copied from Utilities.Path.
    var mystat = stat()
    let rv = stat(path.asString, &mystat)
    return rv == 0 && (mystat.st_mode & S_IFMT) == S_IFREG
}

public func isSymlink(_ path: AbsolutePath) -> Bool {
    // Copied from Utilities.Path.
    var mystat = stat()
    let rv = lstat(path.asString, &mystat)
    return rv == 0 && (mystat.st_mode & S_IFMT) == S_IFLNK
}

public func exists(_ path: AbsolutePath) -> Bool {
    // Copied from Utilities.Path.
    return access(path.asString, F_OK) == 0
}

/// Returns the "real path" corresponding to `path` by resolving any symbolic links.
public func resolveSymlinks(_ path: AbsolutePath) -> AbsolutePath {
    let pathStr = path.asString
  #if os(Linux)
    // FIXME: This is really unfortunate but seems to be the only way to invoke this functionality on Linux.
    let url = URL(fileURLWithPath: pathStr)
    guard let resolvedPathStr = (try? url.resolvingSymlinksInPath())?.path else { return path }
  #else
    // FIXME: It's unfortunate to have to cast to NSString here but apparently the String method is deprecated.
    let resolvedPathStr = (pathStr as NSString).resolvingSymlinksInPath
  #endif
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
 
 - Warning: If path doesn’t exist or cannot be entered this generator will
 be empty. It is up to you to check `path` is valid before using this
 function.
 
 - Warning: Symbolic links that point to directories are *not* followed.
 
 - Note: setting recursively to `false` still causes the generator to feed
 you the directory; just not its contents.
 */
public func walk(_ path: AbsolutePath, recursively: Bool = true) -> RecursibleDirectoryContentsGenerator {
    return RecursibleDirectoryContentsGenerator(path: path, recursionFilter: { _ in recursively })
}

/**
 - Returns: a generator that walks the specified directory producing all
 files therein. Directories are recursed based on the return value of
 `recursing`.
 
 - Warning: directories that cannot be entered due to permissions problems
 are silently ignored. So keep that in mind.
 
 - Warning: If path doesn’t exist or cannot be entered this generator will
 be empty. It is up to you to check `path` is valid before using this
 function.
 
 - Warning: Symbolic links that point to directories are *not* followed.
 
 - Note: returning `false` from `recursing` still produces that directory
 from the generator; just not its contents.
 */
public func walk(_ path: AbsolutePath, recursing: (AbsolutePath) -> Bool) -> RecursibleDirectoryContentsGenerator {
    return RecursibleDirectoryContentsGenerator(path: path, recursionFilter: recursing)
}

/**
 A generator for a single directory’s contents
 */
private class DirectoryContentsGenerator: IteratorProtocol {
    private let dirptr: DirHandle?
    fileprivate let path: AbsolutePath
    
    fileprivate init(path: AbsolutePath) {
        dirptr = libc.opendir(path.asString)
        self.path = path
    }
    
    deinit {
        if let openeddir = dirptr { closedir(openeddir) }
    }
    
    func next() -> dirent? {
        guard let validdir = dirptr else { return nil }  // yuck, silently ignoring the error to maintain this pattern
        
        while true {
            var entry = dirent()
            var result: UnsafeMutablePointer<dirent>? = nil
            guard readdir_r(validdir, &entry, &result) == 0 else { continue }
            guard result != nil else { return nil }
            
            switch (entry.d_name.0, entry.d_name.1, entry.d_name.2) {
            case (46, 0, _):   // "."
                continue
            case (46, 46, 0):  // ".."
                continue
            default:
                return entry
            }
        }
    }
}

/**
 Produced by `walk`.
 */
public class RecursibleDirectoryContentsGenerator: IteratorProtocol, Sequence {
    private var current: DirectoryContentsGenerator
    private var towalk = [AbsolutePath]()
    private let shouldRecurse: (AbsolutePath) -> Bool
    
    private init(path: AbsolutePath, recursionFilter: (AbsolutePath) -> Bool) {
        current = DirectoryContentsGenerator(path: path)
        shouldRecurse = recursionFilter
    }
    
    public func next() -> AbsolutePath? {
        outer: while true {
            guard let entry = current.next() else {
                while !towalk.isEmpty {
                    let path = towalk.removeFirst()
                    guard shouldRecurse(path) else { continue }
                    current = DirectoryContentsGenerator(path: path)
                    continue outer
                }
                return nil
            }
            let name = entry.name ?? ""
            let path = current.path.appending(component: name)
            if isDirectory(path) && !isSymlink(path) {
                towalk.append(path)
            }
            return current.path.appending(component: name)
        }
    }
}
