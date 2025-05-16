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

struct ProgressTaskCounts {
    private(set) var pending: Int
    private(set) var running: Int
    private(set) var succeeded: Int
    private(set) var failed: Int
    private(set) var cancelled: Int
    private(set) var skipped: Int
    // Should be the sum of all other complete counts
    private(set) var completed: Int
    // Should be the sum of all other counts
    private(set) var total: Int
}

extension ProgressTaskCounts {
    var percentage: Double { Double(self.completed) / Double(self.total) }
}

extension ProgressTaskCounts {
    mutating func taskDiscovered() {
        self.pending += 1
        self.total += 1
    }

    mutating func taskStarted() {
        self.pending -= 1
        self.running += 1
    }

    mutating func taskSkipped() {
        self.pending -= 1
        self.skipped += 1
        self.completed += 1
    }

    mutating func taskCompleted(_ completion: ProgressTaskCompletion) {
        self.running -= 1
        self.completed += 1
        switch completion {
        case .succeeded:
            self.succeeded += 1
        case .failed:
            self.failed += 1
        case .cancelled:
            self.cancelled += 1
        case .skipped:
            self.skipped += 1
        }
    }
}

extension ProgressTaskCounts {
    static var zero: Self {
        .init(
            pending: 0,
            running: 0,
            succeeded: 0,
            failed: 0,
            cancelled: 0,
            skipped: 0,
            completed: 0,
            total: 0)
    }
}

extension ProgressTaskCounts: Equatable {}

extension ProgressTaskCounts: Hashable {}
