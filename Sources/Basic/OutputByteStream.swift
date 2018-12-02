/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import SPMLibc
import Dispatch

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
/// This protocol is designed to be able to support efficient streaming to
/// different output destinations, e.g., a file or an in memory buffer. This is
/// loosely modeled on LLVM's llvm::raw_ostream class.
///
/// The stream is generally used in conjunction with the custom streaming
/// operator '<<<'. For example:
///
///   let stream = BufferedOutputByteStream()
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
public protocol OutputByteStream: class, TextOutputStream {
    /// The current offset within the output stream.
    var position: Int { get }

    /// Write an individual byte to the buffer.
    func write(_ byte: UInt8)

    /// Write a collection of bytes to the buffer.
    func write<C: Collection>(_ bytes: C) where C.Element == UInt8

    /// Flush the stream's buffer.
    func flush()
}

extension OutputByteStream {
    /// Write a sequence of bytes to the buffer.
    public func write<S: Sequence>(sequence: S) where S.Iterator.Element == UInt8 {
        // Iterate the sequence and append byte by byte since sequence's append
        // is not performant anyway.
        for byte in sequence {
            write(byte)
        }
    }

    /// Write a string to the buffer (as UTF8).
    public func write(_ string: String) {
        // FIXME(performance): Use `string.utf8._copyContents(initializing:)`.
        write(string.utf8)
    }

    /// Write a string (as UTF8) to the buffer, with escaping appropriate for
    /// embedding within a JSON document.
    ///
    /// - Note: This writes the literal data applying JSON string escaping, but
    ///         does not write any other characters (like the quotes that would surround
    ///         a JSON string).
    public func writeJSONEscaped(_ string: String) {
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

/// The `OutputByteStream` base class.
///
/// This class provides a base and efficient implementation of the `OutputByteStream`
/// protocol. It can not be used as is-as subclasses as several functions need to be
/// implemented in subclasses.
public class _OutputByteStreamBase: OutputByteStream {
    /// If buffering is enabled
    @usableFromInline let _buffered : Bool

    /// The data buffer.
    /// - Note: Minimum Buffer size should be one.
    @usableFromInline var _buffer: [UInt8]

    /// Default buffer size of the data buffer.
    private static let bufferSize = 1024

    /// Queue to protect mutating operation.
    fileprivate let queue = DispatchQueue(label: "org.swift.swiftpm.basic.stream")

    init(buffered: Bool) {
        self._buffered = buffered
        self._buffer = []

        // When not buffered we still reserve 1 byte, as it is used by the
        // by the single byte write() variant.
        self._buffer.reserveCapacity(buffered ? _OutputByteStreamBase.bufferSize : 1)
    }

    // MARK: Data Access API

    /// The current offset within the output stream.
    public var position: Int {
        return _buffer.count
    }

    /// Currently available buffer size.
    @usableFromInline var _availableBufferSize: Int {
        return _buffer.capacity - _buffer.count
    }

    /// Clears the buffer maintaining current capacity.
    @usableFromInline func _clearBuffer() {
        _buffer.removeAll(keepingCapacity: true)
    }

    // MARK: Data Output API

    public final func flush() {
        writeImpl(ArraySlice(_buffer))
        _clearBuffer()
        flushImpl()
    }

    @usableFromInline func flushImpl() {
        // Do nothing.
    }

    @usableFromInline func writeImpl<C: Collection>(_ bytes: C) where C.Iterator.Element == UInt8 {
        fatalError("Subclasses must implement this")
    }

    @usableFromInline func writeImpl(_ bytes: ArraySlice<UInt8>) {
        fatalError("Subclasses must implement this")
    }

    /// Write an individual byte to the buffer.
    public final func write(_ byte: UInt8) {
        guard _buffered else {
            _buffer.append(byte)
            writeImpl(ArraySlice(_buffer))
            flushImpl()
            _clearBuffer()
            return
        }

        // If buffer is full, write and clear it.
        if _availableBufferSize == 0 {
            writeImpl(ArraySlice(_buffer))
            _clearBuffer()
        }

        // This will need to change change if we ever have unbuffered stream.
        precondition(_availableBufferSize > 0)
        _buffer.append(byte)
    }

    /// Write a collection of bytes to the buffer.
    @inlinable public final func write<C: Collection>(_ bytes: C) where C.Element == UInt8 {
        guard _buffered else {
            if let b = bytes as? ArraySlice<UInt8> {
                // Fast path for unbuffered ArraySlice
                writeImpl(b)
            } else if let b = bytes as? Array<UInt8> {
                // Fast path for unbuffered Array
                writeImpl(ArraySlice(b))
            } else {
                // generic collection unfortunately must be temporarily buffered
                writeImpl(bytes)
            }
            flushImpl()
            return
        }

        // This is based on LLVM's raw_ostream.
        let availableBufferSize = self._availableBufferSize
        let byteCount = Int(bytes.count)

        // If we have to insert more than the available space in buffer.
        if byteCount > availableBufferSize {
            // If buffer is empty, start writing and keep the last chunk in buffer.
            if _buffer.isEmpty {
                let bytesToWrite = byteCount - (byteCount % availableBufferSize)
                let writeUptoIndex = bytes.index(bytes.startIndex, offsetBy: numericCast(bytesToWrite))
                writeImpl(bytes.prefix(upTo: writeUptoIndex))

                // If remaining bytes is more than buffer size write everything.
                let bytesRemaining = byteCount - bytesToWrite
                if bytesRemaining > availableBufferSize {
                    writeImpl(bytes.suffix(from: writeUptoIndex))
                    return
                }
                // Otherwise keep remaining in buffer.
                _buffer += bytes.suffix(from: writeUptoIndex)
                return
            }

            let writeUptoIndex = bytes.index(bytes.startIndex, offsetBy: numericCast(availableBufferSize))
            // Append whatever we can accommodate.
            _buffer += bytes.prefix(upTo: writeUptoIndex)

            writeImpl(ArraySlice(_buffer))
            _clearBuffer()

            // FIXME: We should start again with remaining chunk but this doesn't work. Write everything for now.
            //write(collection: bytes.suffix(from: writeUptoIndex))
            writeImpl(bytes.suffix(from: writeUptoIndex))
            return
        }
        _buffer += bytes
    }
}

/// The thread-safe wrapper around output byte streams.
///
/// This class wraps any `OutputByteStream` conforming type to provide a type-safe
/// access to its operations. If the provided stream inherits from `_OutputByteStreamBase`,
/// it will also ensure it is type-safe will all other `ThreadSafeOutputByteStream` instances
/// around the same stream.
public final class ThreadSafeOutputByteStream: OutputByteStream {
    private static let defaultQueue = DispatchQueue(label: "org.swift.swiftpm.basic.thread-safe-output-byte-stream")
    public let stream: OutputByteStream
    private let queue: DispatchQueue

    public var position: Int {
        return queue.sync {
            stream.position
        }
    }

    public init(_ stream: OutputByteStream) {
        self.stream = stream
        self.queue = (stream as? _OutputByteStreamBase)?.queue ?? ThreadSafeOutputByteStream.defaultQueue
    }

    public func write(_ byte: UInt8) {
        queue.sync {
            stream.write(byte)
        }
    }

    public func write<C: Collection>(_ bytes: C) where C.Element == UInt8 {
        queue.sync {
            stream.write(bytes)
        }
    }

    public func flush() {
        queue.sync {
            stream.flush()
        }
    }

    public func write<S: Sequence>(sequence: S) where S.Iterator.Element == UInt8 {
        queue.sync {
            stream.write(sequence: sequence)
        }
    }

    public func writeJSONEscaped(_ string: String) {
        queue.sync {
            stream.writeJSONEscaped(string)
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

// FIXME: This override shouldn't be necesary but removing it causes a 30% performance regression. This problem is
// tracked by the following bug: https://bugs.swift.org/browse/SR-8535
@discardableResult
public func <<< (stream: OutputByteStream, value: ArraySlice<UInt8>) -> OutputByteStream {
    value.write(to: stream)
    return stream
}

@discardableResult
public func <<< (stream: OutputByteStream, value: ByteStreamable) -> OutputByteStream {
    value.write(to: stream)
    return stream
}

extension UInt8: ByteStreamable {
    public func write(to stream: OutputByteStream) {
        stream.write(self)
    }
}

extension Character: ByteStreamable {
    public func write(to stream: OutputByteStream) {
        stream.write(String(self))
    }
}

extension String: ByteStreamable {
    public func write(to stream: OutputByteStream) {
        stream.write(self.utf8)
    }
}

extension Substring: ByteStreamable {
    public func write(to stream: OutputByteStream) {
        stream.write(self.utf8)
    }
}

extension StaticString: ByteStreamable {
    public func write(to stream: OutputByteStream) {
        withUTF8Buffer { stream.write($0) }
    }
}

extension Array: ByteStreamable where Element == UInt8 {
    public func write(to stream: OutputByteStream) {
        stream.write(self)
    }
}

extension ArraySlice: ByteStreamable where Element == UInt8 {
    public func write(to stream: OutputByteStream) {
        stream.write(self)
    }
}

extension ContiguousArray: ByteStreamable where Element == UInt8 {
    public func write(to stream: OutputByteStream) {
        stream.write(self)
    }
}

// MARK: Formatted Streaming Output

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

    /// Write the input list to the stream with the given separator between items.
    static public func asSeparatedList<T: ByteStreamable>(_ items: [T], separator: String) -> ByteStreamable {
        return SeparatedListStreamable(items: items, separator: separator)
    }
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

    /// Write the input list to the stream (after applying a transform to each item) with the given separator between
    /// items.
    static public func asSeparatedList<T>(
        _ items: [T],
        transform: @escaping (T) -> ByteStreamable,
        separator: String
    ) -> ByteStreamable {
        return TransformedSeparatedListStreamable(items: items, transform: transform, separator: separator)
    }
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

    static public func asRepeating(string: String, count: Int) -> ByteStreamable {
        return RepeatingStringStreamable(string: string, count: count)
    }
    private struct RepeatingStringStreamable: ByteStreamable {
        let string: String
        let count: Int

        init(string: String, count: Int) {
            precondition(count >= 0, "Count should be >= zero")
            self.string = string
            self.count = count
        }

        func write(to stream: OutputByteStream) {
            for _ in 0..<count {
                stream <<< string
            }
        }
    }
}

/// In memory implementation of OutputByteStream.
public final class BufferedOutputByteStream: _OutputByteStreamBase {

    /// Contents of the stream.
    private var contents = [UInt8]()

    public init() {
        // We disable the buffering of the underlying _OutputByteStreamBase as
        // we are explicitly buffering the whole stream in memory
        super.init(buffered: false)
    }

    /// The contents of the output stream.
    ///
    /// - Note: This implicitly flushes the stream.
    public var bytes: ByteString {
        flush()
        return ByteString(contents)
    }

    /// The current offset within the output stream.
    override public final var position: Int {
        return contents.count
    }

    override final func flushImpl() {
        // Do nothing.
    }

    override final func writeImpl<C: Collection>(_ bytes: C) where C.Iterator.Element == UInt8 {
        contents += bytes
    }
    override final func writeImpl(_ bytes: ArraySlice<UInt8>) {
        contents += bytes
    }
}

/// Represents a stream which is backed to a file. Not for instantiating.
public class FileOutputByteStream: _OutputByteStreamBase {

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
    let filePointer: UnsafeMutablePointer<FILE>

    /// True if there were any IO error during writing.
    private var error: Bool = false

    /// Closes the file on deinit if true.
    private var closeOnDeinit: Bool

    /// Instantiate using the file pointer.
    init(filePointer: UnsafeMutablePointer<FILE>, closeOnDeinit: Bool = true, buffered: Bool = true) throws {
        self.filePointer = filePointer
        self.closeOnDeinit = closeOnDeinit
        super.init(buffered: buffered)
    }

    /// Opens the file for writing at the provided path.
    ///
    /// - Parameters:
    ///     - path: Path to the file this stream should operate on.
    ///     - closeOnDeinit: If true closes the file on deinit. clients can use
    ///                      close() if they want to close themselves or catch
    ///                      errors encountered during writing to the file.
    ///                      Default value is true.
    ///     - buffered: If true buffers writes in memory until full or flush().
    ///                 Otherwise, writes are processed and flushed immediately.
    ///                 Default value is true.
    ///
    /// - Throws: FileSystemError
    public init(_ path: AbsolutePath, closeOnDeinit: Bool = true, buffered: Bool = true) throws {
        guard let filePointer = fopen(path.asString, "wb") else {
            throw FileSystemError(errno: errno)
        }
        self.filePointer = filePointer
        self.closeOnDeinit = closeOnDeinit
        super.init(buffered: buffered)
    }

    deinit {
        if closeOnDeinit {
            fclose(filePointer)
        }
    }

    func errorDetected() {
        error = true
    }

    override final func writeImpl<C: Collection>(_ bytes: C) where C.Iterator.Element == UInt8 {
        // FIXME: This will be copying bytes but we don't have option currently.
        var contents = [UInt8](bytes)
        while true {
            let n = fwrite(&contents, 1, contents.count, filePointer)
            if n < 0 {
                if errno == EINTR { continue }
                errorDetected()
            } else if n != contents.count {
                errorDetected()
            }
            break
        }
    }

    override final func writeImpl(_ bytes: ArraySlice<UInt8>) {
        bytes.withUnsafeBytes { bytesPtr in
            while true {
                let n = fwrite(bytesPtr.baseAddress, 1, bytesPtr.count, filePointer)
                if n < 0 {
                    if errno == EINTR { continue }
                    errorDetected()
                } else if n != bytesPtr.count {
                    errorDetected()
                }
                break
            }
        }
    }

    override final func flushImpl() {
        fflush(filePointer)
    }

    override final func closeImpl() throws {
        defer {
            fclose(filePointer)
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
public var stdoutStream: ThreadSafeOutputByteStream = try! ThreadSafeOutputByteStream(LocalFileOutputByteStream(
    filePointer: SPMLibc.stdout,
    closeOnDeinit: false))

/// Public stderr stream instance.
public var stderrStream: ThreadSafeOutputByteStream = try! ThreadSafeOutputByteStream(LocalFileOutputByteStream(
    filePointer: SPMLibc.stderr,
    closeOnDeinit: false))
