/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import Basic

/// Represents a message output by the Swift compiler in JSON output mode.
struct SwiftCompilerMessage {
    enum Kind {
        struct Output {
            let type: String
            let path: String
        }

        struct CommandInfo {
            let inputs: [String]
            let outputs: [Output]
        }

        struct OutputInfo {
            let output: String?
        }

        case began(CommandInfo)
        case skipped(CommandInfo)
        case finished(OutputInfo)
        case signalled(OutputInfo)
    }

    let name: String
    let kind: Kind
}

/// Protocol for the parser delegate to get notified of parsing events.
protocol SwiftCompilerOutputParserDelegate: class {
    /// Called for each message parsed.
    func swiftCompilerDidOutputMessage(_ message: SwiftCompilerMessage)

    /// Called on an un-expected parsing error. No more events will be received after that.
    func swiftCompilerOutputParserDidFail(withError error: Error)
}

/// Parser for the Swift compiler JSON output mode.
final class SwiftCompilerOutputParser {

    /// State of the parser state machine.
    private enum State {
        case parsingMessageSize
        case parsingMessage(size: Int)
        case parsingNewlineAfterMessage
    }

    /// Delegate to notify of parsing events.
    public var delegate: SwiftCompilerOutputParserDelegate

    /// Buffer containing the bytes until a full message can be parsed.
    private var buffer: [UInt8] = []

    /// The parser's state machine current state.
    private var state: State = .parsingMessageSize

    /// Boolean indicating if the parser has encountered an un-expected parsing error.
    private var hasFailed = false

    /// The JSON decoder to parse messages.
    private let decoder = JSONDecoder()

    /// Initializes the parser with a delegate to notify of parsing events.
    init(delegate: SwiftCompilerOutputParserDelegate) {
        self.delegate = delegate
    }

    /// Parse the next bytes of the Swift compiler JSON output.
    /// - Note: If a parsing error is encountered, the delegate will be notified and the parser won't accept any further
    ///   input.
    func parse<C>(bytes: C) where C: Collection, C.Element == UInt8 {
        guard !hasFailed else { return }

        do {
            try parseImpl(bytes: bytes)
        } catch {
            hasFailed = true
            delegate.swiftCompilerOutputParserDidFail(withError: error)
        }
    }
}

private extension SwiftCompilerOutputParser {

    /// Error corresponding to invalid Swift compiler output.
    struct ParsingError: LocalizedError {
        /// Text describing the specific reason for the parsing failure.
        let reason: String

        var errorDescription: String? {
            return reason
        }
    }

    /// Throwing implementation of the parse function.
    func parseImpl<C>(bytes: C) throws where C: Collection, C.Element == UInt8 {
        switch state {
        case .parsingMessageSize:
            if let newlineIndex = bytes.index(of: newline) {
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
                delegate.swiftCompilerDidOutputMessage(message)

                if case .signalled = message.kind {
                    hasFailed = true
                    return
                }

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
        }
    }

    /// Parse the next message size from the buffer and update the state machine.
    func parseMessageSize() throws {
        guard let string = String(bytes: buffer, encoding: .utf8) else {
            throw ParsingError(reason: "invalid UTF8 bytes")
        }

        guard let messageSize = Int(string) else {
            throw ParsingError(reason: "invalid message size")
        }

        buffer.removeAll()
        state = .parsingMessage(size: messageSize)
    }

    /// Parse the message in the buffer and update the state machine.
    func parseMessage() throws -> SwiftCompilerMessage {
        let data = Data(bytes: buffer)
        buffer.removeAll()
        state = .parsingNewlineAfterMessage

        do {
            return try decoder.decode(SwiftCompilerMessage.self, from: data)
        } catch {
            throw ParsingError(reason: "unexpected JSON message")
        }
    }
}

extension SwiftCompilerMessage: Decodable, Equatable {
    enum CodingKeys: CodingKey {
        case pid
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        kind = try Kind(from: decoder)
    }
}

extension SwiftCompilerMessage.Kind: Decodable, Equatable {
    enum CodingKeys: CodingKey {
        case kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "began":
            self = try .began(CommandInfo(from: decoder))
        case "skipped":
            self = try .skipped(CommandInfo(from: decoder))
        case "finished":
            self = try .finished(OutputInfo(from: decoder))
        case "signalled":
            self = try .signalled(OutputInfo(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "invalid kind")
        }
    }
}

extension SwiftCompilerMessage.Kind.Output: Decodable, Equatable {}
extension SwiftCompilerMessage.Kind.CommandInfo: Decodable, Equatable {}
extension SwiftCompilerMessage.Kind.OutputInfo: Decodable, Equatable {}

private let newline = UInt8(ascii: "\n")
