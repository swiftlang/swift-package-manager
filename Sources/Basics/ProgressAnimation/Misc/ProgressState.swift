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

struct ProgressState {
    var counts: ProgressTaskCounts
    var tasks: [ProgressTask.ID: ProgressTask]
}

extension ProgressState {
    init() {
        self.counts = .zero
        self.tasks = [:]
    }
}

enum ProgressTaskStateTMP {
    case discovered
    case started
    case completed(ContinuousClock.Duration)
}

extension ProgressState {
    mutating func update(
        id: ProgressTask.ID,
        name: String,
        state: ProgressTaskState,
        at time: ContinuousClock.Instant
    ) -> (ProgressTask, ProgressTaskStateTMP)? {
        switch state {
        case .discovered:
            guard self.tasks[id] == nil else {
                assertionFailure("unexpected duplicate discovery of task with id \(id)")
                return nil
            }
            let task = ProgressTask(
                id: id,
                name: name,
                start: time,
                state: .discovered)
            self.tasks[id] = task
            self.counts.taskDiscovered()
            return (task, .discovered)

        case .started:
            guard var task = self.tasks[id] else {
                assertionFailure("unexpected start of unknown task with id \(id)")
                return nil
            }
            guard task.state == .discovered else {
                assertionFailure("unexpected update to state \(state) of task with id \(id) in state \(task.state)")
                return nil
            }

            task.state = .started
            task.start = time
            self.tasks[id] = task
            self.counts.taskStarted()
            return (task, .started)

        case .completed(let completionEvent):
            guard var task = self.tasks[id] else {
                assertionFailure("unexpected update to state \(state) of unknown task with id \(id)")
                return nil
            }
            switch task.state {
            // Skipped is special, tasks can be skipped and never started
            case .discovered where completionEvent == .skipped:
                task.state = state
                task.end = time
                self.tasks[id] = task
                self.counts.taskSkipped()
                return (task, .completed(task.start.duration(to: time)))

            case .discovered:
                assertionFailure("unexpected update to state \(state) of not started task with id \(id)")
                return nil

            case .started:
                task.state = state
                task.end = time
                self.tasks[id] = task
                self.counts.taskCompleted(completionEvent)
                return (task, .completed(task.start.duration(to: time)))

            case .completed:
                // Already accounted for
                return nil
            }
        }
    }
}
