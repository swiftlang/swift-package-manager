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

import Basics
import Foundation
import SwiftBuild

/// Streams build task events to a file in Trace Event JSON Array Format. The format is documented at:
/// https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU
package final class TraceEventsWriter {
    package enum ArgValue: Codable, Equatable {
        case string(String)
        case int(Int)

        package func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let s): try container.encode(s)
            case .int(let i): try container.encode(i)
            }
        }

        package init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let i = try? container.decode(Int.self) {
                self = .int(i)
            } else {
                self = .string(try container.decode(String.self))
            }
        }
    }

    package enum Phase: String, Codable {
        case complete = "X"
        case metadata = "M"
    }

    package enum Category: String, Codable {
        case build
        case none = ""
    }

    package struct LaneID: Hashable, Comparable, Codable {
        package let rawValue: Int

        package init(rawValue: Int) {
            self.rawValue = rawValue
        }

        package static let metadata = LaneID(rawValue: 0)
        package static let firstTask = LaneID(rawValue: 1)

        package func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        package init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.rawValue = try container.decode(Int.self)
        }

        package static func < (lhs: LaneID, rhs: LaneID) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        func next() -> LaneID {
            LaneID(rawValue: rawValue + 1)
        }
    }

    struct TaskID: Hashable {
        let rawValue: Int

        init(_ rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    package struct TraceEvent: Codable, Equatable {
        package let name: String
        package let category: Category
        package let phase: Phase
        package let timestamp: Int64
        package let duration: Int64
        package let processID: Int
        package let threadID: LaneID
        package let arguments: [String: ArgValue]?

        enum CodingKeys: String, CodingKey {
            case name
            case category = "cat"
            case phase = "ph"
            case timestamp = "ts"
            case duration = "dur"
            case processID = "pid"
            case threadID = "tid"
            case arguments = "args"
        }
    }

    private let fileHandle: FileHandle
    private let encoder: JSONEncoder
    private let buildStartTime: ContinuousClock.Instant
    private var laneAssignments: [TaskID: LaneID] = [:]
    private var availableLanes: [LaneID] = []
    private var nextLane: LaneID = .firstTask
    private var taskStartTimes: [TaskID: ContinuousClock.Instant] = [:]
    private var needsComma: Bool = false

    package init(path: Basics.AbsolutePath) throws {
        let url = URL(fileURLWithPath: path.pathString)
        if !FileManager.default.fileExists(atPath: path.pathString) {
            FileManager.default.createFile(atPath: path.pathString, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        handle.write(Data("[\n".utf8))
        self.fileHandle = handle
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.buildStartTime = ContinuousClock.now
    }

    package func taskStarted(_ info: SwiftBuildMessage.TaskStartedInfo) {
        let taskID = TaskID(info.taskID)
        let lane: LaneID
        if let reusedLane = availableLanes.popLast() {
            lane = reusedLane
        } else {
            lane = nextLane
            nextLane = nextLane.next()
        }
        laneAssignments[taskID] = lane
        taskStartTimes[taskID] = .now
    }

    package func taskCompleted(
        _ info: SwiftBuildMessage.TaskCompleteInfo,
        startedInfo: SwiftBuildMessage.TaskStartedInfo,
        backtrace: String? = nil
    ) {
        let taskID = TaskID(info.taskID)
        let endInstant = ContinuousClock.now
        guard let lane = laneAssignments.removeValue(forKey: taskID),
              let startInstant = taskStartTimes.removeValue(forKey: taskID) else {
            return
        }

        // Return lane to the pool, maintaining descending order.
        let insertionIndex = availableLanes.firstIndex(where: { $0 < lane }) ?? availableLanes.endIndex
        availableLanes.insert(lane, at: insertionIndex)

        let startMicroseconds = (startInstant - buildStartTime).microseconds
        let durationMicroseconds = (endInstant - startInstant).microseconds

        var args: [String: ArgValue] = [:]
        args["description"] = .string(startedInfo.executionDescription)
        if let cmdLine = startedInfo.commandLineDisplayString {
            args["commandLine"] = .string(cmdLine)
        }
        if let backtrace, !backtrace.isEmpty {
            args["backtrace"] = .string(backtrace)
        }
        args["result"] = .string("\(info.result)")
        appendEvent(TraceEvent(
            name: startedInfo.executionDescription,
            category: .build,
            phase: .complete,
            timestamp: startMicroseconds,
            duration: durationMicroseconds,
            processID: 1,
            threadID: lane,
            arguments: args
        ))
    }

    package func close() {
        appendEvent(TraceEvent(
            name: "process_name", category: .none, phase: .metadata,
            timestamp: 0, duration: 0, processID: 1, threadID: .metadata,
            arguments: ["name": .string("Build")]
        ))

        var lane = LaneID.firstTask
        while lane < nextLane {
            appendEvent(TraceEvent(
                name: "thread_name", category: .none, phase: .metadata,
                timestamp: 0, duration: 0, processID: 1, threadID: lane,
                arguments: ["name": .string("Lane \(lane.rawValue)")]
            ))
            appendEvent(TraceEvent(
                name: "thread_sort_index", category: .none, phase: .metadata,
                timestamp: 0, duration: 0, processID: 1, threadID: lane,
                arguments: ["sort_index": .int(lane.rawValue)]
            ))
            lane = lane.next()
        }

        fileHandle.write(Data("\n]\n".utf8))
        fileHandle.closeFile()
    }

    private func appendEvent(_ event: TraceEvent) {
        guard let data = try? encoder.encode(event) else { return }
        if needsComma {
            fileHandle.write(Data(",\n".utf8))
        }
        fileHandle.write(data)
        needsComma = true
    }
}

private extension Duration {
    var microseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1_000_000 + attoseconds / 1_000_000_000_000
    }
}
