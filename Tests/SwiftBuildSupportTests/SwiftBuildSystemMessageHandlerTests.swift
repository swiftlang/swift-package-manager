//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import struct SWBUtil.AbsolutePath
import Testing
import SwiftBuild
import SwiftBuildSupport

import TSCBasic
import _InternalTestSupport

@Suite
struct SwiftBuildSystemMessageHandlerTests {
    private func createMessageHandler(
        _ logLevel: Basics.Diagnostic.Severity = .warning
    ) -> (handler: SwiftBuildSystemMessageHandler, outputStream: BufferedOutputByteStream, observability: TestingObservability) {
        let observability = ObservabilitySystem.makeForTesting()
        let outputStream = BufferedOutputByteStream()

        let handler = SwiftBuildSystemMessageHandler(
            observabilityScope: observability.topScope,
            outputStream: outputStream,
            logLevel: logLevel
        )

        return (handler, outputStream, observability)
    }

    @Test
    func testNoDiagnosticsReported() throws {
        let (messageHandler, outputStream, observability) = createMessageHandler()

        let events: [SwiftBuildMessage] = [
            .taskStarted(.mock()),
            .taskComplete(.mock()),
            .buildCompleted(.mock())
        ]

        for event in events {
            _ = try messageHandler.emitEvent(event)
        }

        // Check output stream
        let output = outputStream.bytes.description
        #expect(!output.contains("error"))

        // Check observability diagnostics
        expectNoDiagnostics(observability.diagnostics)
    }

    @Test
    func testSimpleDiagnosticReported() throws {
        let (messageHandler, outputStream, observability) = createMessageHandler()

        let events: [SwiftBuildMessage] = [
            .taskStarted(.mock(
                taskID: 1,
                taskSignature: "mock-diagnostic"
            )),
            .diagnostic(.mock(
                kind: .error,
                locationContext: .mock(
                    taskID: 1,
                ),
                locationContext2: .mock(
                    taskSignature: "mock-diagnostic"
                ),
                message: "Simple diagnostic",
                appendToOutputStream: true)
            ),
            .taskComplete(.mock(taskID: 1)) // Handler only emits when a task is completed.
        ]

        for event in events {
            _ = try messageHandler.emitEvent(event)
        }

        #expect(observability.hasErrorDiagnostics)

        try expectDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: "Simple diagnostic", severity: .error)
        }
    }
}


extension SwiftBuildMessage.TaskStartedInfo {
    package static func mock(
        taskID: Int = 1,
        targetID: Int? = nil,
        taskSignature: String = "taskStartedSignature",
        parentTaskID: Int? = nil,
        ruleInfo: String = "ruleInfo",
        interestingPath: AbsolutePath? = nil,
        commandLineDisplayString: String? = nil,
        executionDescription: String = "",
        serializedDiagnosticsPaths: [AbsolutePath] = []
    ) -> SwiftBuildMessage.TaskStartedInfo {
        // Use JSON encoding/decoding as a workaround for lack of public initializer. Have it match the custom CodingKeys as described in
        struct MockData: Encodable {
            let id: Int
            let targetID: Int?
            let signature: String
            let parentID: Int?
            let ruleInfo: String
            let interestingPath: String?
            let commandLineDisplayString: String?
            let executionDescription: String
            let serializedDiagnosticsPaths: [String]
        }

        let mockData = MockData(
            id: taskID,
            targetID: targetID,
            signature: taskSignature,
            parentID: parentTaskID,
            ruleInfo: ruleInfo,
            interestingPath: interestingPath?.path.str,
            commandLineDisplayString: commandLineDisplayString,
            executionDescription: executionDescription,
            serializedDiagnosticsPaths: serializedDiagnosticsPaths.map { $0.path.str }
        )

        let data = try! JSONEncoder().encode(mockData)
        return try! JSONDecoder().decode(SwiftBuildMessage.TaskStartedInfo.self, from: data)
    }
}

// MARK: - DiagnosticInfo

extension SwiftBuildMessage.DiagnosticInfo {
    package static func mock(
        kind: Kind = .warning,
        location: Location = .unknown,
        locationContext: SwiftBuildMessage.LocationContext = .mock(),
        locationContext2: SwiftBuildMessage.LocationContext2 = .mock(),
        component: Component = .default,
        message: String = "Test diagnostic message",
        optionName: String? = nil,
        appendToOutputStream: Bool = false,
        childDiagnostics: [SwiftBuildMessage.DiagnosticInfo] = [],
        sourceRanges: [SourceRange] = [],
        fixIts: [FixIt] = []
    ) -> SwiftBuildMessage.DiagnosticInfo {
        struct MockData: Encodable {
            let kind: Kind
            let location: Location
            let locationContext: SwiftBuildMessage.LocationContext
            let locationContext2: SwiftBuildMessage.LocationContext2
            let component: Component
            let message: String
            let optionName: String?
            let appendToOutputStream: Bool
            let childDiagnostics: [SwiftBuildMessage.DiagnosticInfo]
            let sourceRanges: [SourceRange]
            let fixIts: [FixIt]
        }

        let mockData = MockData(
            kind: kind,
            location: location,
            locationContext: locationContext,
            locationContext2: locationContext2,
            component: component,
            message: message,
            optionName: optionName,
            appendToOutputStream: appendToOutputStream,
            childDiagnostics: childDiagnostics,
            sourceRanges: sourceRanges,
            fixIts: fixIts
        )

        let data = try! JSONEncoder().encode(mockData)
        return try! JSONDecoder().decode(SwiftBuildMessage.DiagnosticInfo.self, from: data)
    }
}

extension SwiftBuildMessage.LocationContext {
    package static func mock(
        taskID: Int = 1,
        targetID: Int = 1
    ) -> Self {
        return .task(taskID: taskID, targetID: targetID)
    }

    package static func mockTarget(targetID: Int = 1) -> Self {
        return .target(targetID: targetID)
    }

    package static func mockGlobalTask(taskID: Int = 1) -> Self {
        return .globalTask(taskID: taskID)
    }

    package static func mockGlobal() -> Self {
        return .global
    }
}

extension SwiftBuildMessage.DiagnosticInfo.Location {
    package static func mockPath(
        _ path: String = "/mock/file.swift",
        line: Int = 10,
        column: Int? = 5
    ) -> Self {
        return .path(path, fileLocation: .textual(line: line, column: column))
    }

    package static func mockPathOnly(_ path: String = "/mock/file.swift") -> Self {
        return .path(path, fileLocation: nil)
    }

    package static func mockObject(
        path: String = "/mock/file.swift",
        identifier: String = "mock-identifier"
    ) -> Self {
        return .path(path, fileLocation: .object(identifier: identifier))
    }

    package static func mockBuildSettings(names: [String] = ["MOCK_SETTING"]) -> Self {
        return .buildSettings(names: names)
    }

    package static func mockBuildFiles(
        buildFileGUIDs: [String] = ["BUILD_FILE_1"],
        buildPhaseGUIDs: [String] = ["BUILD_PHASE_1"],
        targetGUID: String = "TARGET_GUID"
    ) -> Self {
        let buildFiles = zip(buildFileGUIDs, buildPhaseGUIDs).map {
            SwiftBuildMessage.DiagnosticInfo.Location.BuildFileAndPhase.mock(
                buildFileGUID: $0,
                buildPhaseGUID: $1
            )
        }
        return .buildFiles(buildFiles, targetGUID: targetGUID)
    }
}

extension SwiftBuildMessage.DiagnosticInfo.Location.BuildFileAndPhase {
    package static func mock(
        buildFileGUID: String = "BUILD_FILE_GUID",
        buildPhaseGUID: String = "BUILD_PHASE_GUID"
    ) -> Self {
        struct MockData: Encodable {
            let buildFileGUID: String
            let buildPhaseGUID: String
        }

        let mockData = MockData(
            buildFileGUID: buildFileGUID,
            buildPhaseGUID: buildPhaseGUID
        )

        let data = try! JSONEncoder().encode(mockData)
        return try! JSONDecoder().decode(SwiftBuildMessage.DiagnosticInfo.Location.BuildFileAndPhase.self, from: data)
    }
}

extension SwiftBuildMessage.DiagnosticInfo.SourceRange {
    package static func mock(
        path: String = "/mock/file.swift",
        startLine: Int = 10,
        startColumn: Int = 5,
        endLine: Int = 10,
        endColumn: Int = 20
    ) -> Self {
        struct MockData: Encodable {
            let path: String
            let startLine: Int
            let startColumn: Int
            let endLine: Int
            let endColumn: Int
        }

        let mockData = MockData(
            path: path,
            startLine: startLine,
            startColumn: startColumn,
            endLine: endLine,
            endColumn: endColumn
        )

        let data = try! JSONEncoder().encode(mockData)
        return try! JSONDecoder().decode(SwiftBuildMessage.DiagnosticInfo.SourceRange.self, from: data)
    }
}

extension SwiftBuildMessage.DiagnosticInfo.FixIt {
    package static func mock(
        sourceRange: SwiftBuildMessage.DiagnosticInfo.SourceRange = .mock(),
        textToInsert: String = "fix text"
    ) -> Self {
        struct MockData: Encodable {
            let sourceRange: SwiftBuildMessage.DiagnosticInfo.SourceRange
            let textToInsert: String
        }

        let mockData = MockData(
            sourceRange: sourceRange,
            textToInsert: textToInsert
        )

        let data = try! JSONEncoder().encode(mockData)
        return try! JSONDecoder().decode(SwiftBuildMessage.DiagnosticInfo.FixIt.self, from: data)
    }
}

extension SwiftBuildMessage.LocationContext2 {
    package static func mock(
        targetID: Int? = nil,
        taskSignature: String? = nil
    ) -> Self {
        struct MockData: Encodable {
            let targetID: Int?
            let taskSignature: String?
        }

        let mockData = MockData(
            targetID: targetID,
            taskSignature: taskSignature
        )

        let data = try! JSONEncoder().encode(mockData)
        return try! JSONDecoder().decode(SwiftBuildMessage.LocationContext2.self, from: data)
    }
}

// MARK: - TaskCompleteInfo

extension SwiftBuildMessage.TaskCompleteInfo {
    package static func mock(
        taskID: Int = 1,
        taskSignature: String = "mock-task-signature",
        result: Result = .success,
        signalled: Bool = false,
        metrics: Metrics? = nil
    ) -> SwiftBuildMessage.TaskCompleteInfo {
        struct MockData: Encodable {
            let id: Int
            let signature: String
            let result: Result
            let signalled: Bool
            let metrics: Metrics?
        }

        let mockData = MockData(
            id: taskID,
            signature: taskSignature,
            result: result,
            signalled: signalled,
            metrics: metrics
        )

        let data = try! JSONEncoder().encode(mockData)
        return try! JSONDecoder().decode(SwiftBuildMessage.TaskCompleteInfo.self, from: data)
    }
}

extension SwiftBuildMessage.TaskCompleteInfo.Metrics {
    package static func mock(
        utime: UInt64 = 100,
        stime: UInt64 = 50,
        maxRSS: UInt64 = 1024000,
        wcStartTime: UInt64 = 1000000,
        wcDuration: UInt64 = 150
    ) -> Self {
        struct MockData: Encodable {
            let utime: UInt64
            let stime: UInt64
            let maxRSS: UInt64
            let wcStartTime: UInt64
            let wcDuration: UInt64
        }

        let mockData = MockData(
            utime: utime,
            stime: stime,
            maxRSS: maxRSS,
            wcStartTime: wcStartTime,
            wcDuration: wcDuration
        )

        let data = try! JSONEncoder().encode(mockData)
        return try! JSONDecoder().decode(SwiftBuildMessage.TaskCompleteInfo.Metrics.self, from: data)
    }
}

// MARK: - TargetStartedInfo

extension SwiftBuildMessage.TargetStartedInfo {
    package static func mock(
        targetID: Int = 1,
        targetGUID: String = "MOCK_TARGET_GUID",
        targetName: String = "MockTarget",
        type: Kind = .native,
        projectName: String = "MockProject",
        projectPath: String = "/mock/project.xcodeproj",
        projectIsPackage: Bool = false,
        projectNameIsUniqueInWorkspace: Bool = true,
        configurationName: String = "Debug",
        configurationIsDefault: Bool = true,
        sdkroot: String? = "macosx"
    ) -> SwiftBuildMessage.TargetStartedInfo {
        struct MockData: Encodable {
            let id: Int
            let guid: String
            let name: String
            let type: Kind
            let projectName: String
            let projectPath: String
            let projectIsPackage: Bool
            let projectNameIsUniqueInWorkspace: Bool
            let configurationName: String
            let configurationIsDefault: Bool
            let sdkroot: String?
        }

        let mockData = MockData(
            id: targetID,
            guid: targetGUID,
            name: targetName,
            type: type,
            projectName: projectName,
            projectPath: projectPath,
            projectIsPackage: projectIsPackage,
            projectNameIsUniqueInWorkspace: projectNameIsUniqueInWorkspace,
            configurationName: configurationName,
            configurationIsDefault: configurationIsDefault,
            sdkroot: sdkroot
        )

        let data = try! JSONEncoder().encode(mockData)
        return try! JSONDecoder().decode(SwiftBuildMessage.TargetStartedInfo.self, from: data)
    }
}

// MARK: - BuildStartedInfo

extension SwiftBuildMessage.BuildStartedInfo {
    package static func mock(
        baseDirectory: String = "/mock/base",
        derivedDataPath: String? = "/mock/derived-data"
    ) -> SwiftBuildMessage.BuildStartedInfo {
        struct MockData: Encodable {
            let baseDirectory: String
            let derivedDataPath: String?
        }

        let mockData = MockData(
            baseDirectory: baseDirectory,
            derivedDataPath: derivedDataPath
        )

        let data = try! JSONEncoder().encode(mockData)
        return try! JSONDecoder().decode(SwiftBuildMessage.BuildStartedInfo.self, from: data)
    }
}

// MARK: - BuildCompletedInfo

extension SwiftBuildMessage.BuildCompletedInfo {
    package static func mock(
        result: Result = .ok,
        metrics: SwiftBuildMessage.BuildOperationMetrics? = nil
    ) -> SwiftBuildMessage.BuildCompletedInfo {
        struct MockData: Encodable {
            let result: Result
            let metrics: SwiftBuildMessage.BuildOperationMetrics?
        }

        let mockData = MockData(
            result: result,
            metrics: metrics
        )

        let data = try! JSONEncoder().encode(mockData)
        return try! JSONDecoder().decode(SwiftBuildMessage.BuildCompletedInfo.self, from: data)
    }
}

extension SwiftBuildMessage.BuildOperationMetrics {
    package static func mock(
        counters: [String: Int] = ["totalTasks": 10],
        taskCounters: [String: [String: Int]] = ["CompileSwift": ["count": 5]]
    ) -> Self {
        struct MockData: Encodable {
            let counters: [String: Int]
            let taskCounters: [String: [String: Int]]
        }

        let mockData = MockData(
            counters: counters,
            taskCounters: taskCounters
        )

        let data = try! JSONEncoder().encode(mockData)
        return try! JSONDecoder().decode(SwiftBuildMessage.BuildOperationMetrics.self, from: data)
    }
}

// MARK: - TaskOutputInfo

extension SwiftBuildMessage.TaskOutputInfo {
    package static func mock(
        taskID: Int = 1,
        data: String = "Mock task output"
    ) -> SwiftBuildMessage.TaskOutputInfo {
        struct MockData: Encodable {
            let taskID: Int
            let data: String
        }

        let mockData = MockData(
            taskID: taskID,
            data: data
        )

        let data = try! JSONEncoder().encode(mockData)
        return try! JSONDecoder().decode(SwiftBuildMessage.TaskOutputInfo.self, from: data)
    }
}

// MARK: - BuildDiagnosticInfo

extension SwiftBuildMessage.BuildDiagnosticInfo {
    package static func mock(
        message: String = "Mock build diagnostic"
    ) -> SwiftBuildMessage.BuildDiagnosticInfo {
        struct MockData: Encodable {
            let message: String
        }

        let mockData = MockData(
            message: message
        )

        let data = try! JSONEncoder().encode(mockData)
        return try! JSONDecoder().decode(SwiftBuildMessage.BuildDiagnosticInfo.self, from: data)
    }
}

// MARK: - TargetCompleteInfo

extension SwiftBuildMessage.TargetCompleteInfo {
    package static func mock(
        targetID: Int = 1
    ) -> SwiftBuildMessage.TargetCompleteInfo {
        struct MockData: Encodable {
            let id: Int
        }

        let mockData = MockData(
            id: targetID
        )

        let data = try! JSONEncoder().encode(mockData)
        return try! JSONDecoder().decode(SwiftBuildMessage.TargetCompleteInfo.self, from: data)
    }
}
