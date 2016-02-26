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
    public static func join(components: String...) -> String {
        return Path.join(components)
    }

    /// - See: Path.join(components: String...)
    public static func join(components: [String]) -> String {
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

        func go(path: [String], _ pivot: [String]) -> String {
            let join = { [String].joined($0)(separator: "/") }

            if path.starts(with: pivot) {
                let relativePortion = path.dropFirst(pivot.count)
                return join(Array(relativePortion))
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
            do {
                if !abs.path { path = try path.abspath() }
                if !abs.pivot { pivot = try pivot.abspath() }
            } catch {
                return path.normpath
            }
        }
        
        return go(clean(string), clean(pivot))
    }

    public func join(components: String...) -> String {
        return Path.join([string] + components)
    }
}

private func clean(parts: [String.CharacterView]) -> [String] {
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

private func clean(string: String) -> [String] {
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

         Path.join(try getcwd(), self).normpath
     */
    public func abspath() throws -> String {
        return Path.join(try getcwd(), self).normpath
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
     - Note: if the entry is a symlink, but the symlink points to Array
       file, then this function returns true. Use `isSymlink` if the
       distinction is important.
     */
    public var isFile: Bool {
        var mystat = stat()
        let rv = stat(self, &mystat)
        return rv == 0 && (mystat.st_mode & S_IFMT) == S_IFREG
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

    /// - Returns: Ensures single path separators in a path string
    private var onesep: String {
        let abs = isAbsolute
        let cleaned = characters.split(separator: "/").map(String.init).joined(separator: "/")
        return abs ? "/\(cleaned)" : cleaned
    }
}
