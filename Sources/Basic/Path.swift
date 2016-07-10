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
    
    /// Initializes the AbsolutePath from `absStr`, which must be an absolute
    /// path (i.e. it must begin with a path separator; this initializer does
    /// not interpret leading `~` characters as home directory specifiers).
    /// The input string will be normalized if needed, as described in the
    /// documentation for AbsolutePath.
    public init(_ absStr: String) {
        // Normalize the absolute string and store it as our PathImpl.
        _impl = PathImpl(string: normalize(absolute: absStr))
    }
    
    /// Initializes the AbsolutePath by concatenating a relative path to an
    /// existing absolute path, and renormalizing if necessary.
    public init(_ absPath: AbsolutePath, _ relPath: RelativePath) {
        // Both paths are already normalized.  The only case in which we have
        // to renormalize their concatenation is if the relative path starts
        // with a `..` path component.
        let relStr = relPath._impl.string
        var absStr = absPath._impl.string
        if absStr != String(pathSeparatorCharacter) {
            absStr.append(pathSeparatorCharacter)
        }
        absStr.append(relStr)
        
        // If the relative string starts with `.` or `..`, we need to normalize
        // the resulting string.
        // FIXME: We can actually optimize that case, since we know that the
        // normalization of a relative path can leave `..` path components at
        // the beginning of the path only.
        if relStr.hasPrefix(".") {
            absStr = normalize(absolute: absStr)
        }
        
        // Finally, store the result as our PathImpl.
        _impl = PathImpl(string: absStr)
    }
    
    /// Convenience initializer that appends a string to a relative path.
    public init(_ absPath: AbsolutePath, _ relStr: String) {
        self.init(absPath, RelativePath(relStr))
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
    public func appending(_ subpath: RelativePath) -> AbsolutePath {
        return AbsolutePath(self, subpath)
    }
    
    /// Returns the absolute path with the contents of the string (interpreted
    /// as a relative path, not a single path component) appended.
    public func appending(_ str: String) -> AbsolutePath {
        return AbsolutePath(self, str)
    }
    
    /// NOTE: We will want to add other methods, such as an appending() method
    ///       that takes an arbitrary number of parameters, etc.  Most likely
    ///       we will also make the `+` operator mean `appending()`.
    
    /// NOTE: We will want to add a method to return the lowest common ancestor
    ///       path.
    
    /// Root directory (whose string representation is just a path separator).
    public static let root = AbsolutePath(String(pathSeparatorCharacter))
    
    // FIXME: We need to add a `home` property to represent the home directory.
    
    /// Normalized string representation (the normalization rules are described
    /// in the documentation of the initializer).  This string is never empty.
    public var asString: String {
        return _impl.string
    }
    
    /// Returns an array of strings that make up the path components of the
    /// absolute path.  This is the same sequence of strings as the basenames
    /// of each successive path component, starting from the root.  Therefore
    /// the first path component of an absolute path is always `/`.
    // FIXME: We should investigate if it would be more efficient to instead
    // return a path component iterator that does all its work lazily, moving
    // from one path separator to the next on-demand.
    public var components: [String] {
        // FIXME: This isn't particularly efficient; needs optimization, and
        // in fact, it might well be best to return a custom iterator so we
        // don't have to allocate everything up-front.  It would be backed by
        // the path string and just return a slice at a time.
        return ["/"] + _impl.string.components(separatedBy: "/").filter { !$0.isEmpty }
    }
}

/// Adoption of the StringLiteralConvertible protocol allows literal strings
/// to be implicitly converted to AbsolutePaths.
extension AbsolutePath : StringLiteralConvertible {
    public typealias UnicodeScalarLiteralType = StringLiteralType
    public typealias ExtendedGraphemeClusterLiteralType = StringLiteralType
    public init(stringLiteral value: String) {
        self.init(value)
    }
    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(stringLiteral: value)
    }
    public init(unicodeScalarLiteral value: String) {
        self.init(stringLiteral: value)
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
    
    /// Directory component.  For a relative path without any path separators,
    /// this is the `.` string instead of the empty string.
    public var dirname: String {
        return _impl.dirname
    }
    
    /// Last path component (including the suffix, if any).  It is never empty.
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

    /// Returns an array of strings that make up the path components of the
    /// relative path.  This is the same sequence of strings as the basenames
    /// of each successive path component.  Therefore the returned array of
    /// path components is never empty; even an empty path has a single path
    /// component: the `.` string.
    // FIXME: We should investigate if it would be more efficient to instead
    // return a path component iterator that does all its work lazily, moving
    // from one path separator to the next on-demand.
    public var components: [String] {
        // FIXME: This isn't particularly efficient; needs optimization, and
        // in fact, it might well be best to return a custom iterator so we
        // don't have to allocate everything up-front.  It would be backed by
        // the path string and just return a slice at a time.
        return _impl.string.components(separatedBy: "/").filter { !$0.isEmpty }
    }
}

/// Adoption of the StringLiteralConvertible protocol allows literal strings
/// to be implicitly converted to RelativePaths.
extension RelativePath : StringLiteralConvertible {
    public typealias UnicodeScalarLiteralType = StringLiteralType
    public typealias ExtendedGraphemeClusterLiteralType = StringLiteralType
    public init(stringLiteral value: String) {
        self.init(value)
    }
    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(stringLiteral: value)
    }
    public init(unicodeScalarLiteral value: String) {
        self.init(stringLiteral: value)
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

// Make absolute paths Comparable.
extension AbsolutePath : Comparable { }
public func <(lhs: AbsolutePath, rhs: AbsolutePath) -> Bool {
    return lhs.asString < rhs.asString
}
public func <=(lhs: AbsolutePath, rhs: AbsolutePath) -> Bool {
    return lhs.asString <= rhs.asString
}
public func >=(lhs: AbsolutePath, rhs: AbsolutePath) -> Bool {
    return lhs.asString >= rhs.asString
}
public func >(lhs: AbsolutePath, rhs: AbsolutePath) -> Bool {
    return lhs.asString > rhs.asString
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
    /// string (relying on the fact that it has been normalized).  Returns a
    /// string consisting of just `.` if there is no directory part (which is
    /// the case if and only if there is no path separator).
    private var dirname: String {
        // FIXME: This method seems too complicated; it should be simplified,
        //        if possible, and certainly optimized (using UTF8View).
        let chars = string.characters
        // Find the last path separator.
        guard let idx = chars.rindex(of: pathSeparatorCharacter) else {
            // No path separators, so the directory name is `.`.
            return "."
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


extension AbsolutePath {
    /// Returns a relative path that, when concatenated to `base`, yields the
    /// callee path itself.  If `base` is not an ancestor of the callee, the
    /// returned path will begin with one or more `..` path components.
    ///
    /// Because both paths are absolute, they always have a common ancestor
    /// (the root path, if nothing else).  Therefore, any path can be made
    /// relative to any other path by using a sufficient number of `..` path
    /// components.
    ///
    /// This method is strictly syntactic and does not access the file system
    /// in any way.  Therefore, it does not take symbolic links into account.
    public func relative(to base: AbsolutePath) -> RelativePath {
        let result: RelativePath
        // Split the two paths into their components.
        // FIXME: The is needs to be optimized to avoid unncessary copying.
        let pathComps = self.components
        let baseComps = base.components
        
        // It's common for the base to be an ancestor, so try that first.
        if pathComps.starts(with: baseComps) {
            // Special case, which is a plain path without `..` components.  It
            // might be an empty path (when self and the base are equal).
            let relComps = pathComps.dropFirst(baseComps.count)
            result = RelativePath(relComps.joined(separator: "/"))
        }
        else {
            // General case, in which we might well need `..` components to go
            // "up" before we can go "down" the directory tree.
            var newPathComps = ArraySlice(pathComps)
            var newBaseComps = ArraySlice(baseComps)
            while newPathComps.prefix(1) == newBaseComps.prefix(1) {
                // First component matches, so drop it.
                newPathComps = newPathComps.dropFirst()
                newBaseComps = newBaseComps.dropFirst()
            }
            // Now construct a path consisting of as many `..`s as are in the
            // `newBaseComps` followed by what remains in `newPathComps`.
            var relComps = Array(repeating: "..", count: newBaseComps.count)
            relComps.append(contentsOf: newPathComps)
            result = RelativePath(relComps.joined(separator: "/"))
        }
        assert(base.appending(result) == self)
        return result
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
