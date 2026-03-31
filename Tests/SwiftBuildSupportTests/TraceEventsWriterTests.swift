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
    func testImportCompilerTimeTraces() throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("trace-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let knownWallClock: Int64 = 1_000_000_000

        // Create Module.build directory
        let moduleBuildDir = tmpDir.appendingPathComponent("Module.build")
        try FileManager.default.createDirectory(at: moduleBuildDir, withIntermediateDirectories: true)

        // File A: beginningOfTime = knownWallClock + 1000
        let traceA: [String: Any] = [
            "beginningOfTime": knownWallClock + 1000,
            "traceEvents": [
                ["pid": 100, "tid": 1, "ts": 100, "ph": "X", "dur": 50, "name": "Parse", "args": [:] as [String: Any]],
                ["pid": 100, "tid": 1, "ts": 200, "ph": "X", "dur": 30, "name": "Sema", "args": [:] as [String: Any]],
            ] as [[String: Any]],
        ]
        try JSONSerialization.data(withJSONObject: traceA)
            .write(to: moduleBuildDir.appendingPathComponent("A.time-trace.json"))

        // File B: beginningOfTime = knownWallClock + 1500
        let traceB: [String: Any] = [
            "beginningOfTime": knownWallClock + 1500,
            "traceEvents": [
                ["pid": 200, "tid": 1, "ts": 50, "ph": "X", "dur": 20, "name": "Parse", "args": [:] as [String: Any]],
                ["pid": 200, "tid": 1, "ts": 150, "ph": "X", "dur": 40, "name": "SILGen", "args": [:] as [String: Any]],
            ] as [[String: Any]],
        ]
        try JSONSerialization.data(withJSONObject: traceB)
            .write(to: moduleBuildDir.appendingPathComponent("B.time-trace.json"))

        let events = try buildTrace { writer in
            writer.buildStartWallClock = knownWallClock
            let path = try Basics.AbsolutePath(validating: tmpDir.path)
            writer.importCompilerTimeTraces(under: path)
        }

        let compilerEvents = events.filter { $0.phase == .complete }
        #expect(compilerEvents.count == 4)

        // File A events: offset = 1000, so ts: 1000+100=1100, 1000+200=1200
        let parseA = try #require(compilerEvents.first { $0.name == "Parse" && $0.processID == 100 })
        #expect(parseA.timestamp == 1100)
        #expect(parseA.duration == 50)

        let sema = try #require(compilerEvents.first { $0.name == "Sema" })
        #expect(sema.timestamp == 1200)
        #expect(sema.duration == 30)

        // File B events: offset = 1500, so ts: 1500+50=1550, 1500+150=1650
        let parseB = try #require(compilerEvents.first { $0.name == "Parse" && $0.processID == 200 })
        #expect(parseB.timestamp == 1550)
        #expect(parseB.duration == 20)

        let silgen = try #require(compilerEvents.first { $0.name == "SILGen" })
        #expect(silgen.timestamp == 1650)
        #expect(silgen.duration == 40)
    }

    @Test
    func testImportCompilerTimeTracesAggregatesTotals() throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("trace-import-total-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let knownWallClock: Int64 = 1_000_000_000

        // Two files, each with "Total SemanticAnalysis" — should be summed
        let traceA: [String: Any] = [
            "beginningOfTime": knownWallClock + 1000,
            "traceEvents": [
                ["pid": 100, "tid": 1, "ts": 100, "ph": "X", "dur": 50, "name": "Parse", "args": [:] as [String: Any]],
                ["pid": 100, "tid": 1, "ts": 200, "ph": "X", "dur": 300, "name": "Total SemanticAnalysis", "args": [:] as [String: Any]],
            ] as [[String: Any]],
        ]
        let traceB: [String: Any] = [
            "beginningOfTime": knownWallClock + 1500,
            "traceEvents": [
                ["pid": 200, "tid": 1, "ts": 50, "ph": "X", "dur": 20, "name": "Parse", "args": [:] as [String: Any]],
                ["pid": 200, "tid": 1, "ts": 100, "ph": "X", "dur": 500, "name": "Total SemanticAnalysis", "args": [:] as [String: Any]],
                ["pid": 200, "tid": 1, "ts": 700, "ph": "X", "dur": 100, "name": "Total SILGeneration", "args": [:] as [String: Any]],
            ] as [[String: Any]],
        ]
        try JSONSerialization.data(withJSONObject: traceA)
            .write(to: tmpDir.appendingPathComponent("A.time-trace.json"))
        try JSONSerialization.data(withJSONObject: traceB)
            .write(to: tmpDir.appendingPathComponent("B.time-trace.json"))

        let events = try buildTrace { writer in
            writer.buildStartWallClock = knownWallClock
            let path = try Basics.AbsolutePath(validating: tmpDir.path)
            writer.importCompilerTimeTraces(under: path)
        }

        let completeEvents = events.filter { $0.phase == .complete }

        // Per-file "Total" events should NOT appear under compiler PIDs
        #expect(!completeEvents.contains { $0.processID == 100 && $0.name.hasPrefix("Total ") })
        #expect(!completeEvents.contains { $0.processID == 200 && $0.name.hasPrefix("Total ") })

        // Aggregated totals should appear under processID 2 ("Totals")
        let totals = completeEvents.filter { $0.processID == 2 }
        #expect(totals.count == 2)

        let sema = try #require(totals.first { $0.name == "Total SemanticAnalysis" })
        #expect(sema.duration == 800) // 300 + 500

        let silgen = try #require(totals.first { $0.name == "Total SILGeneration" })
        #expect(silgen.duration == 100)

        // "Totals" process_name metadata should exist
        let metaEvents = events.filter { $0.phase == .metadata }
        let totalsProcess = metaEvents.first { $0.name == "process_name" && $0.processID == 2 }
        #expect(totalsProcess?.arguments?["name"] == .string("Totals"))
    }

    @Test
    func testImportCompilerTimeTracesEmptyDirectory() throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("trace-import-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let events = try buildTrace { writer in
            let path = try Basics.AbsolutePath(validating: tmpDir.path)
            writer.importCompilerTimeTraces(under: path)
        }

        let compilerEvents = events.filter { $0.phase == .complete }
        #expect(compilerEvents.isEmpty)
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
