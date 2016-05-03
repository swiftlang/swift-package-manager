/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import libc
import POSIX

public struct Path {
    /**
     Join one or more path components intelligently. The return value is the
     concatenation of path and any members of components with exactly one
     directory separator following each non-empty part except the last,
     meaning that the result will only end in a separator if the last part is
     empty. If a component is an absolute path, all previous components are
     thrown away and joining continues from the absolute path component.
     
     - Note: This function considers / to always be the path separator. If in
       future we support platforms that have a different separator we will
       convert any "/" characters in your strings to the platform separator.
    */
    public static func join(_ components: String...) -> String {
        return Path.join(components)
    }

    /// - See: Path.join(components: String...)
    public static func join(_ components: [String]) -> String {
        return components.reduce("") { memo, component in
            let component = component.onesep
            if component.isEmpty {
                return memo
            } else if component.isAbsolute || memo.isEmpty {
                return component
            } else if memo == "/" {
                return memo + component
            } else {
                return memo + "/" + component
            }
        }
    }

    public static var home: String {
        return getenv("HOME")!
    }

//////MARK: instance members

    public let string: String

    public init(components: String...) {
        string = Path.join(components)
    }

    public init(_ component: String) {
        string = component
    }
    /**
     Returns a string that represents the input relative to another
     path.

     The input paths are normalized before being compared. Thus the
     
     resulting path will be normalized.
     Either both paths must be absolute or both must be relative, if
     either differ we absolute both before comparison, so you may or
     may not get back an absolute path.

     If after normalization the input is not relative to the
     provided root we return the cleaned input.

     If either path is not absolute we assume the prefix is the
     current working directory.
    */
    public func relative(to pivot: String) -> String {

        let abs = (path: string.isAbsolute, pivot: pivot.isAbsolute)

        func go(_ path: [String], _ pivot: [String]) -> String {
            let join = { [String].joined($0)(separator: "/") }

            if path.starts(with: pivot) {
                let relativePortion = path.dropFirst(pivot.count)
                return join(Array(relativePortion))
            } else if path.starts(with: pivot.prefix(1)) {
                //only the first matches, so we will be able to find a relative
                //path by adding jumps back the directory tree
                var newPath = ArraySlice(path)
                var newPivot = ArraySlice(pivot)
                repeat {
                    //remove all shared components in the prefix
                    newPath = newPath.dropFirst()
                    newPivot = newPivot.dropFirst()
                } while newPath.prefix(1) == newPivot.prefix(1)
                
                //as we found the first differing point, the final path is
                //a) as many ".." as there are components in newPivot
                //b) what's left in newPath
                var final = Array(repeating: "..", count: newPivot.count)
                final.append(contentsOf: newPath)
                let relativePath = Path.join(final)
                return relativePath
            } else {
                let prefix = abs.path ? "/" : ""
                return prefix + join(path)
            }
        }

        var path = string
        var pivot = pivot

        // The above function requires both paths to be either relative
        // or absolute. So if they differ we make them both absolute.
        if abs.0 != abs.1 {
            if !abs.path { path = path.abspath }
            if !abs.pivot { pivot = pivot.abspath }
        }
        
        return go(clean(string), clean(pivot))
    }

    public func join(_ components: String...) -> String {
        return Path.join([string] + components)
    }
}

private func clean(_ parts: [String.CharacterView]) -> [String] {
    var out = [String]()
    for x in parts.map(String.init) {
        switch x {
        case ".":
            continue
        case "..":
            if !out.isEmpty {
                out.removeLast()
            } else {
                out.append(x)
            }
        default:
            out.append(x)
        }
    }
    return out
}

private func clean(_ string: String) -> [String] {
    return clean(string.characters.split(separator: "/"))
}

extension String {
    /**
     Normalizes the path by:
     - Collapsing ..
     - Removing .
     - Expanding ~
     - Expanding ~foo
     - Removing any trailing slash
     - Removing any redundant slashes

     This string manipulation may change the meaning of a path that
     contains symbolic links. The filesystem is not accessed.
    */
    public var normpath: String {
        guard !isEmpty else {
            return "."
        }

        let chars = characters
        var parts = chars.split(separator: "/")
        let firstc = chars.first!

        if firstc == "~" {
            var replacement = Path.home.characters.split(separator: "/")
            if parts[0].count > 1 {
                // FIXME not technically correct, but works 99% of the time!
                replacement.append("..".characters)
                replacement.append(parts[0].dropFirst())
            }
            parts.replaceSubrange(0...0, with: replacement)
        }

        let stringValue = clean(parts).joined(separator: "/")

        if firstc == "/" || firstc == "~" {
            return "/\(stringValue)"
        } else if stringValue.isEmpty {
            return "."
        } else {
            return stringValue
        }
    }

    /**
     Return a normalized absolutized version of this path. Equivalent to:

         Path.join(getcwd(), self).normpath
     */
    public var abspath: String {
        return Path.join(getcwd(), self).normpath
    }

    /// - Returns: true if the string looks like an absolute path
    public var isAbsolute: Bool {
        return hasPrefix("/")
    }

    /**
     - Returns: true if the string is a directory on the filesystem
     - Note: if the entry is a symlink, but the symlink points to a
       directory, then this function returns true. Use `isSymlink`
       if the distinction is important.
    */
    public var isDirectory: Bool {
        var mystat = stat()
        let rv = stat(self, &mystat)
        return rv == 0 && (mystat.st_mode & S_IFMT) == S_IFDIR
    }

    /**
     - Returns: true if the string is a file on the filesystem
     - Note: if the entry is a symlink, but the symlink points to a
       file, then this function returns true. Use `isSymlink` if the
       distinction is important.
     */
    public var isFile: Bool {
        var mystat = stat()
        let rv = stat(self, &mystat)
        return rv == 0 && (mystat.st_mode & S_IFMT) == S_IFREG
    }
    
    /**
     - Returns: the file extension for a file otherwise nil
     */
    public var fileExt: String? {
        guard isFile else { return nil }
        guard characters.contains(".") else { return nil }
        let parts = characters.split(separator: ".")
        if let last = parts.last where parts.count > 1 { return String(last) }
        return nil
    }

    /**
     - Returns: true if the string is a symlink on the filesystem
     */
    public var isSymlink: Bool {
        var mystat = stat()
        let rv = lstat(self, &mystat)
        return rv == 0 && (mystat.st_mode & S_IFMT) == S_IFLNK
    }

    /**
     - Returns: true if the string is an entry on the filesystem
     - Note: symlinks are resolved
     */
    public var exists: Bool {
        return access(self, F_OK) == 0
    }

    /**
     - Returns: The last path component from `path`, deleting any trailing `/'
       characters. If path consists entirely of `/' characters, "/" is
       returned. If path is an empty string, "." is returned.
    */
    public var basename: String {
        guard !isEmpty else { return "." }
        let parts = characters.split(separator: "/")
        guard !parts.isEmpty else { return "/" }
        return String(parts.last!)
    }

    public var parentDirectory: String {
        guard !isEmpty else { return self }
        return Path.join(self, "..").normpath
    }

    /// - Returns: Ensures single path separators in a path string, and removes trailing slashes.
    private var onesep: String {
        // Fast path, for already clean strings.
        //
        // It would be more efficient to avoid scrubbing every string that
        // passes through join(), but this retains the pre-existing semantics.
        func isClean(_ str: String) -> Bool {
            // Check if the string contains any occurrence of "//" or ends with "/".
            let utf8 = str.utf8
            var idx = utf8.startIndex
            let end = utf8.endIndex
            while idx != end {
                if utf8[idx] == UInt8(ascii: "/") {
                    utf8.formIndex(after: &idx)
                    if idx == end || utf8[idx] == UInt8(ascii: "/") {
                        return false
                    }
                }
                utf8.formIndex(after: &idx)
            }
            return true
        }
        if isClean(self) {
            return self
        }
        
        let abs = isAbsolute
        let cleaned = characters.split(separator: "/").map(String.init).joined(separator: "/")
        return abs ? "/\(cleaned)" : cleaned
    }

    /**
      - Returns: A path suitable for display to the user, if possible,
        a path relative to the current working directory.
      - Note: As such this function relies on the working directory
        not changing during execution.
     */
    public var prettyPath: String {
        let userDirectory = POSIX.getiwd()

        if self.parentDirectory == userDirectory {
            return "./\(basename)"
        } else if hasPrefix(userDirectory) {
            return Path(self).relative(to: userDirectory)
        } else {
            return self
        }
    }
}
