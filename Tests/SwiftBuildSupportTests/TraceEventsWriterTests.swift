//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Testing

import Basics
import Foundation
@_spi(Testing) import SwiftBuild
import SwiftBuildSupport

@Suite
struct TraceEventsWriterTests {
    @Test
    func testSingleTask() throws {
        let events = try buildTrace { writer in
            writer.taskStarted(.init(taskID: 1))
            writer.taskCompleted(
                .init(taskID: 1, result: .success),
                startedInfo: .init(taskID: 1, executionDescription: "Compiling main.swift")
            )
        }

        let taskEvents = events.filter { $0.phase == .complete }
        #expect(taskEvents.count == 1)

        let event = try #require(taskEvents.first)
        #expect(event.name == "Compiling main.swift")
        #expect(event.category == .build)
        #expect(event.processID == 1)
        #expect(event.threadID >= .firstTask)
        #expect(event.timestamp > 0)
        #expect(event.duration >= 0)
    }

    @Test
    func testConcurrentTasksGetSeparateLanes() throws {
        let events = try buildTrace { writer in
            writer.taskStarted(.init(taskID: 1))
            writer.taskStarted(.init(taskID: 2))
            writer.taskStarted(.init(taskID: 3))

            writer.taskCompleted(
                .init(taskID: 1, result: .success),
                startedInfo: .init(taskID: 1, executionDescription: "Task A")
            )
            writer.taskCompleted(
                .init(taskID: 2, result: .success),
                startedInfo: .init(taskID: 2, executionDescription: "Task B")
            )
            writer.taskCompleted(
                .init(taskID: 3, result: .success),
                startedInfo: .init(taskID: 3, executionDescription: "Task C")
            )
        }

        let taskEvents = events.filter { $0.phase == .complete }
        let lanes = Set(taskEvents.map(\.threadID))
        #expect(lanes.count == 3)
        #expect(lanes == Set([.init(rawValue: 1), .init(rawValue: 2), .init(rawValue: 3)]))
    }

    @Test
    func testLaneReuse() throws {
        let events = try buildTrace { writer in
            writer.taskStarted(.init(taskID: 1))
            writer.taskStarted(.init(taskID: 2))

            writer.taskCompleted(
                .init(taskID: 1, result: .success),
                startedInfo: .init(taskID: 1, executionDescription: "Task A")
            )

            writer.taskStarted(.init(taskID: 3))
            writer.taskCompleted(
                .init(taskID: 3, result: .success),
                startedInfo: .init(taskID: 3, executionDescription: "Task C")
            )
            writer.taskCompleted(
                .init(taskID: 2, result: .success),
                startedInfo: .init(taskID: 2, executionDescription: "Task B")
            )
        }

        let taskEvents = events.filter { $0.phase == .complete }
        let eventsByName = Dictionary(uniqueKeysWithValues: taskEvents.map { ($0.name, $0) })

        #expect(eventsByName["Task A"]?.threadID == .init(rawValue: 1))
        #expect(eventsByName["Task B"]?.threadID == .init(rawValue: 2))
        #expect(eventsByName["Task C"]?.threadID == .init(rawValue: 1))
    }

    @Test
    func testLowestLaneReusedFirst() throws {
        let events = try buildTrace { writer in
            writer.taskStarted(.init(taskID: 1))
            writer.taskStarted(.init(taskID: 2))
            writer.taskStarted(.init(taskID: 3))
            writer.taskStarted(.init(taskID: 4))

            writer.taskCompleted(
                .init(taskID: 3, result: .success),
                startedInfo: .init(taskID: 3, executionDescription: "Task C")
            )
            writer.taskCompleted(
                .init(taskID: 1, result: .success),
                startedInfo: .init(taskID: 1, executionDescription: "Task A")
            )

            writer.taskStarted(.init(taskID: 5))
            writer.taskCompleted(
                .init(taskID: 5, result: .success),
                startedInfo: .init(taskID: 5, executionDescription: "Task E")
            )

            writer.taskCompleted(
                .init(taskID: 2, result: .success),
                startedInfo: .init(taskID: 2, executionDescription: "Task B")
            )
            writer.taskCompleted(
                .init(taskID: 4, result: .success),
                startedInfo: .init(taskID: 4, executionDescription: "Task D")
            )
        }

        let taskEvents = events.filter { $0.phase == .complete }
        let eventsByName = Dictionary(uniqueKeysWithValues: taskEvents.map { ($0.name, $0) })

        #expect(eventsByName["Task E"]?.threadID == .init(rawValue: 1))
    }

    @Test
    func testArgsIncludeTaskMetadata() throws {
        let events = try buildTrace { writer in
            writer.taskStarted(.init(taskID: 1))
            writer.taskCompleted(
                .init(taskID: 1, result: .failed),
                startedInfo: .init(
                    taskID: 1,
                    executionDescription: "Compiling Foo.swift",
                    commandLineDisplayString: "/usr/bin/swiftc -c Foo.swift"
                )
            )
        }

        let taskEvent = try #require(events.first(where: { $0.phase == .complete }))

        #expect(taskEvent.arguments?["description"] == .string("Compiling Foo.swift"))
        #expect(taskEvent.arguments?["commandLine"] == .string("/usr/bin/swiftc -c Foo.swift"))
        #expect(taskEvent.arguments?["result"] == .string("failed"))
    }

    fileprivate func buildTrace(
        _ body: (TraceEventsWriter) throws -> Void
    ) throws -> [TraceEventsWriter.TraceEvent] {
        let tmpFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("trace-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let path = try Basics.AbsolutePath(validating: tmpFile.path)
        let writer = try TraceEventsWriter(path: path)
        try body(writer)
        writer.close()

        let data = try Data(contentsOf: tmpFile)
        let text = String(decoding: data, as: UTF8.self)
        let events = try JSONDecoder().decode([TraceEventsWriter.TraceEvent].self, from: data)

        return events
    }
}

extension SwiftBuildMessage.TaskStartedInfo {
    fileprivate init(
        taskID: Int = 0,
        executionDescription: String = "",
        commandLineDisplayString: String? = nil,
        ruleInfo: String = ""
    ) {
        self.init(
            taskID: taskID,
            targetID: nil,
            taskSignature: "",
            parentTaskID: nil,
            ruleInfo: ruleInfo,
            interestingPath: nil,
            commandLineDisplayString: commandLineDisplayString,
            executionDescription: executionDescription,
            serializedDiagnosticsPaths: []
        )
    }
}

extension SwiftBuildMessage.TaskCompleteInfo {
    fileprivate init(
        taskID: Int = 0,
        result: SwiftBuildMessage.TaskCompleteInfo.Result = .success
    ) {
        self.init(taskID: taskID, taskSignature: "", result: result, signalled: false, metrics: nil)
    }
}
