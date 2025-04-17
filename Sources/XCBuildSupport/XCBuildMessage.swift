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
        public let data: String
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
        public let targetID: Int?
        public let taskSignature: String
        public let parentTaskID: Int?
    }

    public struct TaskStartedInfo {
        public let taskID: Int
        public let targetID: Int?
        public let taskSignature: String
        public let parentTaskID: Int?
        public let ruleInfo: String
        public let interestingPath: AbsolutePath?
        public let commandLineDisplayString: String?
        public let executionDescription: String
    }

    public struct TaskDiagnosticInfo {
        public let taskID: Int
        public let targetID: Int?
        public let message: String
    }

    public struct TaskOutputInfo {
        public let taskID: Int
        public let data: String
    }

    public struct TaskCompleteInfo {
        public enum Result: String {
            case success
            case failed
            case cancelled
        }

        public let taskID: Int
        public let result: Result
        public let signalled: Bool
    }

    public struct TargetDiagnosticInfo {
        public let targetID: Int
        public let message: String
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
    case unknown
}

extension XCBuildMessage.BuildDiagnosticInfo: Codable, Equatable, Sendable {}
extension XCBuildMessage.BuildCompletedInfo.Result: Codable, Equatable, Sendable {}
extension XCBuildMessage.BuildCompletedInfo: Codable, Equatable, Sendable {}
extension XCBuildMessage.BuildOutputInfo: Codable, Equatable, Sendable {}
extension XCBuildMessage.TargetUpToDateInfo: Codable, Equatable, Sendable {}
extension XCBuildMessage.TaskDiagnosticInfo: Codable, Equatable, Sendable {}
extension XCBuildMessage.TargetDiagnosticInfo: Codable, Equatable, Sendable {}

extension XCBuildMessage.DidUpdateProgressInfo: Codable, Equatable, Sendable {
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

extension XCBuildMessage.TargetStartedInfo.Kind: Codable, Equatable, Sendable {}
extension XCBuildMessage.TargetStartedInfo: Codable, Equatable, Sendable {
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

extension XCBuildMessage.TargetCompleteInfo: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case targetID = "id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targetID = try container.decodeIntOrString(forKey: .targetID)
    }
}

extension XCBuildMessage.TaskUpToDateInfo: Codable, Equatable, Sendable {
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

extension XCBuildMessage.TaskStartedInfo: Codable, Equatable, Sendable {
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
        commandLineDisplayString = try container.decodeIfPresent(String.self, forKey: .commandLineDisplayString)
        executionDescription = try container.decode(String.self, forKey: .executionDescription)
    }
}

extension XCBuildMessage.TaskOutputInfo: Codable, Equatable, Sendable {
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

extension XCBuildMessage.TaskCompleteInfo.Result: Codable, Equatable, Sendable {}
extension XCBuildMessage.TaskCompleteInfo: Codable, Equatable, Sendable {
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

extension XCBuildMessage: Codable, Equatable, Sendable {
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
            self = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .buildStarted:
            try container.encode("buildStarted", forKey: .kind)
        case let .buildDiagnostic(info):
            try container.encode("buildDiagnostic", forKey: .kind)
            try info.encode(to: encoder)
        case let .buildCompleted(info):
            try container.encode("buildCompleted", forKey: .kind)
            try info.encode(to: encoder)
        case let .buildOutput(info):
            try container.encode("buildOutput", forKey: .kind)
            try info.encode(to: encoder)
        case .preparationComplete:
            try container.encode("preparationComplete", forKey: .kind)
        case let .didUpdateProgress(info):
            try container.encode("didUpdateProgress", forKey: .kind)
            try info.encode(to: encoder)
        case let .targetUpToDate(info):
            try container.encode("targetUpToDate", forKey: .kind)
            try info.encode(to: encoder)
        case let .targetStarted(info):
            try container.encode("targetStarted", forKey: .kind)
            try info.encode(to: encoder)
        case let .targetComplete(info):
            try container.encode("targetComplete", forKey: .kind)
            try info.encode(to: encoder)
        case let .taskUpToDate(info):
            try container.encode("taskUpToDate", forKey: .kind)
            try info.encode(to: encoder)
        case let .taskStarted(info):
            try container.encode("taskStarted", forKey: .kind)
            try info.encode(to: encoder)
        case let .taskDiagnostic(info):
            try container.encode("taskDiagnostic", forKey: .kind)
            try info.encode(to: encoder)
        case let .taskOutput(info):
            try container.encode("taskOutput", forKey: .kind)
            try info.encode(to: encoder)
        case let .taskComplete(info):
            try container.encode("taskComplete", forKey: .kind)
            try info.encode(to: encoder)
        case let .targetDiagnostic(info):
            try container.encode("targetDiagnostic", forKey: .kind)
            try info.encode(to: encoder)
        case .unknown:
            assertionFailure()
            break
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
