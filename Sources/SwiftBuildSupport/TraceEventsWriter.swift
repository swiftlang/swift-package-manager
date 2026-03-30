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

import SPMBuildCore
import SwiftBuild

extension TraceEventsWriter {
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

        var args: [String: ArgValue] = [:]
        args["description"] = .string(startedInfo.executionDescription)
        if let cmdLine = startedInfo.commandLineDisplayString {
            args["commandLine"] = .string(cmdLine)
        }
        args["result"] = .string("\(info.result)")
        addCompleteEvent(
            name: startedInfo.executionDescription,
            category: .build,
            startTime: startInstant,
            duration: endInstant - startInstant,
            processID: 1,
            threadID: lane,
            arguments: args
        )
    }
}
