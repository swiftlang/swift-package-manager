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
@_spi(Testing)
import SwiftBuild
import SwiftBuildSupport

import TSCBasic
import _InternalTestSupport


@Suite
struct SwiftBuildSystemMessageHandlerTests {
    private func createMessageHandler(
        _ logLevel: Basics.Diagnostic.Severity = .warning
    ) -> (handler: SwiftBuildSystemMessageHandler, outputStream: BufferedOutputByteStream, observability: TestingObservability) {
        let outputStream = BufferedOutputByteStream()
        let observability = ObservabilitySystem.makeForTesting(outputStream: outputStream)

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
            .taskStartedInfo(),
            .taskCompleteInfo(),
            .buildCompletedInfo()
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
        let (messageHandler, _, observability) = createMessageHandler()

        let events: [SwiftBuildMessage] = [
            .taskStartedInfo(taskSignature: "simple-diagnostic"),
            .diagnosticInfo(locationContext2: .init(taskSignature: "simple-diagnostic"), message: "Simple diagnostic", appendToOutputStream: true),
            .taskCompleteInfo(taskSignature: "simple-diagnostic", result: .failed) // Handler only emits when a task is completed.
        ]

        for event in events {
            _ = try messageHandler.emitEvent(event)
        }

        #expect(observability.hasErrorDiagnostics)

        try expectDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: "Simple diagnostic", severity: .error)
        }
    }

    @Test
    func testManyDiagnosticsReported() throws {
        let (messageHandler, _, observability) = createMessageHandler()

        let events: [SwiftBuildMessage] = [
            .taskStartedInfo(taskID: 1, taskSignature: "simple-diagnostic"),
            .diagnosticInfo(
                locationContext2: .init(taskSignature: "simple-diagnostic"),
                message: "Simple diagnostic",
                appendToOutputStream: true
            ),
            .taskStartedInfo(taskID: 2, taskSignature: "another-diagnostic"),
            .taskStartedInfo(taskID: 3, taskSignature: "warning-diagnostic"),
            .diagnosticInfo(
                kind: .warning,
                locationContext2: .init(taskSignature: "warning-diagnostic"),
                message: "Warning diagnostic",
                appendToOutputStream: true
            ),
            .taskCompleteInfo(taskID: 1, taskSignature: "simple-diagnostic", result: .failed),
            .diagnosticInfo(
                kind: .warning,
                locationContext2: .init(taskSignature: "warning-diagnostic"),
                message: "Another warning diagnostic",
                appendToOutputStream: true
            ),
            .taskCompleteInfo(taskID: 3, taskSignature: "warning-diagnostic", result: .success),
            .diagnosticInfo(
                kind: .note,
                locationContext2: .init(taskSignature: "another-diagnostic"),
                message: "Another diagnostic",
                appendToOutputStream: true
            ),
            .taskCompleteInfo(taskID: 2, taskSignature: "another-diagnostic", result: .failed)
        ]

        for event in events {
            _ = try messageHandler.emitEvent(event)
        }

        #expect(observability.hasErrorDiagnostics)

        try expectDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: "Simple diagnostic", severity: .error)
            result.check(diagnostic: "Another diagnostic", severity: .debug)
            result.check(diagnostic: "Another warning diagnostic", severity: .warning)
            result.check(diagnostic: "Warning diagnostic", severity: .warning)
        }
    }

    @Test
    func testCompilerOutputDiagnosticsWithoutDuplicatedLogging() throws {
        let (messageHandler, outputStream, observability) = createMessageHandler()

        let simpleDiagnosticString: String = "[error]: Simple diagnostic\n"
        let simpleOutputInfo: SwiftBuildMessage = .outputInfo(
            data: data(simpleDiagnosticString),
            locationContext: .task(taskID: 1, targetID: 1),
            locationContext2: .init(targetID: 1, taskSignature: "simple-diagnostic")
        )

        let warningDiagnosticString: String = "[warning]: Warning diagnostic\n"
        let warningOutputInfo: SwiftBuildMessage = .outputInfo(
            data: data(warningDiagnosticString),
            locationContext: .task(taskID: 3, targetID: 1),
            locationContext2: .init(targetID: 1, taskSignature: "warning-diagnostic")
        )

        let anotherDiagnosticString = "[note]: Another diagnostic\n"
        let anotherOutputInfo: SwiftBuildMessage = .outputInfo(
            data: data(anotherDiagnosticString),
            locationContext: .task(taskID: 2, targetID: 1),
            locationContext2: .init(targetID: 1, taskSignature: "another-diagnostic")
        )

        let anotherWarningDiagnosticString: String = "[warning]: Another warning diagnostic\n"
        let anotherWarningOutputInfo: SwiftBuildMessage = .outputInfo(
            data: data(anotherWarningDiagnosticString),
            locationContext: .task(taskID: 3, targetID: 1),
            locationContext2: .init(targetID: 1, taskSignature: "warning-diagnostic")
        )

        let events: [SwiftBuildMessage] = [
            .taskStartedInfo(taskID: 1, taskSignature: "simple-diagnostic"),
            .diagnosticInfo(
                locationContext2: .init(taskSignature: "simple-diagnostic"),
                message: "Simple diagnostic",
                appendToOutputStream: true
            ),
            .taskStartedInfo(taskID: 2, taskSignature: "another-diagnostic"),
            .taskStartedInfo(taskID: 3, taskSignature: "warning-diagnostic"),
            .diagnosticInfo(
                kind: .warning,
                locationContext2: .init(taskSignature: "warning-diagnostic"),
                message: "Warning diagnostic",
                appendToOutputStream: true
            ),
            anotherWarningOutputInfo,
            simpleOutputInfo,
            .taskCompleteInfo(taskID: 1, taskSignature: "simple-diagnostic"),
            .diagnosticInfo(
                kind: .warning,
                locationContext2: .init(taskSignature: "warning-diagnostic"),
                message: "Another warning diagnostic",
                appendToOutputStream: true
            ),
            warningOutputInfo,
            .taskCompleteInfo(taskID: 3, taskSignature: "warning-diagnostic"),
            .diagnosticInfo(
                kind: .note,
                locationContext2: .init(taskSignature: "another-diagnostic"),
                message: "Another diagnostic",
                appendToOutputStream: true
            ),
            anotherOutputInfo,
            .taskCompleteInfo(taskID: 2, taskSignature: "another-diagnostic")
        ]

        for event in events {
            _ = try messageHandler.emitEvent(event)
        }

        let outputText = outputStream.bytes.description
        #expect(outputText.contains("error"))
    }

    @Test
    func testDiagnosticOutputWhenOnlyWarnings() throws {
        let (messageHandler, outputStream, observability) = createMessageHandler()

        let events: [SwiftBuildMessage] = [
            .taskStartedInfo(taskID: 1, taskSignature: "simple-warning-diagnostic"),
            .diagnosticInfo(
                kind: .warning,
                locationContext2: .init(taskSignature: "simple-warning-diagnostic"),
                message: "Simple warning diagnostic",
                appendToOutputStream: true
            ),
            .taskCompleteInfo(taskID: 1, taskSignature: "simple-diagnostic", result: .success)
        ]

        for event in events {
            _ = try messageHandler.emitEvent(event)
        }

        #expect(observability.hasWarningDiagnostics)
    }
}

private func data(_ message: String) -> Data {
    Data(message.utf8)
}

/// Convenience inits for testing
extension SwiftBuildMessage {
    /// SwiftBuildMessage.TaskStartedInfo
    package static func taskStartedInfo(
        taskID: Int = 1,
        targetID: Int? = nil,
        taskSignature: String = "mock-task-signature",
        parentTaskID: Int? = nil,
        ruleInfo: String = "mock-rule",
        interestingPath: SwiftBuild.AbsolutePath? = nil,
        commandLineDisplayString: String? = nil,
        executionDescription: String = "execution description",
        serializedDiagnosticsPath: [SwiftBuild.AbsolutePath] = []
    ) -> SwiftBuildMessage {
        .taskStarted(
            .init(
                taskID: taskID,
                targetID: targetID,
                taskSignature: taskSignature,
                parentTaskID: parentTaskID,
                ruleInfo: ruleInfo,
                interestingPath: interestingPath,
                commandLineDisplayString: commandLineDisplayString,
                executionDescription: executionDescription,
                serializedDiagnosticsPaths: serializedDiagnosticsPath
            )
        )
    }

    /// SwiftBuildMessage.TaskCompletedInfo
    package static func taskCompleteInfo(
        taskID: Int = 1,
        taskSignature: String = "mock-task-signature",
        result: TaskCompleteInfo.Result = .success,
        signalled: Bool = false,
        metrics: TaskCompleteInfo.Metrics? = nil
    ) -> SwiftBuildMessage {
        .taskComplete(
            .init(
                taskID: taskID,
                taskSignature: taskSignature,
                result: result,
                signalled: signalled,
                metrics: metrics
            )
        )
    }

    /// SwiftBuildMessage.DiagnosticInfo
    package static func diagnosticInfo(
        kind: DiagnosticInfo.Kind = .error,
        location: DiagnosticInfo.Location = .unknown,
        locationContext: LocationContext = .task(taskID: 1, targetID: 1),
        locationContext2: LocationContext2 = .init(),
        component: DiagnosticInfo.Component = .default,
        message: String = "Mock diagnostic message.",
        optionName: String? = nil,
        appendToOutputStream: Bool = false,
        childDiagnostics: [DiagnosticInfo] = [],
        sourceRanges: [DiagnosticInfo.SourceRange] = [],
        fixIts: [SwiftBuildMessage.DiagnosticInfo.FixIt] = []
    ) -> SwiftBuildMessage {
        .diagnostic(
            .init(
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
        )
    }

    /// SwiftBuildMessage.BuildStartedInfo
    package static func buildStartedInfo(
        baseDirectory: SwiftBuild.AbsolutePath,
        derivedDataPath: SwiftBuild.AbsolutePath? = nil
    ) -> SwiftBuildMessage.BuildStartedInfo {
        .init(
            baseDirectory: baseDirectory,
            derivedDataPath: derivedDataPath
        )
    }

    /// SwiftBuildMessage.BuildCompleteInfo
    package static func buildCompletedInfo(
        result: BuildCompletedInfo.Result = .ok,
        metrics: BuildOperationMetrics? = nil
    ) -> SwiftBuildMessage {
        .buildCompleted(
            .init(
                result: result,
                metrics: metrics
            )
        )
    }

    /// SwiftBuildMessage.OutputInfo
    package static func outputInfo(
        data: Data,
        locationContext: LocationContext = .task(taskID: 1, targetID: 1),
        locationContext2: LocationContext2 = .init(targetID: 1, taskSignature: "mock-task-signature")
    ) -> SwiftBuildMessage {
        .output(
            .init(
                data: data,
                locationContext: locationContext,
                locationContext2: locationContext2
            )
        )
    }
}
