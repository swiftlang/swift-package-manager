/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import libc
import POSIX


/// Path separator character (always `/`).  If a path separator occurs at the
/// beginning of a path, the path is considered to be absolute.
public let PathSeparatorCharacter: Character = "/"

/// User directory replacement character (always `~`).  When it occurs at the
/// beginning of the first component of a path (optionally followed by a user
/// name), that first path component is replaced by the absolute path of the
/// home directory of the user.
public let HomeDirectoryCharacter: Character = "~"


/// Represents an absolute file system path, independently of what (or whether
/// anything at all) exists at that path in the file system at any given time.
/// An absolute path always starts with a `/` character, and holds a normalized
/// string representation.  This normalization is strictly syntactic, and does
/// not access the file system in any way.
public struct AbsolutePath {
    /// Private implementation details, shared with the RelativePath struct.
    private let _impl: PathImpl
    
    /// Initializes the AbsolutePath from `string`, which must be an absolute
    /// path (which means that it must begin with either a path separator or a
    /// tilde, denoting an absolute path of a user account home directory).
    ///
    /// The path string will be normalized by:
    /// - Collapsing `..` path components
    /// - Removing `.` path components
    /// - Expanding `~` or `~user` prefix
    /// - Removing any trailing path separator
    /// - Removing any redundant path separators
    ///
    /// This string manipulation may change the meaning of a path if any of the
    /// path components are symbolic links on disk.  However, the file system is
    /// never accessed in any way when initializing an AbsolutePath.
    public init(_ string: String) {
        precondition(string.characters.first == PathSeparatorCharacter
                  || string.characters.first == HomeDirectoryCharacter)
        
        // Get a hold of the character view.
        // FIXME: We need to investigate what is most performant here.
        //        For example, is UTF-8 view more efficient, or unichars, etc?
        var chars = string.characters
        
        // Expand any `~` or `~user` prefix.
        if chars.first == HomeDirectoryCharacter {
            // We're doing home directory substitution. Check for a user name.
            let nStart = chars.index(after: chars.startIndex)
            let nEnd = chars.index(of: PathSeparatorCharacter) ?? chars.endIndex
            if nStart == nEnd {
                // No user name, so we need home directory of effective user.
                let homeDir = gethomedir().characters
                chars.replaceSubrange(chars.startIndex ..< nEnd, with: homeDir)
            }
            else {
                // A user name was provided, so we try to look that up.
                // FIXME:  What do we do if we cannot find the user name? Most
                //         shells leave it as a relative path, which we do not
                //         want to do since we want the type safety of knowing
                //         up-front whether a path is absolute or relative.
                let name = String(chars[nStart ..< nEnd])
                let homeDir = gethomedir(user: name).characters
                chars.replaceSubrange(chars.startIndex ..< nEnd, with: homeDir)
            }
        }
        
        // At this point we expect to have a path separator as first character.
        assert(chars.first == PathSeparatorCharacter)

        // Split the character array into parts, folding components as we go.
        // As we do so, we count the number of characters we'll end up with in
        // the normalized string representation.
        var parts: [String.CharacterView] = []
        var capacity = 0
        for part in chars.split(separator: PathSeparatorCharacter) {
            switch part.count {
              case 0:
                // Ignore empty path components.
                continue
              case 1 where part.first == ".":
                // Ignore `.` path components.
                continue
              case 2 where part.first == "." && part.last == ".":
                // If there's a previous part, drop it; otherwise, do nothing.
                if let prev = parts.last {
                    parts.removeLast()
                    capacity -= prev.count
                }
              default:
                // Any other component gets appended.
                parts.append(part)
                capacity += part.count
            }
        }
        capacity += max(parts.count, 1)
        
        // Create an output buffer using the capacity we've calculated.
        // FIXME: Determine whether this is the most efficient way to do it.
        var result = ""
        result.reserveCapacity(capacity)
        
        // Put the normalized parts back together again.
        var iter = parts.makeIterator()
        result.append(PathSeparatorCharacter)
        if let first = iter.next() {
            result.append(contentsOf: first)
            while let next = iter.next() {
                result.append(PathSeparatorCharacter)
                result.append(contentsOf: next)
            }
        }
        
        // Sanity-check the result (including the capacity we reserved).
        assert(!result.isEmpty, "unexpected empty string")
        assert(result.characters.count == capacity, "count: " +
            "\(result.characters.count), cap: \(capacity)")
        
        // Use the result as our stored string.
        _impl = PathImpl(string: String(result))
    }
    
    /// Directory component.  An absolute path always has a non-empty directory
    /// component (the directory component of the root path is the root itself).
    public var dirname: String {
        return _impl.dirname!
    }
    
    /// Last path component (including the suffix, if any).  it is never empty.
    public var basename: String {
        return _impl.basename
    }
    
    /// Suffix (including leading `.` character) if any.  Note that a basename
    /// that starts with a `.` character is not considered a suffix.
    public var suffix: String? {
        return _impl.suffix
    }
    
    /// Absolute path of parent directory.  This always returns a path, because
    /// every directory has a parent (the parent directory of the root directory
    /// is considered to be the root directory itself).
    public var parentDirectory: AbsolutePath {
        return isRoot ? self : AbsolutePath(_impl.dirname!)
    }
    
    /// True if the path is the root directory.
    public var isRoot: Bool {
        let chars = _impl.string.characters
        return chars.count == 1 && chars.first == PathSeparatorCharacter
    }
    
    /// Returns the absolute path with the relative path applied.
    public func join(_ subpath: RelativePath) -> AbsolutePath {
        let slash = String(PathSeparatorCharacter)
        return AbsolutePath(asString + slash + subpath.asString)
    }
    
    /// NOTE: We will want to add other methods here, such as a join() method
    ///       that takes an arbitrary number of parameters, etc.  Most likely
    ///       we will also make the `+` operator mean `join()`.
    
    /// Root directory (whose string representation is just a path separator).
    public static var root: AbsolutePath {
        // FIXME: If this is called a lot, we should maybe cache the root path.
        return AbsolutePath(String(PathSeparatorCharacter))
    }
    
    /// Home directory of the effective user.
    public static var home: AbsolutePath {
        // FIXME: We need a real implementation here.
        return AbsolutePath(gethomedir())
    }
    
    /// Normalized string representation (the normalization rules are described
    /// in the documentation of the initializer).  This string is never empty.
    public var asString: String {
        return _impl.string
    }
}


/// Represents a relative file system path.  A relative path is a string that
/// doesn't start with a `/` or a `~` character, and holds a normalized string
/// representation.  As with AbsolutePath, the normalization is strictly syn-
/// tactic, and does not access the file system in any way.
public struct RelativePath {
    /// Private implementation details, shared with the AbsolutePath struct.
    private let _impl: PathImpl
    
    /// Initializes the RelativePath from `str`, which must be a relative path
    /// (which means that it must not begin with a path separator or a tilde).
    /// An empty input path is allowed, but will be normalized to a single `.`
    /// character.
    ///
    /// The path string will be normalized by:
    /// - Collapsing `..` path components that aren't at the beginning
    /// - Removing extraneous `.` path components
    /// - Removing any trailing path separator
    /// - Removing any redundant path separators
    /// - Replacing a completely empty path with a `.`
    ///
    /// This string manipulation may change the meaning of a path if any of the
    /// path components are symbolic links on disk.  However, the file system is
    /// never accessed in any way when initializing an AbsolutePath.
    public init(_ string: String) {
        precondition(string.characters.first != PathSeparatorCharacter
                  && string.characters.first != HomeDirectoryCharacter)
        // Get a hold of the character view.
        // FIXME: We need to investigate what is most performant here.
        //        For example, is UTF-8 view more efficient, or unichars, etc?
        let chars = string.characters
        
        // Split the character array into parts, folding components as we go.
        // As we do so, we count the number of characters we'll end up with in
        // the normalized string representation.
        var parts: [String.CharacterView] = []
        var capacity = 0
        for part in chars.split(separator: PathSeparatorCharacter) {
            switch part.count {
              case 0:
                // Ignore empty path components.
                continue
              case 1 where part.first == ".":
                // Ignore `.` path components.
                continue
              case 2 where part.first == "." && part.last == ".":
                // If at beginning, fall through to treat the `..` literally.
                guard let prev = parts.last else {
                    fallthrough
                }
                // If previous component is anything other than `..`, drop it.
                if !(prev.count == 2 && prev.first == "." && prev.last == ".") {
                    parts.removeLast()
                    capacity -= prev.count
                    continue
                }
                // Otherwise, fall through to treat the `..` literally.
                fallthrough
              default:
                // Any other component gets appended.
                parts.append(part)
                capacity += part.count
            }
        }
        capacity += max(parts.count - 1, 0)
        
        // Create an output buffer using the capacity we've calculated.
        // FIXME: Determine whether this is the most efficient way to do it.
        var result = ""
        result.reserveCapacity(capacity)
        
        // Put the normalized parts back together again.
        var iter = parts.makeIterator()
        if let first = iter.next() {
            result.append(contentsOf: first)
            while let next = iter.next() {
                result.append(PathSeparatorCharacter)
                result.append(contentsOf: next)
            }
        }
        
        // Sanity-check the result (including the capacity we reserved).
        assert(result.characters.count == capacity, "count: " +
            "\(result.characters.count), cap: \(capacity)")

        // Use the result (or `.` if it's empty) as our stored string.
        _impl = PathImpl(string: result.isEmpty ? "." : String(result))
    }
    
    /// Directory component.  For a relative path, this may be empty.
    public var dirname: String? {
        return _impl.dirname
    }
    
    /// Last path component (including the suffix, if any).  it is never empty.
    public var basename: String {
        return _impl.basename
    }
    
    /// Suffix (including leading `.` character) if any.  Note that a basename
    /// that starts with a `.` character is not considered a suffix.
    public var suffix: String? {
        return _impl.suffix
    }
    
    /// Normalized string representation (the normalization rules are described
    /// in the documentation of the initializer).  This string is never empty.
    public var asString: String {
        return _impl.string
    }
}


// Make absolute paths Hashable.
extension AbsolutePath : Hashable {
    public var hashValue: Int {
        return self.asString.hashValue
    }
}

// Make absolute paths Equatable.
extension AbsolutePath : Equatable { }
public func ==(lhs: AbsolutePath, rhs: AbsolutePath) -> Bool {
    return lhs.asString == rhs.asString
}


// Make relative paths Hashable.
extension RelativePath : Hashable {
    public var hashValue: Int {
        return self.asString.hashValue
    }
}

// Make relative paths Equatable.
extension RelativePath : Equatable { }
public func ==(lhs: RelativePath, rhs: RelativePath) -> Bool {
    return lhs.asString == rhs.asString
}


/// Private implementation shared between AbsolutePath and RelativePath.  It is
/// a little unfortunate that there needs to be duplication at all between the
/// AbsolutePath and RelativePath struct, but PathImpl helps mitigate it.  From
/// a type safety perspective, absolute paths and relative paths are genuinely
/// different.
private struct PathImpl {
    /// Normalized string of the (absolute or relative) path.  Never empty.
    private let string: String
    
    /// Private function that returns the directory part of the stored path
    /// string (relying on the fact that it has been normalized).  Returns nil
    /// if there is no directory part (which is the case iff there is no path
    /// separator).
    private var dirname: String? {
        let chars = string.characters
        guard let idx = chars.rindex(of: PathSeparatorCharacter) else {
            return nil
        }
        return idx == chars.startIndex ? String(chars[idx])
            : String(chars.prefix(upTo: idx))
    }
    
    private var basename: String {
        // FIXME: This needs to be rewritten.
        guard !string.isEmpty else { return "." }
        let parts = string.characters.split(separator: PathSeparatorCharacter)
        guard !parts.isEmpty else { return "/" }
        return String(parts.last!)
    }
    
    private var suffix: String? {
        // FIXME: This needs to be rewritten.
        let chars = string.characters
        guard chars.contains(".") else { return nil }
        let parts = chars.split(separator: ".")
        if let last = parts.last where parts.count > 1 { return String(last) }
        return nil
    }
}


/// Private functions for use by the path logic.  These should move out into a
/// public place, but we'll need to debate the names, etc, etc.
private extension String.CharacterView {
    
    /// Returns the index of the last occurrence of `char`, or nil if none.
    private func rindex(of char: Character) -> Index? {
        var idx = endIndex
        while idx > startIndex {
            idx = index(before: idx)
            if self[idx] == char {
                return idx
            }
        }
        return nil
    }
}


/// Private function that returns a string containing the home directory of the
/// effective user.  This should definitely move out into a public place, but
/// we'll need to debate the names, etc, etc.
/// FIXME:  Should this function return an optional or throw an error if there
/// is a problem with the current user id?
private func gethomedir() -> String {
    /// First respect the `HOME` environment variable, if it's set.
    if let path = POSIX.getenv("HOME") {
        return path
    }
    // Otherwise check effective user id, falling back on actual user id.
    var uid = geteuid()
    if uid == 0 { uid = getuid() }
    // Look up the user in the account database.
    let pwd = getpwuid(uid)
    if let cdir = pwd?.pointee.pw_dir {
        // We found the user, so construct a string from the pw_dir.
        if let dir = String(validatingUTF8: cdir) {
            return dir
        }
        // FIXME: How should we recover from bad UTF-8 in the home directory?
        //        Should we just throw an error and punt the problem upwards?
    }
    // FIXME: What should we return if all else fails?
    return "/tmp/~"
}


/// Private function that returns a string containing the home directory of the
/// name user.  This should definitely move out into a public place, but we'll
/// need to debate the names, etc, etc.
/// FIXME:  Should this function return an optional or throw an error if there
/// is no user with the given name?
private func gethomedir(user: String) -> String {
    // Look up the user in the account database.
    let pwd = getpwnam(user)
    if let cdir = pwd?.pointee.pw_dir {
        // We found the user, so construct a string from the pw_dir.
        if let dir = String(validatingUTF8: cdir) {
            return dir
        }
        // FIXME: How should we recover from bad UTF-8 in the home directory?
        //        Should we just throw an error and punt the problem upwards?
    }
    // FIXME: What should we return if all else fails?
    return "/tmp/~\(user)"
}


/// Convenience properties that access the file system, making it convenient to
/// get information about a file system entity at a particular path.  Note that
/// none of these functions is allowed to mutate the file system.
extension AbsolutePath {
    // FIXME: Factor out a method to return the stat record, and then move the
    //        other methods to the stat record.  That makes it easier to avoid
    //        blithely stat:ing over and over again if multple properties are
    //        checked (e.g. `isFile || isSymlink` etc).
    
    public var isDirectory: Bool {
        var mystat = stat()
        let rv = lstat(self.asString, &mystat)
        return rv == 0 && (mystat.st_mode & S_IFMT) == S_IFDIR
    }
    
    public var isFile: Bool {
        var mystat = stat()
        let rv = lstat(self.asString, &mystat)
        return rv == 0 && (mystat.st_mode & S_IFMT) == S_IFREG
    }
        
    public var isSymlink: Bool {
        var mystat = stat()
        let rv = lstat(self.asString, &mystat)
        return rv == 0 && (mystat.st_mode & S_IFMT) == S_IFLNK
    }
    
    public var exists: Bool {
        return access(self.asString, F_OK) == 0
    }
}
