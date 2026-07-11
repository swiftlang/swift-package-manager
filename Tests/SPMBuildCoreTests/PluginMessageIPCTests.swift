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

#if !os(Windows) && (!canImport(Darwin) || os(macOS))

import Basics
import Foundation
import Testing

@testable import SPMBuildCore

/// Exercises the plugin IPC substrate end to end over a real subprocess: `framed` writes to the child's
/// stdin, `AsyncProcess.launchAsyncStream` reads its stdout, and `FrameReassembler` decodes it back. This is
/// the exact integration the plugin runner uses, without the plugin compilation machinery.
@Suite(.timeLimit(.minutes(1)))
struct PluginMessageIPCTests {
    @Test func framedMessagesRoundTripThroughSubprocess() async throws {
        let first = Data("first plugin message".utf8)
        let second = Data("second".utf8)
        let outgoing = framed(first) + framed(second)

        // `head -c N` echoes exactly the N bytes we send, then exits, so no stdin close is needed.
        let process = AsyncProcess(
            arguments: ["/bin/sh", "-c", "head -c \(outgoing.count)"],
            outputRedirection: .asyncStream
        )

        var received: [Data] = []
        let (_, result) = try await process.launchAsyncStream { stdin, output in
            stdin.write(outgoing)
            stdin.flush()
            var reassembler = FrameReassembler()
            for await chunk in output {
                if case .stdout(let bytes) = chunk {
                    received.append(contentsOf: try reassembler.push(bytes))
                }
            }
            try reassembler.finish()
        }

        #expect(received == [first, second])
        #expect(result.exitStatus == .terminated(code: 0))
    }

    @Test func cancellationTerminatesAStuckSubprocess() async throws {
        // `cat` blocks forever reading stdin (which we never close), producing no output, so the consumer
        // stays suspended until the surrounding task is cancelled.
        let process = AsyncProcess(arguments: ["/bin/cat"], outputRedirection: .asyncStream)

        let task = Task {
            try await process.launchAsyncStream { _, output in
                for await _ in output {}
            }
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        // Must return (not hang): launchAsyncStream SIGKILLs and reaps on teardown.
        _ = try? await task.value
    }
}

#endif
