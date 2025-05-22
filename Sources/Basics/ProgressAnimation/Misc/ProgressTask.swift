//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// FIXME: use task tree
//struct ProgressTask {
//    var id: Int
//    var name: String
//    var childTasks: [ProgressTask.ID: ProgressTask]
//    var childTaskCounts: ProgressTaskCounts
//    var state: ProgressTaskState
//    var start: ContinuousClock.Instant
//    var end: ContinuousClock.Instant?
//}

struct ProgressTask {
    var id: Int
    var name: String
    var start: ContinuousClock.Instant
    var state: ProgressTaskState
    var end: ContinuousClock.Instant?
}

extension ProgressTask {
    var duration: ContinuousClock.Duration? {
        guard let end = self.end else { return nil }
        return self.start.duration(to: end)
    }
}

extension ProgressTask: Equatable { }

extension ProgressTask: Comparable {
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.start < rhs.start
    }
}

extension ProgressTask: Identifiable {}
