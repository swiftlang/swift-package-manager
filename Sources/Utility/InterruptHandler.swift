/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import libc
import enum POSIX.SystemError
import Basic

/// Interrupt signal handling global variables
private var wasInterrupted = false
private var wasInterruptedLock = Lock()
private var signalWatchingPipe: [Int32] = [0, 0]
private var oldAction = sigaction()

/// This class can be used by command line tools to install a handler which
/// should be called when a interrupt signal is delivered to the process.
public final class InterruptHandler {

    /// The thread which waits to be notified when a signal is received.
    let thread: Thread

    /// Start watching for interrupt signal and call the handler whenever the signal is received.
    public init(_ handler: @escaping () -> Void) throws {
        // Create a signal handler.
        let signalHandler: @convention(c)(Int32) -> Void = { _ in
            // Turn on the interrupt bool.
            wasInterruptedLock.withLock {
                wasInterrupted = true
            }
            // Write on pipe to notify the watching thread.
            var byte: UInt8 = 0
            write(signalWatchingPipe[1], &byte, 1)
        }
        var action = sigaction()
      #if os(macOS)
        action.__sigaction_u.__sa_handler = signalHandler
      #else
        action.__sigaction_handler = unsafeBitCast(
            signalHandler,
            to: sigaction.__Unnamed_union___sigaction_handler.self)
      #endif
        // Install the new handler.
        sigaction(SIGINT, &action, &oldAction)
        // Create pipe.
        let rv = libc.pipe(&signalWatchingPipe)
        guard rv == 0 else {
            throw SystemError.pipe(rv)
        }

        // This thread waits to be notified via pipe. If something is read from pipe, check the interrupt bool
        // and send termination signal to all spawned processes in the process group.
        thread = Thread {
            while true {
                var buf: Int8 = 0
                let n = read(signalWatchingPipe[0], &buf, 1)
                // Pipe closed, nothing to do.
                if n == 0 { break }
                // Read the value of wasInterrupted and set it to false.
                let wasInt = wasInterruptedLock.withLock { () -> Bool in
                    let oldValue = wasInterrupted
                    wasInterrupted = false
                    return oldValue
                }
                // Terminate all processes if was interrupted.
                if wasInt {
                    handler()
                }
            }
            close(signalWatchingPipe[0])
        }
        thread.start()
    }

    deinit {
        // Restore the old action and close the write end of pipe.
        sigaction(SIGINT, &oldAction, nil)
        close(signalWatchingPipe[1])
        thread.join()
    }
}
