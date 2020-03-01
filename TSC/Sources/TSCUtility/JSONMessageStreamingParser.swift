/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import TSCBasic

/// Protocol for the parser delegate to get notified of parsing events.
public protocol JSONMessageStreamingParserDelegate: class {

    /// A decodable type representing the JSON messages being parsed.
    associatedtype Message: Decodable

    /// Called for each message parsed.
    func jsonMessageStreamingParser(_ parser: JSONMessageStreamingParser<Self>, didParse message: Message)

    /// Called when parsing raw text instead of message size.
    func jsonMessageStreamingParser(_ parser: JSONMessageStreamingParser<Self>, didParseRawText text: String)

    /// Called on an un-expected parsing error. No more events will be received after that.
    func jsonMessageStreamingParser(_ parser: JSONMessageStreamingParser<Self>, didFailWith error: Error)
}

/// Streaming parser for JSON messages seperated by integers to represent size of message. Used by the Swift compiler
/// and XCBuild to share progess information: https://github.com/apple/swift/blob/master/docs/DriverParseableOutput.rst.
public final class JSONMessageStreamingParser<Delegate: JSONMessageStreamingParserDelegate> {

    /// The object representing the JSON message being parsed.
    public typealias Message = Delegate.Message

    /// State of the parser state machine.
    private enum State {
        case parsingMessageSize
        case parsingMessage(size: Int)
        case parsingNewlineAfterMessage
        case failed
    }

    /// Delegate to notify of parsing events.
    public weak var delegate: Delegate?

    /// Buffer containing the bytes until a full message can be parsed.
    private var buffer: [UInt8] = []

    /// The parser's state machine current state.
    private var state: State = .parsingMessageSize

    /// The JSON decoder to parse messages.
    private let decoder: JSONDecoder

    /// Initializes the parser.
    /// - Parameters:
    ///   - delegate: The `JSONMessageStreamingParserDelegate` that will receive parsing event callbacks.
    ///   - decoder: The `JSONDecoder` to use for decoding JSON messages.
    public init(delegate: Delegate, decoder: JSONDecoder = JSONDecoder())
    {
        self.delegate = delegate
        self.decoder = decoder
    }

    /// Parse the next bytes of the stream.
    /// - Note: If a parsing error is encountered, the delegate will be notified and the parser won't accept any further
    ///   input.
    public func parse<C>(bytes: C) where C: Collection, C.Element == UInt8 {
        if case .failed = state { return }

        do {
            try parseImpl(bytes: bytes)
        } catch {
            state = .failed
            delegate?.jsonMessageStreamingParser(self, didFailWith: error)
        }
    }
}

private extension JSONMessageStreamingParser {

    /// Error corresponding to invalid Swift compiler output.
    struct ParsingError: LocalizedError {

        /// Text describing the specific reason for the parsing failure.
        let reason: String

        /// The underlying error, if there is one.
        let underlyingError: Error?

        var errorDescription: String? {
            if let error = underlyingError {
                return "\(reason): \(error)"
            } else {
                return reason
            }
        }
    }

    /// Throwing implementation of the parse function.
    func parseImpl<C>(bytes: C) throws where C: Collection, C.Element == UInt8 {
        switch state {
        case .parsingMessageSize:
            if let newlineIndex = bytes.firstIndex(of: newline) {
                buffer.append(contentsOf: bytes[..<newlineIndex])
                try parseMessageSize()

                let nextIndex = bytes.index(after: newlineIndex)
                try parseImpl(bytes: bytes[nextIndex...])
            } else {
                buffer.append(contentsOf: bytes)
            }
        case .parsingMessage(size: let size):
            let remainingBytes = size - buffer.count
            if remainingBytes <= bytes.count {
                buffer.append(contentsOf: bytes.prefix(remainingBytes))

                let message = try parseMessage()
                delegate?.jsonMessageStreamingParser(self, didParse: message)

                try parseImpl(bytes: bytes.dropFirst(remainingBytes))
            } else {
                buffer.append(contentsOf: bytes)
            }
        case .parsingNewlineAfterMessage:
            if let firstByte = bytes.first {
                precondition(firstByte == newline)
                state = .parsingMessageSize
                try parseImpl(bytes: bytes.dropFirst())
            }
        case .failed:
            return
        }
    }

    /// Parse the next message size from the buffer and update the state machine.
    func parseMessageSize() throws {
        guard let string = String(bytes: buffer, encoding: .utf8) else {
            throw ParsingError(reason: "invalid UTF8 bytes", underlyingError: nil)
        }

        guard let messageSize = Int(string) else {
            delegate?.jsonMessageStreamingParser(self, didParseRawText: string)
            buffer.removeAll()
            return
        }

        buffer.removeAll()
        state = .parsingMessage(size: messageSize)
    }

    /// Parse the message in the buffer and update the state machine.
    func parseMessage() throws -> Message {
        let data = Data(buffer)
        buffer.removeAll()
        state = .parsingNewlineAfterMessage

        do {
            return try decoder.decode(Message.self, from: data)
        } catch {
            throw ParsingError(reason: "unexpected JSON message: \(ByteString(buffer).cString)", underlyingError: error)
        }
    }
}

private let newline = UInt8(ascii: "\n")
