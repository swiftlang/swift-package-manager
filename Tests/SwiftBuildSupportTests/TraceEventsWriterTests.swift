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
import SPMBuildCore
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

    @Test
    func testAddCompleteEvent() throws {
        let events = try buildTrace { writer in
            let start = ContinuousClock.now
            let duration = Duration.milliseconds(42)
            writer.addCompleteEvent(
                name: "Compile test-package",
                category: .manifest,
                startTime: start,
                duration: duration,
                processID: 0,
                threadID: .manifestCompile,
                arguments: ["package": .string("test-package")]
            )
        }

        let completeEvents = events.filter { $0.phase == .complete }
        #expect(completeEvents.count == 1)

        let event = try #require(completeEvents.first)
        #expect(event.name == "Compile test-package")
        #expect(event.category == .manifest)
        #expect(event.processID == 0)
        #expect(event.threadID == .manifestCompile)
        #expect(event.duration >= 42000) // 42ms = 42000µs
        #expect(event.arguments?["package"] == .string("test-package"))
    }

    @Test
    func testSwiftPMPhaseCategories() throws {
        let events = try buildTrace { writer in
            let start = ContinuousClock.now

            writer.addCompleteEvent(
                name: "Compile root",
                category: .manifest,
                startTime: start,
                duration: .milliseconds(10),
                processID: 0,
                threadID: .manifestCompile
            )
            writer.addCompleteEvent(
                name: "Evaluate root",
                category: .manifest,
                startTime: start,
                duration: .milliseconds(5),
                processID: 0,
                threadID: .manifestEvaluate
            )
            writer.addCompleteEvent(
                name: "Resolve Dependencies",
                category: .resolution,
                startTime: start,
                duration: .milliseconds(100),
                processID: 0,
                threadID: .resolution
            )
            writer.addCompleteEvent(
                name: "Generate Build Plan",
                category: .planning,
                startTime: start,
                duration: .milliseconds(50),
                processID: 0,
                threadID: .buildPlanning
            )
        }

        let completeEvents = events.filter { $0.phase == .complete }
        #expect(completeEvents.count == 4)

        let categories = Set(completeEvents.map(\.category))
        #expect(categories.contains(.manifest))
        #expect(categories.contains(.resolution))
        #expect(categories.contains(.planning))

        // All SwiftPM phase events should use processID 0
        #expect(completeEvents.allSatisfy { $0.processID == 0 })
    }

    @Test
    func testFetchLaneManagement() throws {
        let events = try buildTrace { writer in
            let start = ContinuousClock.now

            // Acquire two fetch lanes concurrently
            let lane1 = writer.acquireFetchLane()
            let lane2 = writer.acquireFetchLane()

            #expect(lane1 == .firstFetch)
            #expect(lane2 == TraceEventsWriter.LaneID(rawValue: TraceEventsWriter.LaneID.firstFetch.rawValue + 1))

            writer.addCompleteEvent(
                name: "Fetch pkg-a",
                category: .fetch,
                startTime: start,
                duration: .milliseconds(20),
                processID: 0,
                threadID: lane1
            )
            writer.releaseFetchLane(lane1)

            // Reuse the released lane
            let lane3 = writer.acquireFetchLane()
            #expect(lane3 == lane1)

            writer.addCompleteEvent(
                name: "Fetch pkg-b",
                category: .fetch,
                startTime: start,
                duration: .milliseconds(30),
                processID: 0,
                threadID: lane2
            )
            writer.addCompleteEvent(
                name: "Download pkg-c",
                category: .fetch,
                startTime: start,
                duration: .milliseconds(15),
                processID: 0,
                threadID: lane3
            )
            writer.releaseFetchLane(lane2)
            writer.releaseFetchLane(lane3)
        }

        let fetchEvents = events.filter { $0.phase == .complete && $0.category == .fetch }
        #expect(fetchEvents.count == 3)

        // All fetch events should use processID 0
        #expect(fetchEvents.allSatisfy { $0.processID == 0 })
    }

    @Test
    func testMetadataIncludesSwiftPMProcess() throws {
        let events = try buildTrace { writer in
            // Just close to generate metadata
        }

        let metadataEvents = events.filter { $0.phase == .metadata }
        let processNames = metadataEvents.filter { $0.name == "process_name" }

        // Should have both "Build" (pid=1) and "SwiftPM" (pid=0) process names
        let buildProcess = processNames.first { $0.processID == 1 }
        let swiftpmProcess = processNames.first { $0.processID == 0 }
        #expect(buildProcess?.arguments?["name"] == .string("Build"))
        #expect(swiftpmProcess?.arguments?["name"] == .string("SwiftPM"))

        // Should have thread names for SwiftPM lanes
        let threadNames = metadataEvents.filter { $0.name == "thread_name" && $0.processID == 0 }
        let threadLabels = threadNames.compactMap { $0.arguments?["name"] }
        #expect(threadLabels.contains(.string("Manifest Compile")))
        #expect(threadLabels.contains(.string("Manifest Evaluate")))
        #expect(threadLabels.contains(.string("Resolution")))
        #expect(threadLabels.contains(.string("Build Planning")))
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
        return try JSONDecoder().decode([TraceEventsWriter.TraceEvent].self, from: data)
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
