/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/


/// Path separator character (always `/`).  If a path separator occurs at the
/// beginning of a path, the path is considered to be absolute.
/// FIXME: We can probably get rid of this, since a) this is not likely to be
/// something we can ever change, and b) the other characters that have special
/// meaning (such as `.`) do not have similar constants.
public let pathSeparatorCharacter: Character = "/"


/// Represents an absolute file system path, independently of what (or whether
/// anything at all) exists at that path in the file system at any given time.
/// An absolute path always starts with a `/` character, and holds a normalized
/// string representation.  This normalization is strictly syntactic, and does
/// not access the file system in any way.
///
/// The absolute path string is normalized by:
/// - Collapsing `..` path components
/// - Removing `.` path components
/// - Removing any trailing path separator
/// - Removing any redundant path separators
///
/// This string manipulation may change the meaning of a path if any of the
/// path components are symbolic links on disk.  However, the file system is
/// never accessed in any way when initializing an AbsolutePath.
///
/// FIXME: We will also need to add support for `~` resolution.
public struct AbsolutePath {
    /// Private implementation details, shared with the RelativePath struct.
    private let _impl: PathImpl
    
    /// Initializes the AbsolutePath from `string`, which must be an absolute
    /// path (i.e. it must begin with a path separator; this initializer does
    /// not interpret leading `~` characters as home directory specifiers).
    /// The input string will be normalized if needed, as described in the
    /// documentation for AbsolutePath.
    public init(_ string: String) {
        // Normalize the absolute string and store it as our PathImpl.
        _impl = PathImpl(string: normalize(absolute: string))
    }
    
    /// Initializes the AbsolutePath from an AbsolutePath and a RelativePath.
    public init(_ absPath: AbsolutePath, _ relPath: RelativePath) {
        // Both paths are already normalized, so we just construct a new path.
        let absStr = absPath._impl.string
        let relStr = relPath._impl.string
        _impl = PathImpl(string: relStr == "." ? absStr :
            absStr + String(pathSeparatorCharacter) + relStr)
    }
    
    /// NOTE: We will want to add other initializers, such as ones that take
    ///       an arbtirary number of relative paths.
    
    /// Directory component.  An absolute path always has a non-empty directory
    /// component (the directory component of the root path is the root itself).
    public var dirname: String {
        return _impl.dirname
    }
    
    /// Last path component (including the suffix, if any).  it is never empty.
    public var basename: String {
        return _impl.basename
    }
    
    /// Suffix (including leading `.` character) if any.  Note that a basename
    /// that starts with a `.` character is not considered a suffix, nor is a
    /// trailing `.` character.
    public var suffix: String? {
        return _impl.suffix
    }
    
    /// Absolute path of parent directory.  This always returns a path, because
    /// every directory has a parent (the parent directory of the root directory
    /// is considered to be the root directory itself).
    public var parentDirectory: AbsolutePath {
        return isRoot ? self : AbsolutePath(_impl.dirname)
    }
    
    /// True if the path is the root directory.
    public var isRoot: Bool {
        let chars = _impl.string.characters
        return chars.count == 1 && chars.first == pathSeparatorCharacter
    }
    
    /// Returns the absolute path with the relative path applied.
    public func join(_ subpath: RelativePath) -> AbsolutePath {
        return AbsolutePath(self, subpath)
    }
    
    /// NOTE: We will want to add other methods here, such as a join() method
    ///       that takes an arbitrary number of parameters, etc.  Most likely
    ///       we will also make the `+` operator mean `join()`.
    
    /// NOTE: We will want to add a method to return the lowest common ancestor
    ///       path, and another to create a minimal relative path to get from
    ///       one AbsolutePath to another.
    
    /// Root directory (whose string representation is just a path separator).
    public static let root = AbsolutePath(String(pathSeparatorCharacter))
    
    // FIXME: We need to add a `home` property to represent the home directory.
    
    /// Normalized string representation (the normalization rules are described
    /// in the documentation of the initializer).  This string is never empty.
    public var asString: String {
        return _impl.string
    }
}


/// Represents a relative file system path.  A relative path never starts with
/// a `/` character, and holds a normalized string representation.  As with
/// AbsolutePath, the normalization is strictly syntactic, and does not access
/// the file system in any way.
///
/// The relative path string is normalized by:
/// - Collapsing `..` path components that aren't at the beginning
/// - Removing extraneous `.` path components
/// - Removing any trailing path separator
/// - Removing any redundant path separators
/// - Replacing a completely empty path with a `.`
///
/// This string manipulation may change the meaning of a path if any of the
/// path components are symbolic links on disk.  However, the file system is
/// never accessed in any way when initializing a RelativePath.
public struct RelativePath {
    /// Private implementation details, shared with the AbsolutePath struct.
    private let _impl: PathImpl
    
    /// Initializes the RelativePath from `str`, which must be a relative path
    /// (which means that it must not begin with a path separator or a tilde).
    /// An empty input path is allowed, but will be normalized to a single `.`
    /// character.  The input string will be normalized if needed, as described
    /// in the documentation for RelativePath.
    public init(_ string: String) {
        // Normalize the relative string and store it as our PathImpl.
        _impl = PathImpl(string: normalize(relative: string))
    }
    
    /// Directory component.  For a relative path, this may be empty.
    public var dirname: String {
        return _impl.dirname
    }
    
    /// Last path component (including the suffix, if any).  it is never empty.
    public var basename: String {
        return _impl.basename
    }
    
    /// Suffix (including leading `.` character) if any.  Note that a basename
    /// that starts with a `.` character is not considered a suffix, nor is a
    /// trailing `.` character.
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
    /// string (relying on the fact that it has been normalized).  Returns an
    /// empty string if there is no directory part (which is the case if and
    /// only if there is no path separator).
    private var dirname: String {
        // FIXME: This method seems too complicated; it should be simplified,
        //        if possible, and certainly optimized (using UTF8View).
        let chars = string.characters
        // Find the last path separator.
        guard let idx = chars.rindex(of: pathSeparatorCharacter) else {
            // No path separators, so the directory name is empty.
            return ""
        }
        // Check if it's the only one in the string.
        if idx == chars.startIndex {
            // Just one path separator, so the directory name is `/`.
            return String(pathSeparatorCharacter)
        }
        // Otherwise, it's the string up to (but not including) the last path
        // separator.
        return String(chars.prefix(upTo: idx))
    }
    
    private var basename: String {
        // FIXME: This method seems too complicated; it should be simplified,
        //        if possible, and certainly optimized (using UTF8View).
        let chars = string.characters
        // Check for a special case of the root directory.
        if chars.count == 1 && chars.first == pathSeparatorCharacter {
            // Root directory, so the basename is a single path separator (the
            // root directory is special in this regard).
            return String(pathSeparatorCharacter)
        }
        // Find the last path separator.
        guard let idx = chars.rindex(of: pathSeparatorCharacter) else {
            // No path separators, so the basename is the whole string.
            return string
        }
        // Otherwise, it's the string from (but not including) the last path
        // separator.
        return String(chars.suffix(from: chars.index(after: idx)))
    }
    
    private var suffix: String? {
        // FIXME: This method seems too complicated; it should be simplified,
        //        if possible, and certainly optimized (using UTF8View).
        let chars = string.characters
        // Find the last path separator, if any.
        let sIdx = chars.rindex(of: pathSeparatorCharacter)
        // Find the start of the basename.
        let bIdx = (sIdx != nil) ? chars.index(after: sIdx!) : chars.startIndex
        // Find the last `.` (if any), starting from the second character of
        // the basename (a leading `.` does not make the whole path component
        // a suffix).
        let fIdx = chars.index(bIdx, offsetBy: 1, limitedBy: chars.endIndex)
        if let idx = chars.rindex(of: ".", from: fIdx) {
            // Unless it's just a `.` at the end, we have found a suffix.
            if chars.distance(from: idx, to: chars.endIndex) > 1 {
                return String(chars.suffix(from: idx))
            }
            else {
                return nil
            }
        }
        // If we get this far, there is no suffix.
        return nil
    }
}


// FIXME: We should consider whether to merge the two `normalize()` functions.
// The argument for doing so is that some of the code is repeated; the argument
// against doing so is that some of the details are different, and since any
// given path is either absolute or relative, it's wasteful to keep checking
// for whether it's relative or absolute.  Possibly we can do both by clever
// use of generics that abstract away the differences.


/// Private function that normalizes and returns an absolute string.  Asserts
/// that `string` starts with a path separator.
///
/// The normalization rules are as described for the AbsolutePath struct.
private func normalize(absolute string: String) -> String {
    // FIXME: We will also need to support a leading `~` for a home directory.
    precondition(string.characters.first == pathSeparatorCharacter)
    
    // Get a hold of the character view.
    // FIXME: Switch to use the UTF-8 view, which is more efficient.
    let chars = string.characters
    
    // At this point we expect to have a path separator as first character.
    assert(chars.first == pathSeparatorCharacter)
    
    // FIXME: Here we should also keep track of whether anything actually has
    // to be changed in the string, and if not, just return the existing one.

    // Split the character array into parts, folding components as we go.
    // As we do so, we count the number of characters we'll end up with in
    // the normalized string representation.
    var parts: [String.CharacterView] = []
    var capacity = 0
    for part in chars.split(separator: pathSeparatorCharacter) {
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
    // FIXME: Determine the most efficient way to reassemble a string.
    var result = ""
    result.reserveCapacity(capacity)
    
    // Put the normalized parts back together again.
    var iter = parts.makeIterator()
    result.append(pathSeparatorCharacter)
    if let first = iter.next() {
        result.append(contentsOf: first)
        while let next = iter.next() {
            result.append(pathSeparatorCharacter)
            result.append(contentsOf: next)
        }
    }
    
    // Sanity-check the result (including the capacity we reserved).
    assert(!result.isEmpty, "unexpected empty string")
    assert(result.characters.count == capacity, "count: " +
        "\(result.characters.count), cap: \(capacity)")
    
    // Use the result as our stored string.
    return result
}


/// Private function that normalizes and returns a relative string.  Asserts
/// that `string` does not start with a path separator.
///
/// The normalization rules are as described for the AbsolutePath struct.
private func normalize(relative string: String) -> String {
    // FIXME: We should also guard against a leading `~`.
    precondition(string.characters.first != pathSeparatorCharacter)
    
    // Get a hold of the character view.
    // FIXME: Switch to use the UTF-8 view, which is more efficient.
    let chars = string.characters
    
    // FIXME: Here we should also keep track of whether anything actually has
    // to be changed in the string, and if not, just return the existing one.
    
    // Split the character array into parts, folding components as we go.
    // As we do so, we count the number of characters we'll end up with in
    // the normalized string representation.
    var parts: [String.CharacterView] = []
    var capacity = 0
    for part in chars.split(separator: pathSeparatorCharacter) {
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
    // FIXME: Determine the most efficient way to reassemble a string.
    var result = ""
    result.reserveCapacity(capacity)
    
    // Put the normalized parts back together again.
    var iter = parts.makeIterator()
    if let first = iter.next() {
        result.append(contentsOf: first)
        while let next = iter.next() {
            result.append(pathSeparatorCharacter)
            result.append(contentsOf: next)
        }
    }
    
    // Sanity-check the result (including the capacity we reserved).
    assert(result.characters.count == capacity, "count: " +
        "\(result.characters.count), cap: \(capacity)")
    
    // If the result is empty, return `.`, otherwise we return it as a string.
    return result.isEmpty ? "." : result
}


/// Private functions for use by the path logic.  These should move out into a
/// public place, but we'll need to debate the names, etc, etc.
private extension String.CharacterView {
    
    /// Returns the index of the last occurrence of `char` or nil if none.  If
    /// provided, the `start` index limits the search to a suffix of charview.
    private func rindex(of char: Character, from start: Index? = nil) -> Index? {
        var idx = endIndex
        let firstIdx = start ?? startIndex
        while idx > firstIdx {
            idx = index(before: idx)
            if self[idx] == char {
                return idx
            }
        }
        return nil
    }
}
