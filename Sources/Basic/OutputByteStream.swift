/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import libc

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
public class OutputByteStream: TextOutputStream {
    /// The data buffer.
    /// Note: Minimum Buffer size should be one.
    private var buffer: [UInt8]

    /// Default buffer size of the data buffer.
    private static let bufferSize = 1024

    init() {
        self.buffer = []
        self.buffer.reserveCapacity(OutputByteStream.bufferSize)
    }

    // MARK: Data Access API

    /// The current offset within the output stream.
    public final var position: Int {
        return buffer.count
    }

    /// Currently available buffer size.
    private var availableBufferSize: Int {
        return buffer.capacity - buffer.count
    }

     /// Clears the buffer maintaining current capacity.
    private func clearBuffer() {
        buffer.removeAll(keepingCapacity: true)
    }

    // MARK: Data Output API

    public final func flush() {
        writeImpl(buffer)
        clearBuffer()
        flushImpl()
    }

    func flushImpl() {
        // Do nothing.
    }

    func writeImpl<C: Collection>(_ bytes: C) where C.Iterator.Element == UInt8 {
        fatalError("Subclasses must implement this")
    }

    /// Write an individual byte to the buffer.
    public final func write(_ byte: UInt8) {
        // If buffer is full, write and clear it.
        if availableBufferSize == 0 {
            writeImpl(buffer)
            clearBuffer()
        }

        // This will need to change change if we ever have unbuffered stream.
        precondition(availableBufferSize > 0)
        buffer.append(byte)
    }

    /// Write a collection of bytes to the buffer.
    public final func write<C: Collection>(collection bytes: C) where
        C.IndexDistance == Int,
        C.Iterator.Element == UInt8,
        C.SubSequence: Collection,
        C.SubSequence.Iterator.Element == UInt8
    {
        // This is based on LLVM's raw_ostream.
        let availableBufferSize = self.availableBufferSize

        // If we have to insert more than the available space in buffer.
        if bytes.count > availableBufferSize {
            // If buffer is empty, start writing and keep the last chunk in buffer.
            if buffer.isEmpty {
                let bytesToWrite = bytes.count - (bytes.count % availableBufferSize)
                let writeUptoIndex = bytes.index(bytes.startIndex, offsetBy: bytesToWrite)
                writeImpl(bytes.prefix(upTo: writeUptoIndex))

                // If remaining bytes is more than buffer size write everything.
                let bytesRemaining = bytes.count - bytesToWrite
                if bytesRemaining > availableBufferSize {
                    writeImpl(bytes.suffix(from: writeUptoIndex))
                    return
                }
                // Otherwise keep remaining in buffer.
                buffer += bytes.suffix(from: writeUptoIndex)
                return
            }

            let writeUptoIndex = bytes.index(bytes.startIndex, offsetBy: availableBufferSize)
            // Append whatever we can accommodate.
            buffer += bytes.prefix(upTo: writeUptoIndex)

            writeImpl(buffer)
            clearBuffer()

            // FIXME: We should start again with remaining chunk but this doesn't work. Write everything for now.
            //write(collection: bytes.suffix(from: writeUptoIndex))
            writeImpl(bytes.suffix(from: writeUptoIndex))
            return
        }
        buffer += bytes
    }

    /// Write the contents of a UnsafeBufferPointer<UInt8>.
    final func write(_ ptr: UnsafeBufferPointer<UInt8>) {
        write(collection: ptr)
    }
    
    /// Write a sequence of bytes to the buffer.
    public final func write(_ bytes: ArraySlice<UInt8>) {
        write(collection: bytes)
    }

    /// Write a sequence of bytes to the buffer.
    public final func write(_ bytes: [UInt8]) {
        write(collection: bytes)
    }
    
    /// Write a sequence of bytes to the buffer.
    public final func write<S: Sequence>(sequence: S) where S.Iterator.Element == UInt8 {
        // Iterate the sequence and append byte by byte since sequence's append
        // is not performant anyway.
        for byte in sequence {
            write(byte)
        }
    }

    /// Write a string to the buffer (as UTF8).
    public final func write(_ string: String) {
        // FIXME(performance): Use `string.utf8._copyContents(initializing:)`.
        write(sequence: string.utf8)
    }

    /// Write a character to the buffer (as UTF8).
    public final func write(_ character: Character) {
        write(String(character))
    }

    /// Write an arbitrary byte streamable to the buffer.
    public final func write(_ value: ByteStreamable) {
        value.write(to: self)
    }

    /// Write an arbitrary streamable to the buffer.
    public final func write(_ value: TextOutputStreamable) {
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
    public final func writeJSONEscaped(_ string: String) {
        // See RFC7159 for reference: https://tools.ietf.org/html/rfc7159
        for character in string.utf8 {
            // Handle string escapes; we use constants here to directly match the RFC.
            switch character {
                // Literal characters.
            case 0x20...0x21, 0x23...0x5B, 0x5D...0xFF:
                write(character)
            
                // Single-character escaped characters.
            case 0x22: // '"'
                write(0x5C) // '\'
                write(0x22) // '"'
            case 0x5C: // '\\'
                write(0x5C) // '\'
                write(0x5C) // '\'
            case 0x08: // '\b'
                write(0x5C) // '\'
                write(0x62) // 'b'
            case 0x0C: // '\f'
                write(0x5C) // '\'
                write(0x66) // 'b'
            case 0x0A: // '\n'
                write(0x5C) // '\'
                write(0x6E) // 'n'
            case 0x0D: // '\r'
                write(0x5C) // '\'
                write(0x72) // 'r'
            case 0x09: // '\t'
                write(0x5C) // '\'
                write(0x74) // 't'

                // Multi-character escaped characters.
            default:
                write(0x5C) // '\'
                write(0x75) // 'u'
                write(hexdigit(0))
                write(hexdigit(0))
                write(hexdigit(character >> 4))
                write(hexdigit(character & 0xF))
            }
        }
    }
}
    
/// Define an output stream operator. We need it to be left associative, so we
/// use `<<<`.
infix operator <<< : StreamingPrecedence
precedencegroup StreamingPrecedence {
  associativity: left
}

// MARK: Output Operator Implementations
//
// NOTE: It would be nice to use a protocol here and the adopt it by all the
// things we can efficiently stream out. However, that doesn't work because we
// ultimately need to provide a manual overload sometimes, e.g., TextOutputStreamable, but
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
public func <<< <C: Collection>(stream: OutputByteStream, value: C) -> OutputByteStream where
    C.Iterator.Element == UInt8,
    C.IndexDistance == Int,
    C.SubSequence: Collection,
    C.SubSequence.Iterator.Element == UInt8
{
    stream.write(collection: value)
    return stream
}

@discardableResult
public func <<< <S: Sequence>(stream: OutputByteStream, value: S) -> OutputByteStream where S.Iterator.Element == UInt8 {
    stream.write(sequence: value)
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
public func <<<(stream: OutputByteStream, value: TextOutputStreamable) -> OutputByteStream {
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
    static public func asJSON<T>(_ items: [T], transform: @escaping (T) -> String) -> ByteStreamable {
        return JSONEscapedTransformedStringListStreamable(items: items, transform: transform)
    }

    /// Write the input list to the stream with the given separator between items.
    static public func asSeparatedList<T: ByteStreamable>(_ items: [T], separator: String) -> ByteStreamable {
        return SeparatedListStreamable(items: items, separator: separator)
    }

    /// Write the input list to the stream (after applying a transform to each item) with the given separator between items.
    static public func asSeparatedList<T>(_ items: [T], transform: @escaping (T) -> ByteStreamable, separator: String) -> ByteStreamable {
        return TransformedSeparatedListStreamable(items: items, transform: transform, separator: separator)
    }
}

/// Inmemory implementation of OutputByteStream.
public final class BufferedOutputByteStream: OutputByteStream {

    /// Contents of the stream.
    // FIXME: For inmemory implementation we should be share this buffer with OutputByteStream.
    // One way to do this is by allowing OuputByteStream to install external buffers.
    private var contents = [UInt8]()

    override public init() {
        super.init()
    }

    /// The contents of the output stream.
    ///
    /// Note: This implicitly flushes the stream.
    public var bytes: ByteString {
        flush()
        return ByteString(contents)
    }

    override final func flushImpl() {
        // Do nothing.
    }

    override final func writeImpl<C: Collection>(_ bytes: C) where C.Iterator.Element == UInt8 {
        contents += bytes
    }
}

/// Represents a stream which is backed to a file. Not for instantiating.
public class FileOutputByteStream: OutputByteStream {

    /// Closes the file flushing any buffered data.
    public final func close() throws {
        flush()
        try closeImpl()
    }

    func closeImpl() throws {
        fatalError("closeImpl() should be implemented by a subclass")
    }
}

/// Implements file output stream for local file system.
public final class LocalFileOutputByteStream: FileOutputByteStream {

    /// The pointer to the file.
    let fp: UnsafeMutablePointer<FILE>

    /// True if there were any IO error during writing.
    private var error: Bool = false

    /// Closes the file on deinit if true.
    private var closeOnDeinit: Bool

    /// Instantiate using the file pointer.
    init(filePointer: UnsafeMutablePointer<FILE>, closeOnDeinit: Bool = true) throws {
        self.fp = filePointer
        self.closeOnDeinit = closeOnDeinit
        super.init()
    }

    /// Opens the file for writing at the provided path.
    ///
    /// - Parameters:
    ///     - path: Path to the file this stream should operate on.
    ///     - closeOnDeinit: If true closes the file on deinit. clients can use close() if they
    ///                      want to close themselves or catch errors encountered during writing
    ///                      to the file. Default value is true.
    ///
    /// - Throws: FileSystemError
    public init(_ path: AbsolutePath, closeOnDeinit: Bool = true) throws {
        guard let fp = fopen(path.asString, "wb") else {
            throw FileSystemError(errno: errno)
        }
        self.fp = fp
        self.closeOnDeinit = closeOnDeinit
        super.init()
    }

    deinit {
        if closeOnDeinit {
            fclose(fp)
        }
    }

    func errorDetected() {
        error = true
    }

    override final func writeImpl<C: Collection>(_ bytes: C) where C.Iterator.Element == UInt8 {
        // FIXME: This will be copying bytes but we don't have option currently.
        var contents = [UInt8](bytes)
        while true {
            let n = fwrite(&contents, 1, contents.count, fp)
            if n < 0 {
                if errno == EINTR { continue }
                errorDetected()
            } else if n != contents.count {
                errorDetected()
            }
            break
        }
    }

    override final func flushImpl() {
        fflush(fp)
    }

    override final func closeImpl() throws {
        defer {
            fclose(fp)
            // If clients called close we shouldn't call fclose again in deinit.
            closeOnDeinit = false
        }
        // Throw if errors were found during writing.
        if error {
            throw FileSystemError.ioError
        }
    }
}

/// Public stdout stream instance.
public var stdoutStream: FileOutputByteStream = try! LocalFileOutputByteStream(filePointer: libc.stdout, closeOnDeinit: false)

/// Public stderr stream instance.
public var stderrStream: FileOutputByteStream = try! LocalFileOutputByteStream(filePointer: libc.stderr, closeOnDeinit: false)
