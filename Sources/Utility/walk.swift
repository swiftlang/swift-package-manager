/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct libc.DirHandle
import struct libc.dirent
import func libc.readdir_r
import func libc.closedir
import func libc.opendir
import var libc.DT_DIR


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
public func walk(paths: String..., recursively: Bool = true) -> RecursibleDirectoryContentsGenerator {
    return RecursibleDirectoryContentsGenerator(path: Path.join(paths), recursionFilter: { _ in recursively })
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
public func walk(paths: String..., recursing: (String) -> Bool) -> RecursibleDirectoryContentsGenerator {
    return RecursibleDirectoryContentsGenerator(path: Path.join(paths), recursionFilter: recursing)
}

/**
 A generator for a single directory’s contents
*/
private class DirectoryContentsGenerator: IteratorProtocol {
    private let dirptr: DirHandle
    private let path: String

    private init(path: String) {
        let path = path.normpath
        dirptr = libc.opendir(path)
        self.path = path
    }

    deinit {
        if dirptr != nil { closedir(dirptr) }
    }

    func next() -> dirent? {
        if dirptr == nil { return nil }  // yuck, silently ignoring the error to maintain this pattern

        while true {
            var entry = dirent()
            var result: UnsafeMutablePointer<dirent> = nil
            guard readdir_r(dirptr, &entry, &result) == 0 else { continue }
            guard result != nil else { return nil }

            switch (Int32(entry.d_type), entry.d_name.0, entry.d_name.1, entry.d_name.2) {
            case (Int32(DT_DIR), 46, 0, _):   // "."
                continue
            case (Int32(DT_DIR), 46, 46, 0):  // ".."
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
    private var towalk = [String]()
    private let shouldRecurse: (String) -> Bool

    private init(path: String, recursionFilter: (String) -> Bool) {
        current = DirectoryContentsGenerator(path: path)
        shouldRecurse = recursionFilter
    }

    public func next() -> String? {
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
            var dirName = entry.d_name
            let name = withUnsafePointer(&dirName) { (ptr) -> String in
                return String(validatingUTF8: UnsafePointer<CChar>(ptr)) ?? ""
            }
            if Int32(entry.d_type) == Int32(DT_DIR) {
                towalk.append(Path.join(current.path, name))
            }
            return Path.join(current.path, name)
        }
    }
}
