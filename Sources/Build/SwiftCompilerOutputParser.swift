/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import TSCBasic

/// Represents a message output by the Swift compiler in JSON output mode.
public struct SwiftCompilerMessage {
    public enum Kind {
        public struct Output {
            public let type: String
            public let path: String

            public init(type: String, path: String) {
                self.type = type
                self.path = path
            }
        }

        public struct BeganInfo {
            public let pid: Int
            public let inputs: [String]
            public let outputs: [Output]
            public let commandExecutable: String
            public let commandArguments: [String]

            public init(
                pid: Int,
                inputs: [String],
                outputs: [Output],
                commandExecutable: String,
                commandArguments: [String]
            ) {
                self.pid = pid
                self.inputs = inputs
                self.outputs = outputs
                self.commandExecutable = commandExecutable
                self.commandArguments = commandArguments
            }
        }

        public struct SkippedInfo {
            public let inputs: [String]
            public let outputs: [Output]

            public init(inputs: [String], outputs: [SwiftCompilerMessage.Kind.Output]) {
                self.inputs = inputs
                self.outputs = outputs
            }
        }

        public struct OutputInfo {
            public let pid: Int
            public let output: String?

            public init(pid: Int, output: String?) {
                self.pid = pid
                self.output = output
            }
        }

        case began(BeganInfo)
        case skipped(SkippedInfo)
        case finished(OutputInfo)
        case signalled(OutputInfo)
        case unparsableOutput(String)
    }

    public let name: String
    public let kind: Kind

    public init(name: String, kind: SwiftCompilerMessage.Kind) {
        self.name = name
        self.kind = kind
    }
}

/// Protocol for the parser delegate to get notified of parsing events.
public protocol SwiftCompilerOutputParserDelegate: class {
    /// Called for each message parsed.
    func swiftCompilerOutputParser(_ parser: SwiftCompilerOutputParser, didParse message: SwiftCompilerMessage)

    /// Called on an un-expected parsing error. No more events will be received after that.
    func swiftCompilerOutputParser(_ parser: SwiftCompilerOutputParser, didFailWith error: Error)
}

/// Parser for the Swift compiler JSON output mode.
public final class SwiftCompilerOutputParser {

    /// State of the parser state machine.
    private enum State {
        case parsingMessageSize
        case parsingMessage(size: Int)
        case parsingNewlineAfterMessage
    }

    /// Name of the target the compiler is compiling.
    public let targetName: String

    /// Delegate to notify of parsing events.
    public weak var delegate: SwiftCompilerOutputParserDelegate?

    /// Buffer containing the bytes until a full message can be parsed.
    private var buffer: [UInt8] = []

    /// The parser's state machine current state.
    private var state: State = .parsingMessageSize

    /// Boolean indicating if the parser has encountered an un-expected parsing error.
    private var hasFailed = false

    /// The JSON decoder to parse messages.
    private let decoder: JSONDecoder

    /// Initializes the parser with a delegate to notify of parsing events.
    public init(targetName: String, delegate: SwiftCompilerOutputParserDelegate) {
        self.targetName = targetName
        self.delegate = delegate
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    /// Parse the next bytes of the Swift compiler JSON output.
    /// - Note: If a parsing error is encountered, the delegate will be notified and the parser won't accept any further
    ///   input.
    public func parse<C>(bytes: C) where C: Collection, C.Element == UInt8 {
        guard !hasFailed else { return }

        do {
            try parseImpl(bytes: bytes)
        } catch {
            hasFailed = true
            delegate?.swiftCompilerOutputParser(self, didFailWith: error)
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
                delegate?.swiftCompilerOutputParser(self, didParse: message)

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
            // Non-parseable chunks are *assumed* to be output. E.g., you get
            // a "remark" if you build with SWIFTC_MAXIMUM_DETERMINISM env variable.
            let message = SwiftCompilerMessage(name: "unknown", kind: .unparsableOutput(string))
            delegate?.swiftCompilerOutputParser(self, didParse: message)
            buffer.removeAll()
            return
        }

        buffer.removeAll()
        state = .parsingMessage(size: messageSize)
    }

    /// Parse the message in the buffer and update the state machine.
    func parseMessage() throws -> SwiftCompilerMessage {
        let data = Data(buffer)
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        kind = try Kind(from: decoder)
    }
}

extension SwiftCompilerMessage.Kind: Decodable, Equatable {
    enum CodingKeys: CodingKey {
        case kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "began":
            self = try .began(BeganInfo(from: decoder))
        case "skipped":
            self = try .skipped(SkippedInfo(from: decoder))
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
extension SwiftCompilerMessage.Kind.BeganInfo: Decodable, Equatable {}
extension SwiftCompilerMessage.Kind.SkippedInfo: Decodable, Equatable {}
extension SwiftCompilerMessage.Kind.OutputInfo: Decodable, Equatable {}

private let newline = UInt8(ascii: "\n")
