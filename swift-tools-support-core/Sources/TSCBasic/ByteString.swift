/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

/// A `ByteString` represents a sequence of bytes.
///
/// This struct provides useful operations for working with buffers of
/// bytes. Conceptually it is just a contiguous array of bytes (UInt8), but it
/// contains methods and default behavor suitable for common operations done
/// using bytes strings.
///
/// This struct *is not* intended to be used for significant mutation of byte
/// strings, we wish to retain the flexibility to micro-optimize the memory
/// allocation of the storage (for example, by inlining the storage for small
/// strings or and by eliminating wasted space in growable arrays). For
/// construction of byte arrays, clients should use the `OutputByteStream` class
/// and then convert to a `ByteString` when complete.
public struct ByteString: ExpressibleByArrayLiteral, Hashable {
    /// The buffer contents.
    @usableFromInline
    internal var _bytes: [UInt8]

    /// Create an empty byte string.
    @inlinable
    public init() {
        _bytes = []
    }

    /// Create a byte string from a byte array literal.
    @inlinable
    public init(arrayLiteral contents: UInt8...) {
        _bytes = contents
    }

    /// Create a byte string from an array of bytes.
    @inlinable
    public init(_ contents: [UInt8]) {
        _bytes = contents
    }

    /// Create a byte string from an array slice.
    @inlinable
    public init(_ contents: ArraySlice<UInt8>) {
        _bytes = Array(contents)
    }

    /// Create a byte string from an byte buffer.
    @inlinable
    public init<S: Sequence> (_ contents: S) where S.Iterator.Element == UInt8 {
        _bytes = [UInt8](contents)
    }

    /// Create a byte string from the UTF8 encoding of a string.
    @inlinable
    public init(encodingAsUTF8 string: String) {
        _bytes = [UInt8](string.utf8)
    }

    /// Access the byte string contents as an array.
    @inlinable
    public var contents: [UInt8] {
        return _bytes
    }

    /// Return the byte string size.
    @inlinable
    public var count: Int {
        return _bytes.count
    }

    /// Gives a non-escaping closure temporary access to an immutable `Data` instance wrapping the `ByteString` without
    /// copying any memory around.
    ///
    /// - Parameters:
    ///   - closure: The closure that will have access to a `Data` instance for the duration of its lifetime.
    @inlinable
    public func withData<T>(_ closure: (Data) throws -> T) rethrows -> T {
        return try _bytes.withUnsafeBytes { pointer -> T in
            let mutatingPointer = UnsafeMutableRawPointer(mutating: pointer.baseAddress!)
            let data = Data(bytesNoCopy: mutatingPointer, count: pointer.count, deallocator: .none)
            return try closure(data)
        }
    }

    /// Returns a `String` lowercase hexadecimal representation of the contents of the `ByteString`.
    @inlinable
    public var hexadecimalRepresentation: String {
        _bytes.reduce("") {
            var str = String($1, radix: 16)
            // The above method does not do zero padding.
            if str.count == 1 {
                str = "0" + str
            }
            return $0 + str
        }
    }
}

/// Conform to CustomDebugStringConvertible.
extension ByteString: CustomStringConvertible {
    /// Return the string decoded as a UTF8 sequence, or traps if not possible.
    public var description: String {
        guard let description = validDescription else {
            fatalError("invalid byte string: \(cString)")
        }

        return description
    }

    /// Return the string decoded as a UTF8 sequence, if possible.
    @inlinable
    public var validDescription: String? {
        // FIXME: This is very inefficient, we need a way to pass a buffer. It
        // is also wrong if the string contains embedded '\0' characters.
        let tmp = _bytes + [UInt8(0)]
        return tmp.withUnsafeBufferPointer { ptr in
            return String(validatingUTF8: unsafeBitCast(ptr.baseAddress, to: UnsafePointer<CChar>.self))
        }
    }

    /// Return the string decoded as a UTF8 sequence, substituting replacement
    /// characters for ill-formed UTF8 sequences.
    @inlinable
    public var cString: String {
        return String(decoding: _bytes, as: Unicode.UTF8.self)
    }

    @available(*, deprecated, message: "use description or validDescription instead")
    public var asString: String? {
        return validDescription
    }
}

/// ByteStreamable conformance for a ByteString.
extension ByteString: ByteStreamable {
    @inlinable
    public func write(to stream: OutputByteStream) {
        stream.write(_bytes)
    }
}

/// StringLiteralConvertable conformance for a ByteString.
extension ByteString: ExpressibleByStringLiteral {
    public typealias UnicodeScalarLiteralType = StringLiteralType
    public typealias ExtendedGraphemeClusterLiteralType = StringLiteralType

    public init(unicodeScalarLiteral value: UnicodeScalarLiteralType) {
        _bytes = [UInt8](value.utf8)
    }
    public init(extendedGraphemeClusterLiteral value: ExtendedGraphemeClusterLiteralType) {
        _bytes = [UInt8](value.utf8)
    }
    public init(stringLiteral value: StringLiteralType) {
        _bytes = [UInt8](value.utf8)
    }
}
