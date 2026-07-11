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

import Foundation
import Testing

@testable import Basics

private func sh(_ script: String) -> AsyncProcess {
    AsyncProcess(arguments: ["/bin/sh", "-c", script], outputRedirection: .asyncStream)
}

/// Drains `output` into per-stream byte buffers.
private func collect(
    _ output: AsyncChannel<AsyncProcess.OutputChunk>
) async -> (stdout: [UInt8], stderr: [UInt8]) {
    var out = [UInt8]()
    var err = [UInt8]()
    for await chunk in output {
        switch chunk {
        case .stdout(let bytes): out.append(contentsOf: bytes)
        case .stderr(let bytes): err.append(contentsOf: bytes)
        }
    }
    return (out, err)
}

@Suite(.timeLimit(.minutes(1)))
struct AsyncProcessAsyncStreamTests {
    // A1: every byte delivered, per-stream order preserved, iteration ends at EOF.
    @Test func deliversAllStdoutInOrder() async throws {
        let (collected, result) = try await sh("for i in $(seq 1 2000); do echo line$i; done")
            .launchAsyncStream { _, output in await collect(output) }
        let lines = String(decoding: collected.stdout, as: UTF8.self).split(separator: "\n")
        #expect(lines.count == 2000)
        #expect(lines.first == "line1")
        #expect(lines.last == "line2000")
        #expect(result.exitStatus == .terminated(code: 0))
    }

    // A2: stdout and stderr are delivered as distinct, correctly-tagged chunks.
    @Test func tagsStdoutAndStderrSeparately() async throws {
        let (collected, _) = try await sh(#"printf OUT; printf ERR 1>&2"#)
            .launchAsyncStream { _, output in await collect(output) }
        #expect(String(decoding: collected.stdout, as: UTF8.self) == "OUT")
        #expect(String(decoding: collected.stderr, as: UTF8.self) == "ERR")
    }

    // A3: a gap between two writes forces read -> EAGAIN -> waitForReadable -> read; both lines arrive.
    @Test func resumesAfterWouldBlock() async throws {
        let (collected, _) = try await sh(#"printf "one\n"; sleep 0.3; printf "two\n""#)
            .launchAsyncStream { _, output in await collect(output) }
        #expect(String(decoding: collected.stdout, as: UTF8.self) == "one\ntwo\n")
    }

    // A4: a paused consumer backpressures the child. The child writes >> a pipe buffer to stdout, then touches
    // a marker; while the consumer holds after one chunk, the child is blocked writing, so the marker is absent.
    @Test func pausedConsumerBackpressuresChild() async throws {
        let marker = NSTemporaryDirectory() + "spm-backpressure-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: marker) }
        // 4 MiB is far beyond any plausible pipe buffer (max F_SETPIPE_SZ is ~1 MiB), so the child cannot finish
        // its stdout write while the consumer holds, and the marker stays absent.
        let script = "dd if=/dev/zero bs=1024 count=4096 2>/dev/null; touch \(marker)"

        let (markerDuringPause, _) = try await sh(script).launchAsyncStream { _, output in
            var iterator = output.makeAsyncIterator()
            _ = await iterator.next()                                   // take one chunk, then hold
            try? await Task.sleep(nanoseconds: 500_000_000)
            let existed = FileManager.default.fileExists(atPath: marker)
            while await iterator.next() != nil {}                       // drain so the child can finish
            return existed
        }
        #expect(markerDuringPause == false)
    }

    // A5: iteration ends after the child exits (channel is finished on last EOF).
    @Test func iterationEndsWhenChildExits() async throws {
        let (_, result) = try await sh("echo hi; exit 0")
            .launchAsyncStream { _, output in for await _ in output {} }
        #expect(result.exitStatus == .terminated(code: 0))
    }

    // A6: clean exit status is propagated.
    @Test func propagatesCleanExitStatus() async throws {
        let (_, result) = try await sh("exit 0")
            .launchAsyncStream { _, output in for await _ in output {} }
        #expect(result.exitStatus == .terminated(code: 0))
    }

    // A7: non-zero and signalled exit statuses are propagated.
    @Test func propagatesNonZeroAndSignalledExitStatus() async throws {
        let (_, nonZero) = try await sh("exit 3")
            .launchAsyncStream { _, output in for await _ in output {} }
        #expect(nonZero.exitStatus == .terminated(code: 3))

        let (_, signalled) = try await sh("kill -KILL $$")
            .launchAsyncStream { _, output in for await _ in output {} }
        #expect(signalled.exitStatus == .signalled(signal: SIGKILL))
    }

    // A8: in .asyncStream mode the result's accumulated output is always empty (bytes came via the channel).
    @Test func resultOutputIsEmptyInAsyncStreamMode() async throws {
        let (_, result) = try await sh("echo hi; echo err 1>&2")
            .launchAsyncStream { _, output in await collect(output) }
        #expect(try result.output.get().isEmpty)
        #expect(try result.stderrOutput.get().isEmpty)
    }

    // A9a: throwing from the body mid-stream (a pump likely parked in send) kills and reaps the child and the
    // call returns promptly (guarded by the suite time limit) rather than hanging.
    @Test func bodyThrowUnwindsAndReaps() async {
        struct Boom: Error {}
        let endless = "while true; do dd if=/dev/zero bs=1024 count=64 2>/dev/null; done"
        await #expect(throws: Boom.self) {
            _ = try await sh(endless).launchAsyncStream { _, output in
                for await _ in output { throw Boom() }
            }
        }
    }

    // A9b: cancelling via a Cancellator while the body is consuming a long-running child terminates the call.
    @Test func cancellatorTeardownTerminates() async throws {
        let cancellator = Cancellator(observabilityScope: nil)
        let process = sh("while true; do dd if=/dev/zero bs=1024 count=64 2>/dev/null; done")
        _ = cancellator.register(process)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = try? await process.launchAsyncStream { _, output in
                    for await _ in output {}
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 300_000_000)
                try? cancellator.cancel(deadline: .now() + .seconds(5))
            }
            try await group.waitForAll()
        }
    }

    // A9c: cancelling immediately, across many iterations, hammers the window where cancellation lands during
    // the pump's DispatchSource-readability setup; every iteration must still return (not hang), guarded by the
    // suite time limit. `cat` produces no output, so a pump is parked in waitForReadable right after launch.
    @Test func immediateCancellationDuringSetupNeverHangs() async {
        for _ in 0 ..< 500 {
            let task = Task {
                try await sh("cat").launchAsyncStream { _, output in
                    for await _ in output {}
                }
            }
            task.cancel()
            _ = try? await task.value
        }
    }
}

#endif
