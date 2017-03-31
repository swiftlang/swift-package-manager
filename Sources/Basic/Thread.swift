/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

/// This class bridges the gap between OSX and Linux Foundation Threading API.
/// It provides closure based execution and a join method to block the calling thread
/// until the thread is finished executing.
final public class Thread {

    /// The thread implementation which is Foundation.Thread on Linux and
    /// a Thread subclass which provides closure support on OSX.
    private var thread: ThreadImpl!

    /// Condition variable to support blocking other threads using join when this thread has not finished executing.
    private var finishedCondition: Condition

    /// A boolean variable to track if this thread has finished executing its task.
    private var isFinished: Bool

    /// Creates an instance of thread class with closure to be executed when start() is called.
    public init(task: @escaping () -> Void) {
        isFinished = false
        finishedCondition = Condition()

        // Wrap the task with condition notifying any other threads blocked due to this thread.
        // Capture self weakly to avoid reference cycle. In case Thread is deinited before the task
        // runs, skip the use of finishedCondition.
        let theTask = { [weak self] in
            if let strongSelf = self {
                precondition(!strongSelf.isFinished)
                strongSelf.finishedCondition.whileLocked {
                    task()
                    strongSelf.isFinished = true
                    strongSelf.finishedCondition.broadcast()
                }
            } else {
                // If the containing thread has been destroyed, we can ignore the finished condition and just run the
                // task.
                task()
            }
        }

        self.thread = ThreadImpl(block: theTask)
    }

    /// Starts the thread execution.
    public func start() {
        thread.start()
    }

    /// Blocks the calling thread until this thread is finished execution.
    public func join() {
        finishedCondition.whileLocked {
            while !isFinished {
                finishedCondition.wait()
            }
        }
    }
}

#if os(macOS)
/// A helper subclass of Foundation's Thread with closure support.
final private class ThreadImpl: Foundation.Thread {

    /// The task to be executed.
    private let task: () -> Void

    override func main() {
        task()
    }

    init(block task: @escaping () -> Void) {
        self.task = task
    }
}
#else
// Thread on Linux supports closure so just use it directly.
typealias ThreadImpl = Foundation.Thread
#endif
