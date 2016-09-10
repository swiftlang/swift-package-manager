/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/


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
/// Note that `~` (home directory resolution) is *not* done as part of path
/// normalization, because it is normally the responsibility of the shell and
/// not the program being invoked (e.g. when invoking `cd ~`, it is the shell
/// that evaluates the tilde; the `cd` command receives an absolute path).
public struct AbsolutePath {
    /// Check if the given name is a valid individual path component.
    ///
    /// This only checks with regard to the semantics enforced by `AbsolutePath`
    /// and `RelativePath`; particular file systems may have their own
    /// additional requirements.
    public static func isValidComponent(_ name: String) -> Bool {
        return name != "" && name != "." && name != ".." && !name.contains("/")
    }
    
    /// Private implementation details, shared with the RelativePath struct.
    private let _impl: PathImpl

    /// Private initializer when the backing storage is known.
    private init(_ impl: PathImpl) {
        _impl = impl
    }
    
    /// Initializes the AbsolutePath from `absStr`, which must be an absolute
    /// path (i.e. it must begin with a path separator; this initializer does
    /// not interpret leading `~` characters as home directory specifiers).
    /// The input string will be normalized if needed, as described in the
    /// documentation for AbsolutePath.
    public init(_ absStr: String) {
        // Normalize the absolute string.
        self.init(PathImpl(string: normalize(absolute: absStr)))
    }
    
    /// Initializes an AbsolutePath from a string that may be either absolute
    /// or relative; if relative, `basePath` is used as the anchor; if absolute,
    /// it is used as is, and in this case `basePath` is ignored.
    public init(_ str: String, relativeTo basePath: AbsolutePath) {
        if str.hasPrefix("/") {
            self.init(str)
        }
        else {
            self.init(basePath, RelativePath(str))
        }
    }
    
    /// Initializes the AbsolutePath by concatenating a relative path to an
    /// existing absolute path, and renormalizing if necessary.
    public init(_ absPath: AbsolutePath, _ relPath: RelativePath) {
        // Both paths are already normalized.  The only case in which we have
        // to renormalize their concatenation is if the relative path starts
        // with a `..` path component.
        let relStr = relPath._impl.string
        var absStr = absPath._impl.string
        if absStr != "/" {
            absStr.append("/")
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
        self.init(PathImpl(string: absStr))
    }
    
    /// Convenience initializer that appends a string to a relative path.
    public init(_ absPath: AbsolutePath, _ relStr: String) {
        self.init(absPath, RelativePath(relStr))
    }
    
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

    /// Extension of the give path's basename. This follow same rules as
    /// suffix except that it doesn't include leading `.` character.
    public var `extension`: String? {
        return _impl.extension
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
        return chars.count == 1 && chars.first == "/"
    }
    
    /// Returns the absolute path with the relative path applied.
    public func appending(_ subpath: RelativePath) -> AbsolutePath {
        return AbsolutePath(self, subpath)
    }
    
    /// Returns the absolute path with an additional literal component appended.
    ///
    /// This method should only be used in cases where the input is guaranteed
    /// to be a valid path component (i.e., it cannot be empty, contain a path
    /// separator, or be a pseudo-path like '.' or '..').
    public func appending(component name: String) -> AbsolutePath {
        assert(AbsolutePath.isValidComponent(name))
        if self == AbsolutePath.root {
            return AbsolutePath(PathImpl(string: "/" + name))
        } else {
            return AbsolutePath(PathImpl(string: _impl.string + "/" + name))
        }            
    }
    
    /// Returns the absolute path with additional literal components appended.
    ///
    /// This method should only be used in cases where the input is guaranteed
    /// to be a valid path component (i.e., it cannot be empty, contain a path
    /// separator, or be a pseudo-path like '.' or '..').
    public func appending(components names: String...) -> AbsolutePath {
        // FIXME: This doesn't seem a particularly efficient way to do this.
        return names.reduce(self, { path, name in
                path.appending(component: name)
            })
    }

    /// NOTE: We will most likely want to add other `appending()` methods, such
    ///       as `appending(suffix:)`, and also perhaps `replacing()` methods,
    ///       such as `replacing(suffix:)` or `replacing(basename:)` for some
    ///       of the more common path operations.
    
    /// NOTE: We may want to consider adding operators such as `+` for appending
    ///       a path component.
    
    /// NOTE: We will want to add a method to return the lowest common ancestor
    ///       path.
    
    /// Root directory (whose string representation is just a path separator).
    public static let root = AbsolutePath("/")
    
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
        return ["/"] + _impl.string.components(separatedBy: "/").filter {
            !$0.isEmpty
        }
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
    fileprivate let _impl: PathImpl
    
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

    /// Extension of the give path's basename. This follow same rules as
    /// suffix except that it doesn't include leading `.` character.
    public var `extension`: String? {
        return _impl.extension
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

/// Make absolute paths CustomStringConvertible.
extension AbsolutePath : CustomStringConvertible {
    public var description: String {
        // FIXME: We should really be escaping backslashes and quotes here.
        return "<AbsolutePath:\"\(asString)\">"
    }
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

/// Make relative paths CustomStringConvertible.
extension RelativePath : CustomStringConvertible {
    public var description: String {
        // FIXME: We should really be escaping backslashes and quotes here.
        return "<RelativePath:\"\(asString)\">"
    }
}


/// Private implementation shared between AbsolutePath and RelativePath.  It is
/// a little unfortunate that there needs to be duplication at all between the
/// AbsolutePath and RelativePath struct, but PathImpl helps mitigate it.  From
/// a type safety perspective, absolute paths and relative paths are genuinely
/// different.
private struct PathImpl {
    /// Normalized string of the (absolute or relative) path.  Never empty.
    fileprivate let string: String
    
    /// Private function that returns the directory part of the stored path
    /// string (relying on the fact that it has been normalized).  Returns a
    /// string consisting of just `.` if there is no directory part (which is
    /// the case if and only if there is no path separator).
    fileprivate var dirname: String {
        // FIXME: This method seems too complicated; it should be simplified,
        //        if possible, and certainly optimized (using UTF8View).
        let chars = string.characters
        // Find the last path separator.
        guard let idx = chars.rindex(of: "/") else {
            // No path separators, so the directory name is `.`.
            return "."
        }
        // Check if it's the only one in the string.
        if idx == chars.startIndex {
            // Just one path separator, so the directory name is `/`.
            return "/"
        }
        // Otherwise, it's the string up to (but not including) the last path
        // separator.
        return String(chars.prefix(upTo: idx))
    }
    
    fileprivate var basename: String {
        // FIXME: This method seems too complicated; it should be simplified,
        //        if possible, and certainly optimized (using UTF8View).
        let chars = string.characters
        // Check for a special case of the root directory.
        if chars.count == 1 && chars.first == "/" {
            // Root directory, so the basename is a single path separator (the
            // root directory is special in this regard).
            return "/"
        }
        // Find the last path separator.
        guard let idx = chars.rindex(of: "/") else {
            // No path separators, so the basename is the whole string.
            return string
        }
        // Otherwise, it's the string from (but not including) the last path
        // separator.
        return String(chars.suffix(from: chars.index(after: idx)))
    }
    
    fileprivate var suffix: String? {
        return suffix(withDot: true)
    }

    fileprivate var `extension`: String? {
        return suffix(withDot: false)
    }

    /// Returns suffix with leading `.` if withDot is true otherwise without it. 
    private func suffix(withDot: Bool) -> String? {
        // FIXME: This method seems too complicated; it should be simplified,
        //        if possible, and certainly optimized (using UTF8View).
        let chars = string.characters
        // Find the last path separator, if any.
        let sIdx = chars.rindex(of: "/")
        // Find the start of the basename.
        let bIdx = (sIdx != nil) ? chars.index(after: sIdx!) : chars.startIndex
        // Find the last `.` (if any), starting from the second character of
        // the basename (a leading `.` does not make the whole path component
        // a suffix).
        let fIdx = chars.index(bIdx, offsetBy: 1, limitedBy: chars.endIndex)
        if let idx = chars.rindex(of: ".", from: fIdx) {
            // Unless it's just a `.` at the end, we have found a suffix.
            if chars.distance(from: idx, to: chars.endIndex) > 1 {
                let fromIndex = withDot ? idx : chars.index(idx, offsetBy: 1)
                return String(chars.suffix(from: fromIndex))
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
    precondition(string.characters.first == "/")
    
    // Get a hold of the character view.
    // FIXME: Switch to use the UTF-8 view, which is more efficient.
    let chars = string.characters
    
    // At this point we expect to have a path separator as first character.
    assert(chars.first == "/")
    
    // FIXME: Here we should also keep track of whether anything actually has
    // to be changed in the string, and if not, just return the existing one.

    // Split the character array into parts, folding components as we go.
    // As we do so, we count the number of characters we'll end up with in
    // the normalized string representation.
    var parts: [String.CharacterView] = []
    var capacity = 0
    for part in chars.split(separator: "/") {
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
    result.append("/")
    if let first = iter.next() {
        result.append(contentsOf: first)
        while let next = iter.next() {
            result.append("/")
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
    precondition(string.characters.first != "/")
    
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
    for part in chars.split(separator: "/") {
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
            result.append("/")
            result.append(contentsOf: next)
        }
    }
    
    // Sanity-check the result (including the capacity we reserved).
    assert(result.characters.count == capacity, "count: " +
        "\(result.characters.count), cap: \(capacity)")
    
    // If the result is empty, return `.`, otherwise we return it as a string.
    return result.isEmpty ? "." : result
}
