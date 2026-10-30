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

// These tests run real child processes through `Cancellator.withCancellable`, using a shell script in place of `tar`
// (`TarArchiver.validate` runs `<tar> tf <path>` with `PlatformOptions.cancellable`). The script records its own PID
// and that of a child it starts, so the tests can check what is left running after a cancellation.

#if !os(Windows)

import Foundation
import Testing

@testable import Basics

/// Cancels everything registered with `cancellator`. `_cancel` blocks its thread until the handlers finish, and those
/// handlers run as tasks, so it must not run on a thread of the cooperative pool or it can starve them.
private func cancel(_ cancellator: Cancellator) async {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            cancellator._cancel(deadline: .now() + .seconds(30))
            continuation.resume()
        }
    }
}

@Suite(.serialized)
struct CancellatorProcessTests {
    /// A temporary directory holding a fake `tar` script and the files it writes.
    private final class Fixture {
        let directory: URL
        let script: URL
        let archive: URL

        var scriptPath: String { self.script.path }
        var archivePath: AbsolutePath { try! AbsolutePath(validating: self.archive.path) }
        var processPID: Int32? { self.readPID("process.pid") }
        var descendantPID: Int32? { self.readPID("descendant.pid") }
        var interruptMarkerExists: Bool {
            FileManager.default.fileExists(atPath: self.directory.appendingPathComponent("interrupted").path)
        }

        /// - Parameter body: Shell code run by the fake `tar`. `$DIR` is the fixture directory. `process.pid` and
        ///   `descendant.pid` are written before `body` runs. `body` must create `$DIR/ready` once it is ready to be
        ///   interrupted (that is, after it has set up its signal handling).
        init(body: String) throws {
            self.directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("CancellatorProcessTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            self.script = self.directory.appendingPathComponent("fake-tar")
            self.archive = self.directory.appendingPathComponent("archive.tar")
            try Data().write(to: self.archive)
            let text = """
            #!/bin/sh
            DIR='\(self.directory.path)'
            echo $$ > "$DIR/process.pid.tmp"; mv "$DIR/process.pid.tmp" "$DIR/process.pid"
            sleep 60 &
            echo $! > "$DIR/descendant.pid.tmp"; mv "$DIR/descendant.pid.tmp" "$DIR/descendant.pid"
            \(body)
            """
            try text.write(to: self.script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: self.script.path)
        }

        deinit {
            // Don't leave the script's `sleep` behind if a test failed.
            for pid in [self.processPID, self.descendantPID].compactMap({ $0 }) {
                kill(pid, SIGKILL)
            }
            try? FileManager.default.removeItem(at: self.directory)
        }

        private func readPID(_ name: String) -> Int32? {
            guard let text = try? String(contentsOf: self.directory.appendingPathComponent(name), encoding: .utf8) else {
                return nil
            }
            return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        /// Waits until the script has recorded both PIDs and set up its signal handling.
        func waitUntilStarted() async throws -> (process: Int32, descendant: Int32) {
            let deadline = ContinuousClock.now + .seconds(10)
            while ContinuousClock.now < deadline {
                if let process = self.processPID, let descendant = self.descendantPID,
                   FileManager.default.fileExists(atPath: self.directory.appendingPathComponent("ready").path)
                {
                    return (process, descendant)
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            throw StringError("the fake tar did not start")
        }
    }

    /// Whether `pid` is a running process (a zombie awaiting reaping doesn't count).
    private static func isRunning(_ pid: Int32) -> Bool {
        guard kill(pid, 0) == 0 else { return false }
        #if os(Linux)
        // In a container, PID 1 may not reap orphans, so look at the state of the process.
        if let stat = try? String(contentsOfFile: "/proc/\(pid)/stat", encoding: .utf8),
           let state = stat.split(separator: ")").last?.split(separator: " ").first
        {
            return state != "Z"
        }
        #endif
        return true
    }

    /// Polls until `pid` is no longer running or `timeout` passes.
    private static func waitForExit(_ pid: Int32, timeout: Duration = .seconds(5)) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if !self.isRunning(pid) { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return !self.isRunning(pid)
    }

    /// Exits as soon as it is interrupted, as a well-behaved tool does.
    private static let exitsOnInterrupt = """
    trap 'touch "$DIR/interrupted"; exit 0' INT
    touch "$DIR/ready"
    while true; do wait; done
    """

    /// Ignores being interrupted, so only the forced termination at the end of the grace period can stop it.
    private static let ignoresInterrupt = """
    trap '' INT
    touch "$DIR/ready"
    while true; do wait; done
    """

    @Test
    func cancelWaitsForChildToExit() async throws {
        let fixture = try Fixture(body: Self.exitsOnInterrupt)
        let cancellator = Cancellator(observabilityScope: nil)
        let archiver = TarArchiver(fileSystem: localFileSystem, cancellator: cancellator, tarCommand: fixture.scriptPath)

        let validation = Task { try await archiver.validate(path: fixture.archivePath) }
        let (process, _) = try await fixture.waitUntilStarted()

        await cancel(cancellator)

        // `_cancel` must not return before the child has been torn down, or SwiftPM could exit and orphan it.
        #expect(!Self.isRunning(process), "the child was still running when the cancellation returned")
        #expect(fixture.interruptMarkerExists, "the child was not given the chance to handle SIGINT")
        await #expect(throws: Basics.CancellationError.self) { try await validation.value }
    }

    @Test
    func cancelTerminatesChildThatIgnoresInterruptAndItsDescendants() async throws {
        let fixture = try Fixture(body: Self.ignoresInterrupt)
        let cancellator = Cancellator(observabilityScope: nil)
        let archiver = TarArchiver(fileSystem: localFileSystem, cancellator: cancellator, tarCommand: fixture.scriptPath)

        let validation = Task { try await archiver.validate(path: fixture.archivePath) }
        let (process, descendant) = try await fixture.waitUntilStarted()

        await cancel(cancellator)

        #expect(!Self.isRunning(process), "the child was still running when the cancellation returned")
        #expect(try await Self.waitForExit(descendant), "the child's descendant outlived the cancellation")
        #expect(!fixture.interruptMarkerExists)
        await #expect(throws: Basics.CancellationError.self) { try await validation.value }
    }

    @Test
    func cancellingTheCallerTerminatesTheChild() async throws {
        let fixture = try Fixture(body: Self.exitsOnInterrupt)
        let archiver = TarArchiver(fileSystem: localFileSystem, cancellator: nil, tarCommand: fixture.scriptPath)

        let validation = Task { try await archiver.validate(path: fixture.archivePath) }
        let (process, _) = try await fixture.waitUntilStarted()

        validation.cancel()

        await #expect(throws: Basics.CancellationError.self) { try await validation.value }
        #expect(!Self.isRunning(process), "the child outlived the cancelled call")
        #expect(fixture.interruptMarkerExists, "the child was not given the chance to handle SIGINT")
    }

    /// The original defect was a race, so repeat the cancellation to make a regression show up reliably.
    @Test(arguments: 0..<15)
    func cancelNeverLeavesTheChildRunning(iteration: Int) async throws {
        let fixture = try Fixture(body: Self.exitsOnInterrupt)
        let cancellator = Cancellator(observabilityScope: nil)
        let archiver = TarArchiver(fileSystem: localFileSystem, cancellator: cancellator, tarCommand: fixture.scriptPath)

        let validation = Task { try await archiver.validate(path: fixture.archivePath) }
        let (process, _) = try await fixture.waitUntilStarted()

        await cancel(cancellator)

        #expect(!Self.isRunning(process), "iteration \(iteration): the child was still running after the cancellation")
        _ = try? await validation.value
    }
}

#endif
