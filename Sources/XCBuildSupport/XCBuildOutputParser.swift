/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import TSCBasic
import TSCUtility

/// Represents a message output by xcbuild.
public enum XCBuildMessage {
    public struct BuildDiagnosticInfo {
        public let message: String
    }

    public struct BuildCompletedInfo {
        public enum Result: String {
            case ok
            case failed
            case cancelled
            case aborted
        }

        public let result: Result
    }

    public struct BuildOutputInfo {
        let data: String
    }

    public struct DidUpdateProgressInfo {
        public let message: String
        public let percentComplete: Double
        public let showInLog: Bool
    }

    public struct TargetUpToDateInfo {
        public let guid: PIF.GUID
    }

    public struct TargetStartedInfo {
        public enum Kind: String {
            case native = "Native"
            case aggregate = "Aggregate"
            case external = "External"
            case packageProduct = "Package Product"
        }

        public let targetID: Int
        public let targetGUID: PIF.GUID
        public let targetName: String
        public let type: Kind
    }

    public struct TargetCompleteInfo {
        public let targetID: Int
    }

    public struct TaskUpToDateInfo {
        let targetID: Int?
        let taskSignature: String
        let parentTaskID: Int?
    }

    public struct TaskStartedInfo {
        let taskID: Int
        let targetID: Int?
        let taskSignature: String
        let parentTaskID: Int?
        let ruleInfo: String
        let interestingPath: AbsolutePath?
        let commandLineDisplayString: String?
        let executionDescription: String
    }

    public struct TaskDiagnosticInfo {
        let taskID: Int
        let targetID: Int?
        let message: String
    }

    public struct TaskOutputInfo {
        let taskID: Int
        let data: String
    }

    public struct TaskCompleteInfo {
        public enum Result: String {
            case success
            case failed
            case cancelled
        }

        let taskID: Int
        let result: Result
        let signalled: Bool
    }
    
    public struct TargetDiagnosticInfo {
        let targetID: Int
        let message: String
    }

    case buildStarted
    case buildDiagnostic(BuildDiagnosticInfo)
    case buildCompleted(BuildCompletedInfo)
    case buildOutput(BuildOutputInfo)
    case preparationComplete
    case didUpdateProgress(DidUpdateProgressInfo)
    case targetUpToDate(TargetUpToDateInfo)
    case targetStarted(TargetStartedInfo)
    case targetComplete(TargetCompleteInfo)
    case taskUpToDate(TaskUpToDateInfo)
    case taskStarted(TaskStartedInfo)
    case taskDiagnostic(TaskDiagnosticInfo)
    case taskOutput(TaskOutputInfo)
    case taskComplete(TaskCompleteInfo)
    case targetDiagnostic(TargetDiagnosticInfo)
}

/// Protocol for the parser delegate to get notified of parsing events.
public protocol XCBuildOutputParserDelegate: class {

    /// Called for each message parsed.
    func xcBuildOutputParser(_ parser: XCBuildOutputParser, didParse message: XCBuildMessage)

    /// Called on an un-expected parsing error. No more events will be received after that.
    func xcBuildOutputParser(_ parser: XCBuildOutputParser, didFailWith error: Error)
}

/// Parser for XCBuild output.
public final class XCBuildOutputParser {

    /// The underlying JSON message parser.
    private var jsonParser: JSONMessageStreamingParser<XCBuildOutputParser>!

    /// Whether the parser is in a failing state.
    private var hasFailed: Bool

    /// Delegate to notify of parsing events.
    public weak var delegate: XCBuildOutputParserDelegate? = nil

    /// Initializes the parser with a delegate to notify of parsing events.
    /// - Parameters:
    ///     - delegate: Delegate to notify of parsing events.
    public init(delegate: XCBuildOutputParserDelegate) {
        self.hasFailed = false
        self.delegate = delegate
        self.jsonParser = JSONMessageStreamingParser<XCBuildOutputParser>(delegate: self)
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

extension XCBuildOutputParser: JSONMessageStreamingParserDelegate {
    public func jsonMessageStreamingParser(
        _ parser: JSONMessageStreamingParser<XCBuildOutputParser>,
        didParse message: XCBuildMessage
    ) {
        guard !hasFailed else {
            return
        }

        delegate?.xcBuildOutputParser(self, didParse: message)
    }

    public func jsonMessageStreamingParser(
        _ parser: JSONMessageStreamingParser<XCBuildOutputParser>,
        didParseRawText text: String
    ) {
        // Don't do anything with raw text.
    }

    public func jsonMessageStreamingParser(
        _ parser: JSONMessageStreamingParser<XCBuildOutputParser>,
        didFailWith error: Error
    ) {
        delegate?.xcBuildOutputParser(self, didFailWith: error)
    }
}

extension XCBuildMessage.BuildDiagnosticInfo: Decodable, Equatable {}
extension XCBuildMessage.BuildCompletedInfo.Result: Decodable, Equatable {}
extension XCBuildMessage.BuildCompletedInfo: Decodable, Equatable {}
extension XCBuildMessage.BuildOutputInfo: Decodable, Equatable {}
extension XCBuildMessage.TargetUpToDateInfo: Decodable, Equatable {}
extension XCBuildMessage.TaskDiagnosticInfo: Decodable, Equatable {}
extension XCBuildMessage.TargetDiagnosticInfo: Decodable, Equatable {}

extension XCBuildMessage.DidUpdateProgressInfo: Decodable, Equatable {
    enum CodingKeys: String, CodingKey {
        case message
        case percentComplete
        case showInLog
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        percentComplete = try container.decodeDoubleOrString(forKey: .percentComplete)
        showInLog = try container.decodeBoolOrString(forKey: .showInLog)
    }
}

extension XCBuildMessage.TargetStartedInfo.Kind: Decodable, Equatable {}
extension XCBuildMessage.TargetStartedInfo: Decodable, Equatable {
    enum CodingKeys: String, CodingKey {
        case targetID = "id"
        case targetGUID = "guid"
        case targetName = "name"
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targetID = try container.decodeIntOrString(forKey: .targetID)
        targetGUID = try container.decode(PIF.GUID.self, forKey: .targetGUID)
        targetName = try container.decode(String.self, forKey: .targetName)
        type = try container.decode(Kind.self, forKey: .type)
    }
}

extension XCBuildMessage.TargetCompleteInfo: Decodable, Equatable {
    enum CodingKeys: String, CodingKey {
        case targetID = "id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targetID = try container.decodeIntOrString(forKey: .targetID)
    }
}

extension XCBuildMessage.TaskUpToDateInfo: Decodable, Equatable {
    enum CodingKeys: String, CodingKey {
        case targetID
        case taskSignature = "signature"
        case parentTaskID = "parentID"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targetID = try container.decodeIntOrStringIfPresent(forKey: .targetID)
        taskSignature = try container.decode(String.self, forKey: .taskSignature)
        parentTaskID = try container.decodeIntOrStringIfPresent(forKey: .parentTaskID)
    }
}

extension XCBuildMessage.TaskStartedInfo: Decodable, Equatable {
    enum CodingKeys: String, CodingKey {
        case taskID = "id"
        case targetID
        case taskSignature = "signature"
        case parentTaskID = "parentID"
        case ruleInfo
        case interestingPath
        case commandLineDisplayString
        case executionDescription
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskID = try container.decodeIntOrString(forKey: .taskID)
        targetID = try container.decodeIntOrStringIfPresent(forKey: .targetID)
        taskSignature = try container.decode(String.self, forKey: .taskSignature)
        parentTaskID = try container.decodeIntOrStringIfPresent(forKey: .parentTaskID)
        ruleInfo = try container.decode(String.self, forKey: .ruleInfo)
        interestingPath = try AbsolutePath(validatingOrNilIfEmpty: container.decodeIfPresent(String.self, forKey: .interestingPath))
        commandLineDisplayString = try container.decode(String.self, forKey: .commandLineDisplayString)
        executionDescription = try container.decode(String.self, forKey: .executionDescription)
    }
}

extension XCBuildMessage.TaskOutputInfo: Decodable, Equatable {
    enum CodingKeys: String, CodingKey {
        case taskID
        case data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskID = try container.decodeIntOrString(forKey: .taskID)
        data = try container.decode(String.self, forKey: .data)
    }
}

extension XCBuildMessage.TaskCompleteInfo.Result: Decodable, Equatable {}
extension XCBuildMessage.TaskCompleteInfo: Decodable, Equatable {
    enum CodingKeys: String, CodingKey {
        case taskID = "id"
        case result
        case signalled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskID = try container.decodeIntOrString(forKey: .taskID)
        result = try container.decode(Result.self, forKey: .result)
        signalled = try container.decode(Bool.self, forKey: .signalled)
    }
}

extension XCBuildMessage: Decodable, Equatable {
    enum CodingKeys: CodingKey {
        case kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "buildStarted":
            self = .buildStarted
        case "buildDiagnostic":
            self = try .buildDiagnostic(BuildDiagnosticInfo(from: decoder))
        case "buildCompleted":
            self = try .buildCompleted(BuildCompletedInfo(from: decoder))
        case "buildOutput":
            self = try .buildOutput(BuildOutputInfo(from: decoder))
        case "preparationComplete":
            self = .preparationComplete
        case "didUpdateProgress":
            self = try .didUpdateProgress(DidUpdateProgressInfo(from: decoder))
        case "targetUpToDate":
            self = try .targetUpToDate(TargetUpToDateInfo(from: decoder))
        case "targetStarted":
            self = try .targetStarted(TargetStartedInfo(from: decoder))
        case "targetComplete":
            self = try .targetComplete(TargetCompleteInfo(from: decoder))
        case "taskUpToDate":
            self = try .taskUpToDate(TaskUpToDateInfo(from: decoder))
        case "taskStarted":
            self = try .taskStarted(TaskStartedInfo(from: decoder))
        case "taskDiagnostic":
            self = try .taskDiagnostic(TaskDiagnosticInfo(from: decoder))
        case "taskOutput":
            self = try .taskOutput(TaskOutputInfo(from: decoder))
        case "taskComplete":
            self = try .taskComplete(TaskCompleteInfo(from: decoder))
        case "targetDiagnostic":
            self = try .targetDiagnostic(TargetDiagnosticInfo(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "invalid kind \(kind)")
        }
    }
}

fileprivate extension KeyedDecodingContainer {
    func decodeBoolOrString(forKey key: Key) throws -> Bool {
        do {
            return try decode(Bool.self, forKey: key)
        } catch {
            let string = try decode(String.self, forKey: key)
            guard let value = Bool(string) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Could not parse '\(string)' as Bool for key \(key)")
            }
            return value
        }
    }

    func decodeDoubleOrString(forKey key: Key) throws -> Double {
        do {
            return try decode(Double.self, forKey: key)
        } catch {
            let string = try decode(String.self, forKey: key)
            guard let value = Double(string) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Could not parse '\(string)' as Double for key \(key)")
            }
            return value
        }
    }

    func decodeIntOrString(forKey key: Key) throws -> Int {
        do {
            return try decode(Int.self, forKey: key)
        } catch {
            let string = try decode(String.self, forKey: key)
            guard let value = Int(string) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Could not parse '\(string)' as Int for key \(key)")
            }
            return value
        }
    }

    func decodeIntOrStringIfPresent(forKey key: Key) throws -> Int? {
        do {
            return try decodeIfPresent(Int.self, forKey: key)
        } catch {
            guard let string = try decodeIfPresent(String.self, forKey: key), !string.isEmpty else {
                return nil
            }
            guard let value = Int(string) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Could not parse '\(string)' as Int for key \(key)")
            }
            return value
        }
    }
}

fileprivate extension AbsolutePath {
    init?(validatingOrNilIfEmpty path: String?) throws {
        guard let path = path, !path.isEmpty else {
            return nil
        }
        try self.init(validating: path)
    }
}
