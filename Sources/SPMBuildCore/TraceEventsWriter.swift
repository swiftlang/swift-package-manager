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

/// Streams trace events to a file in Trace Event JSON Array Format. The format is documented at:
/// https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU
public final class TraceEventsWriter {
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
        case manifest
        case resolution
        case fetch
        case planning
        case none = ""
    }

    package struct LaneID: Hashable, Comparable, Codable {
        package let rawValue: Int

        package init(rawValue: Int) {
            self.rawValue = rawValue
        }

        package static let metadata = LaneID(rawValue: 0)
        package static let firstTask = LaneID(rawValue: 1)

        // SwiftPM phase lanes (used with processID 0)
        package static let manifestCompile = LaneID(rawValue: 1)
        package static let manifestEvaluate = LaneID(rawValue: 2)
        package static let resolution = LaneID(rawValue: 3)
        package static let buildPlanning = LaneID(rawValue: 4)
        package static let firstFetch = LaneID(rawValue: 5)

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

        package func next() -> LaneID {
            LaneID(rawValue: rawValue + 1)
        }
    }

    package struct TaskID: Hashable {
        package let rawValue: Int

        package init(_ rawValue: Int) {
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

        package init(
            name: String,
            category: Category,
            phase: Phase,
            timestamp: Int64,
            duration: Int64,
            processID: Int,
            threadID: LaneID,
            arguments: [String: ArgValue]?
        ) {
            self.name = name
            self.category = category
            self.phase = phase
            self.timestamp = timestamp
            self.duration = duration
            self.processID = processID
            self.threadID = threadID
            self.arguments = arguments
        }

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
    package let buildStartTime: ContinuousClock.Instant
    package var laneAssignments: [TaskID: LaneID] = [:]
    package var availableLanes: [LaneID] = []
    package var nextLane: LaneID = .firstTask
    package var taskStartTimes: [TaskID: ContinuousClock.Instant] = [:]
    package var buildStartWallClock: Int64 // µs since epoch
    private var needsComma: Bool = false
    private var isClosed: Bool = false

    // Fetch lane management (used with processID 0 for SwiftPM phases)
    private var availableFetchLanes: [LaneID] = []
    private var nextFetchLane: LaneID = .firstFetch

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
        self.buildStartWallClock = Int64(Date().timeIntervalSince1970 * 1_000_000)
    }

    /// Record a complete event with an absolute start time and duration.
    package func addCompleteEvent(
        name: String,
        category: Category,
        startTime: ContinuousClock.Instant,
        duration: Duration,
        processID: Int,
        threadID: LaneID,
        arguments: [String: ArgValue]? = nil
    ) {
        let startMicroseconds = (startTime - buildStartTime).microseconds
        let durationMicroseconds = duration.microseconds
        appendEvent(TraceEvent(
            name: name,
            category: category,
            phase: .complete,
            timestamp: startMicroseconds,
            duration: durationMicroseconds,
            processID: processID,
            threadID: threadID,
            arguments: arguments
        ))
    }

    /// Acquire a fetch lane for concurrent package fetch events.
    package func acquireFetchLane() -> LaneID {
        if let reusedLane = availableFetchLanes.popLast() {
            return reusedLane
        }
        let lane = nextFetchLane
        nextFetchLane = nextFetchLane.next()
        return lane
    }

    /// Release a fetch lane back to the pool.
    package func releaseFetchLane(_ lane: LaneID) {
        let insertionIndex = availableFetchLanes.firstIndex(where: { $0 < lane }) ?? availableFetchLanes.endIndex
        availableFetchLanes.insert(lane, at: insertionIndex)
    }

    /// Import compiler time trace files (produced by `-time-trace`) found under the given directory
    /// and append their events to the trace, rebasing timestamps relative to the build start time.
    /// Per-file "Total ..." events are aggregated across all files and emitted under a "Totals" process.
    package func importCompilerTimeTraces(under directory: AbsolutePath) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: directory.pathString),
            includingPropertiesForKeys: nil
        ) else { return }

        // Maps compiler PID → label derived from the trace file path
        // (e.g. "ArgumentParser/Argument.swift" from "ArgumentParser.build/Argument.swift.time-trace.json")
        var pidLabels: [Int: String] = [:]

        // Accumulate "Total ..." durations across all files for build-wide summary
        var aggregatedTotals: [String: Int64] = [:]

        let suffix = ".time-trace.json"
        let buildDirSuffix = ".build"

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent.hasSuffix(suffix) else {
                continue
            }

            guard let data = try? Data(contentsOf: fileURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let beginningOfTime = json["beginningOfTime"] as? Int,
                  let traceEvents = json["traceEvents"] as? [[String: Any]] else {
                continue
            }

            let offset = Int64(beginningOfTime) - buildStartWallClock

            // Derive a human-readable label from the file path:
            // "Module.build/File.swift.time-trace.json" → "Module/File.swift"
            let fileName = String(fileURL.lastPathComponent.dropLast(suffix.count))
            let parentDir = fileURL.deletingLastPathComponent().lastPathComponent
            let label: String
            if parentDir.hasSuffix(buildDirSuffix) {
                let moduleName = String(parentDir.dropLast(buildDirSuffix.count))
                label = "\(moduleName)/\(fileName)"
            } else {
                label = fileName
            }

            for event in traceEvents {
                guard let name = event["name"] as? String,
                      let ph = event["ph"] as? String, ph == "X",
                      let ts = event["ts"] as? Int,
                      let dur = event["dur"] as? Int,
                      let pid = event["pid"] as? Int,
                      let tid = event["tid"] as? Int else {
                    continue
                }

                // Aggregate "Total ..." events into build-wide sums instead of emitting per-file
                if name.hasPrefix("Total ") {
                    aggregatedTotals[name, default: 0] += Int64(dur)
                    continue
                }

                if pidLabels[pid] == nil {
                    pidLabels[pid] = label
                }

                var args: [String: ArgValue]? = nil
                if let eventArgs = event["args"] as? [String: Any], !eventArgs.isEmpty {
                    var converted: [String: ArgValue] = [:]
                    for (key, value) in eventArgs {
                        if let s = value as? String {
                            converted[key] = .string(s)
                        } else if let i = value as? Int {
                            converted[key] = .int(i)
                        }
                    }
                    if !converted.isEmpty {
                        args = converted
                    }
                }

                appendEvent(TraceEvent(
                    name: name,
                    category: .none,
                    phase: .complete,
                    timestamp: offset + Int64(ts),
                    duration: Int64(dur),
                    processID: pid,
                    threadID: LaneID(rawValue: tid),
                    arguments: args
                ))
            }
        }

        // Emit process_name metadata for each compiler process
        for (pid, label) in pidLabels.sorted(by: { $0.key < $1.key }) {
            appendEvent(TraceEvent(
                name: "process_name", category: .none, phase: .metadata,
                timestamp: 0, duration: 0, processID: pid, threadID: .metadata,
                arguments: ["name": .string(label)]
            ))
        }

        // Emit aggregated totals under the "Totals" process (pid=2), each on its own lane,
        // sorted by duration descending so the biggest contributors appear first in Perfetto.
        let totalsProcessID = 2
        let sortedTotals = aggregatedTotals.sorted { $0.value > $1.value }
        for (index, (name, duration)) in sortedTotals.enumerated() {
            let lane = LaneID(rawValue: index + 1)
            appendEvent(TraceEvent(
                name: name,
                category: .none,
                phase: .complete,
                timestamp: 0,
                duration: duration,
                processID: totalsProcessID,
                threadID: lane,
                arguments: nil
            ))
            appendEvent(TraceEvent(
                name: "thread_name", category: .none, phase: .metadata,
                timestamp: 0, duration: 0, processID: totalsProcessID, threadID: lane,
                arguments: ["name": .string(name)]
            ))
            appendEvent(TraceEvent(
                name: "thread_sort_index", category: .none, phase: .metadata,
                timestamp: 0, duration: 0, processID: totalsProcessID, threadID: lane,
                arguments: ["sort_index": .int(index)]
            ))
        }
        if !sortedTotals.isEmpty {
            appendEvent(TraceEvent(
                name: "process_name", category: .none, phase: .metadata,
                timestamp: 0, duration: 0, processID: totalsProcessID, threadID: .metadata,
                arguments: ["name": .string("Totals")]
            ))
            appendEvent(TraceEvent(
                name: "process_sort_index", category: .none, phase: .metadata,
                timestamp: 0, duration: 0, processID: totalsProcessID, threadID: .metadata,
                arguments: ["sort_index": .int(-1)]
            ))
        }
    }

    package func close() {
        guard !isClosed else { return }
        isClosed = true

        // Emit metadata for the Build process (pid=1)
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

        // Emit metadata for the SwiftPM phases process (pid=0)
        appendEvent(TraceEvent(
            name: "process_name", category: .none, phase: .metadata,
            timestamp: 0, duration: 0, processID: 0, threadID: .metadata,
            arguments: ["name": .string("SwiftPM")]
        ))

        for (lane, label) in [
            (LaneID.manifestCompile, "Manifest Compile"),
            (.manifestEvaluate, "Manifest Evaluate"),
            (.resolution, "Resolution"),
            (.buildPlanning, "Build Planning"),
        ] as [(LaneID, String)] {
            appendEvent(TraceEvent(
                name: "thread_name", category: .none, phase: .metadata,
                timestamp: 0, duration: 0, processID: 0, threadID: lane,
                arguments: ["name": .string(label)]
            ))
            appendEvent(TraceEvent(
                name: "thread_sort_index", category: .none, phase: .metadata,
                timestamp: 0, duration: 0, processID: 0, threadID: lane,
                arguments: ["sort_index": .int(lane.rawValue)]
            ))
        }

        // Emit metadata for dynamically assigned fetch lanes
        var fetchLane = LaneID.firstFetch
        while fetchLane < nextFetchLane {
            appendEvent(TraceEvent(
                name: "thread_name", category: .none, phase: .metadata,
                timestamp: 0, duration: 0, processID: 0, threadID: fetchLane,
                arguments: ["name": .string("Fetch \(fetchLane.rawValue - LaneID.firstFetch.rawValue + 1)")]
            ))
            appendEvent(TraceEvent(
                name: "thread_sort_index", category: .none, phase: .metadata,
                timestamp: 0, duration: 0, processID: 0, threadID: fetchLane,
                arguments: ["sort_index": .int(fetchLane.rawValue)]
            ))
            fetchLane = fetchLane.next()
        }

        fileHandle.write(Data("\n]\n".utf8))
        fileHandle.closeFile()
    }

    package func appendEvent(_ event: TraceEvent) {
        guard let data = try? encoder.encode(event) else { return }
        if needsComma {
            fileHandle.write(Data(",\n".utf8))
        }
        fileHandle.write(data)
        needsComma = true
    }
}

package extension Duration {
    var microseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1_000_000 + attoseconds / 1_000_000_000_000
    }
}
