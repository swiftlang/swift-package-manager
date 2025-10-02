//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation

import class TSCUtility.JSONMessageStreamingParser
import protocol TSCUtility.JSONMessageStreamingParserDelegate

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
            public let outputs: [Output]?
            public let commandExecutable: String
            public let commandArguments: [String]

            public init(
                pid: Int,
                inputs: [String],
                outputs: [Output]?,
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
            public let outputs: [Output]?

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
        case abnormal(OutputInfo)
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
public protocol SwiftCompilerOutputParserDelegate: AnyObject {

    /// Called for each message parsed.
    func swiftCompilerOutputParser(_ parser: SwiftCompilerOutputParser, didParse message: SwiftCompilerMessage)

    /// Called on an un-expected parsing error. No more events will be received after that.
    func swiftCompilerOutputParser(_ parser: SwiftCompilerOutputParser, didFailWith error: Error)
}

/// Parser for the Swift compiler JSON output mode.
public final class SwiftCompilerOutputParser {

    /// The underlying JSON message parser.
    private var jsonParser: JSONMessageStreamingParser<SwiftCompilerOutputParser>!

    /// Whether the parser is in a failing state.
    private var hasFailed: Bool

    /// Name of the target the compiler is compiling.
    public let targetName: String

    /// Delegate to notify of parsing events.
    public weak var delegate: SwiftCompilerOutputParserDelegate?

    /// Initializes the parser with a delegate to notify of parsing events.
    /// - Parameters:
    ///     - targetName: The name of the target being built.
    ///     - delegate: Delegate to notify of parsing events.
    public init(targetName: String, delegate: SwiftCompilerOutputParserDelegate) {
        self.hasFailed = false
        self.targetName = targetName
        self.delegate = delegate

        let decoder = JSONDecoder.makeWithDefaults()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        jsonParser = JSONMessageStreamingParser<SwiftCompilerOutputParser>(delegate: self, decoder: decoder)
    }

    /// Parse the next bytes of the Swift compiler JSON output.
    /// - Note: If a parsing error is encountered, the delegate will be notified and the parser won't accept any further
    ///   input.
    public func parse<C>(bytes: C) where C: Collection, C.Element == UInt8 {
        guard !hasFailed else {
            return
        }

        jsonParser.parse(bytes: bytes)
    }
}

extension SwiftCompilerOutputParser: JSONMessageStreamingParserDelegate {
    public func jsonMessageStreamingParser(
        _ parser: JSONMessageStreamingParser<SwiftCompilerOutputParser>,
        didParse message: SwiftCompilerMessage
    ) {
        guard !hasFailed else {
            return
        }

        delegate?.swiftCompilerOutputParser(self, didParse: message)

        if case .signalled = message.kind {
            hasFailed = true
        }
    }

    public func jsonMessageStreamingParser(
        _ parser: JSONMessageStreamingParser<SwiftCompilerOutputParser>,
        didParseRawText text: String
    ) {
        guard !hasFailed else {
            return
        }

        let message = SwiftCompilerMessage(name: "unknown", kind: .unparsableOutput(text + "\n"))
        delegate?.swiftCompilerOutputParser(self, didParse: message)
    }

    public func jsonMessageStreamingParser(
        _ parser: JSONMessageStreamingParser<SwiftCompilerOutputParser>,
        didFailWith error: Error
    ) {
        delegate?.swiftCompilerOutputParser(self, didFailWith: error)
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
        case "abnormal-exit":
            self = try .abnormal(OutputInfo(from: decoder))
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
