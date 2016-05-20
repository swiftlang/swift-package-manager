/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Convert an integer in 0..<16 to its hexadecimal ASCII character.
private func hexdigit(_ value: UInt8) -> UInt8 {
    return value < 10 ? (0x30 + value) : (0x41 + value - 10)
}

/// Describes a type which can be written to a byte stream.
public protocol ByteStreamable {
    func write(to stream: OutputByteStream)
}

/// An output byte stream.
///
/// This class is designed to be able to support efficient streaming to
/// different output destinations, e.g., a file or an in memory buffer. This is
/// loosely modeled on LLVM's llvm::raw_ostream class.
///
/// The stream is generally used in conjunction with the custom streaming
/// operator '<<<'. For example:
///
///   let stream = OutputByteStream()
///   stream <<< "Hello, world!"
///
/// would write the UTF8 encoding of "Hello, world!" to the stream.
///
/// The stream accepts a number of custom formatting operators which are defined
/// in the `Format` struct (used for namespacing purposes). For example:
/// 
///   let items = ["hello", "world"]
///   stream <<< Format.asSeparatedList(items, separator: " ")
///
/// would write each item in the list to the stream, separating them with a
/// space.
public class OutputByteStream: OutputStream {
    /// The data buffer.
    private var buffer: [UInt8]
    
    public init() {
        self.buffer = []
    }

    // MARK: Data Access API

    /// The current offset within the output stream.
    public var position: Int {
        return buffer.count
    }

    /// The contents of the output stream.
    ///
    /// This method implicitly flushes the stream.
    public var bytes: ByteString {
        flush()
        return ByteString(self.buffer)
    }
    
    // MARK: Data Output API

    public func flush() {
        // Do nothing.
    }

    /// Write an individual byte to the buffer.
    public func write(_ byte: UInt8) {
        buffer.append(byte)
    }
    
    /// Write a sequence of bytes to the buffer.
    public func write(_ bytes: [UInt8]) {
        buffer += bytes
    }
    
    /// Write a sequence of bytes to the buffer.
    public func write(_ bytes: ArraySlice<UInt8>) {
        buffer += bytes
    }
    
    /// Write a sequence of bytes to the buffer.
    public func write<S: Sequence where S.Iterator.Element == UInt8>(_ sequence: S) {
        buffer += sequence
    }

    /// Write a string to the buffer (as UTF8).
    public func write(_ string: String) {
        // Fast path for contiguous strings. For some reason Swift itself
        // doesn't implement this optimization: <rdar://problem/24100375> Missing fast path for [UInt8] += String.UTF8View
        let stringPtrStart = string._contiguousUTF8
        if stringPtrStart != nil {
            buffer += UnsafeBufferPointer(start: stringPtrStart, count: string.utf8.count)
        } else {
            buffer += string.utf8
        }
    }

    /// Write a character to the buffer (as UTF8).
    public func write(_ character: Character) {
        buffer += String(character).utf8
    }

    /// Write an arbitrary byte streamable to the buffer.
    public func write(_ value: ByteStreamable) {
        value.write(to: self)
    }

    /// Write an arbitrary streamable to the buffer.
    public func write(_ value: Streamable) {
        // Get a mutable reference.
        var stream: OutputByteStream = self
        value.write(to: &stream)
    }

    /// Write a string (as UTF8) to the buffer, with escaping appropriate for
    /// embedding within a JSON document.
    ///
    /// NOTE: This writes the literal data applying JSON string escaping, but
    /// does not write any other characters (like the quotes that would surround
    /// a JSON string).
    public func writeJSONEscaped(_ string: String) {
        // See RFC7159 for reference.
        for character in string.utf8 {
            switch character {
                // Literal characters.
                //
                // FIXME: Workaround: <rdar://problem/22546289> Unexpected crash with range to max value for type
            case 0x20...0x21, 0x23...0x5B, 0x5D...0xFE, 0xFF:
                buffer.append(character)
            
                // Single-character escaped characters.
            case 0x22: // '"'
                buffer.append(0x5C) // '\'
                buffer.append(0x22) // '"'
            case 0x5C: // '\\'
                buffer.append(0x5C) // '\'
                buffer.append(0x5C) // '\'
            case 0x08: // '\b'
                buffer.append(0x5C) // '\'
                buffer.append(0x62) // 'b'
            case 0x0C: // '\f'
                buffer.append(0x5C) // '\'
                buffer.append(0x66) // 'b'
            case 0x0A: // '\n'
                buffer.append(0x5C) // '\'
                buffer.append(0x6E) // 'n'
            case 0x0D: // '\r'
                buffer.append(0x5C) // '\'
                buffer.append(0x72) // 'r'
            case 0x09: // '\t'
                buffer.append(0x5C) // '\'
                buffer.append(0x74) // 't'

                // Multi-character escaped characters.
            default:
                buffer.append(0x5C) // '\'
                buffer.append(0x75) // 'u'
                buffer.append(hexdigit(0))
                buffer.append(hexdigit(0))
                buffer.append(hexdigit(character >> 4))
                buffer.append(hexdigit(character & 0xF))
            }
        }
    }
}
    
/// Define an output stream operator. We need it to be left associative, so we
/// use `<<<`.
infix operator <<< { associativity left }

// MARK: Output Operator Implementations
//
// NOTE: It would be nice to use a protocol here and the adopt it by all the
// things we can efficiently stream out. However, that doesn't work because we
// ultimately need to provide a manual overload sometimes, e.g., Streamable, but
// that will then cause ambiguous lookup versus the implementation just using
// the defined protocol.

@discardableResult
public func <<<(stream: OutputByteStream, value: UInt8) -> OutputByteStream {
    stream.write(value)
    return stream
}

@discardableResult
public func <<<(stream: OutputByteStream, value: [UInt8]) -> OutputByteStream {
    stream.write(value)
    return stream
}

@discardableResult
public func <<<(stream: OutputByteStream, value: ArraySlice<UInt8>) -> OutputByteStream {
    stream.write(value)
    return stream
}

@discardableResult
public func <<<<S: Sequence where S.Iterator.Element == UInt8>(stream: OutputByteStream, value: S) -> OutputByteStream {
    stream.write(value)
    return stream
}

@discardableResult
public func <<<(stream: OutputByteStream, value: String) -> OutputByteStream {
    stream.write(value)
    return stream
}

@discardableResult
public func <<<(stream: OutputByteStream, value: Character) -> OutputByteStream {
    stream.write(value)
    return stream
}

@discardableResult
public func <<<(stream: OutputByteStream, value: ByteStreamable) -> OutputByteStream {
    stream.write(value)
    return stream
}

@discardableResult
public func <<<(stream: OutputByteStream, value: Streamable) -> OutputByteStream {
    stream.write(value)
    return stream
}

extension UInt8: ByteStreamable {
    public func write(to stream: OutputByteStream) {
        stream.write(self)
    }
}

extension Character: ByteStreamable {
    public func write(to stream: OutputByteStream) {
        stream.write(self)
    }
}

extension String: ByteStreamable {
    public func write(to stream: OutputByteStream) {
        stream.write(self)
    }
}

// MARK: Formatted Streaming Output

// Not nested because it is generic.
private struct SeparatedListStreamable<T: ByteStreamable>: ByteStreamable {
    let items: [T]
    let separator: String
    
    func write(to stream: OutputByteStream) {
        for (i, item) in items.enumerated() {
            // Add the separator, if necessary.
            if i != 0 {
                stream <<< separator
            }
            
            stream <<< item
        }
    }
}

// Not nested because it is generic.
private struct TransformedSeparatedListStreamable<T>: ByteStreamable {
    let items: [T]
    let transform: (T) -> ByteStreamable
    let separator: String
    
    func write(to stream: OutputByteStream) {
        for (i, item) in items.enumerated() {
            if i != 0 { stream <<< separator }
            stream <<< transform(item)
        }
    }
}

// Not nested because it is generic.
private struct JSONEscapedTransformedStringListStreamable<T>: ByteStreamable {
    let items: [T]
    let transform: (T) -> String

    func write(to stream: OutputByteStream) {
        stream <<< UInt8(ascii: "[")
        for (i, item) in items.enumerated() {
            if i != 0 { stream <<< "," }
            stream <<< Format.asJSON(transform(item))
        }
        stream <<< UInt8(ascii: "]")
    }
}

/// Provides operations for returning derived streamable objects to implement various forms of formatted output.
public struct Format {
    /// Write the input boolean encoded as a JSON object.
    static public func asJSON(_ value: Bool) -> ByteStreamable {
        return JSONEscapedBoolStreamable(value: value)
    }
    private struct JSONEscapedBoolStreamable: ByteStreamable {
        let value: Bool
        
        func write(to stream: OutputByteStream) {
            stream <<< (value ? "true" : "false")
        }
    }

    /// Write the input integer encoded as a JSON object.
    static public func asJSON(_ value: Int) -> ByteStreamable {
        return JSONEscapedIntStreamable(value: value)
    }
    private struct JSONEscapedIntStreamable: ByteStreamable {
        let value: Int
        
        func write(to stream: OutputByteStream) {
            // FIXME: Diagnose integers which cannot be represented in JSON.
            stream <<< value.description
        }
    }

    /// Write the input double encoded as a JSON object.
    static public func asJSON(_ value: Double) -> ByteStreamable {
        return JSONEscapedDoubleStreamable(value: value)
    }
    private struct JSONEscapedDoubleStreamable: ByteStreamable {
        let value: Double
        
        func write(to stream: OutputByteStream) {
            // FIXME: What should we do about NaN, etc.?
            //
            // FIXME: Is Double.debugDescription the best representation?
            stream <<< value.debugDescription
        }
    }

    /// Write the input string encoded as a JSON object.
    static public func asJSON(_ string: String) -> ByteStreamable {
        return JSONEscapedStringStreamable(value: string)
    }
    private struct JSONEscapedStringStreamable: ByteStreamable {
        let value: String
        
        func write(to stream: OutputByteStream) {
            stream <<< UInt8(ascii: "\"")
            stream.writeJSONEscaped(value)
            stream <<< UInt8(ascii: "\"")
        }
    }
    
    /// Write the input string list encoded as a JSON object.
    //
    // FIXME: We might be able to make this more generic through the use of a "JSONEncodable" protocol.
    static public func asJSON(_ items: [String]) -> ByteStreamable {
        return JSONEscapedStringListStreamable(items: items)
    }
    private struct JSONEscapedStringListStreamable: ByteStreamable {
        let items: [String]
        
        func write(to stream: OutputByteStream) {
            stream <<< UInt8(ascii: "[")
            for (i, item) in items.enumerated() {
                if i != 0 { stream <<< "," }
                stream <<< Format.asJSON(item)
            }
            stream <<< UInt8(ascii: "]")
        }
    }

    /// Write the input dictionary encoded as a JSON object.
    static public func asJSON(_ items: [String: String]) -> ByteStreamable {
        return JSONEscapedDictionaryStreamable(items: items)
    }
    private struct JSONEscapedDictionaryStreamable: ByteStreamable {
        let items: [String: String]
        
        func write(to stream: OutputByteStream) {
            stream <<< UInt8(ascii: "{")
            for (offset: i, element: (key: key, value: value)) in items.enumerated() {
                if i != 0 { stream <<< "," }
                stream <<< Format.asJSON(key) <<< ":" <<< Format.asJSON(value)
            }
            stream <<< UInt8(ascii: "}")
        }
    }

    /// Write the input list (after applying a transform to each item) encoded as a JSON object.
    //
    // FIXME: We might be able to make this more generic through the use of a "JSONEncodable" protocol.
    static public func asJSON<T>(_ items: [T], transform: (T) -> String) -> ByteStreamable {
        return JSONEscapedTransformedStringListStreamable(items: items, transform: transform)
    }

    /// Write the input list to the stream with the given separator between items.
    static public func asSeparatedList<T: ByteStreamable>(_ items: [T], separator: String) -> ByteStreamable {
        return SeparatedListStreamable(items: items, separator: separator)
    }

    /// Write the input list to the stream (after applying a transform to each item) with the given separator between items.
    static public func asSeparatedList<T>(_ items: [T], transform: (T) -> ByteStreamable, separator: String) -> ByteStreamable {
        return TransformedSeparatedListStreamable(items: items, transform: transform, separator: separator)
    }
}
