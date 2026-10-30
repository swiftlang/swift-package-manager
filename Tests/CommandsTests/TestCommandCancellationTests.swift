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

// Interrupting `swift test` must stop the tests it started. The signal is sent to the `swift-test` process alone, as a
// CI system or an IDE does, rather than to the whole foreground process group as pressing Ctrl-C in a terminal does.

#if !os(Windows)

import Basics
import Foundation
import PackageModel
import Testing
import _InternalTestSupport

import struct SPMBuildCore.BuildSystemProvider

@Suite(
    .serialized,
    .tags(
        Tag.TestSize.large,
        Tag.Feature.Command.Test,
    )
)
struct TestCommandCancellationTests {
    /// A package with one XCTest test that records its process ID, starts a long-running descendant in its process
    /// group (also recording its process ID) and then waits.
    private static func writeFixture(at root: AbsolutePath, markers: AbsolutePath) throws {
        try localFileSystem.createDirectory(root.appending(components: "Tests", "SlowTests"), recursive: true)
        try localFileSystem.writeFileContents(
            root.appending("Package.swift"),
            string: """
            // swift-tools-version: 5.9
            import PackageDescription

            let package = Package(
                name: "Slow",
                targets: [.testTarget(name: "SlowTests")]
            )
            """
        )
        try localFileSystem.writeFileContents(
            root.appending(components: "Tests", "SlowTests", "SlowTests.swift"),
            string: """
            import Foundation
            import XCTest

            final class SlowTests: XCTestCase {
                func testWaitsForever() throws {
                    let markers = URL(fileURLWithPath: "\(markers.pathString)")
                    try "\\(getpid())".write(to: markers.appendingPathComponent("test.pid"), atomically: true, encoding: .utf8)

                    // Start the descendant with `posix_spawn`, so that it is in the test's process group (a
                    // `Foundation.Process` may be started in its own group).
                    var descendant: pid_t = 0
                    var arguments: [UnsafeMutablePointer<CChar>?] = [strdup("sleep"), strdup("300"), nil]
                    var environment: [UnsafeMutablePointer<CChar>?] = [nil]
                    defer { arguments.forEach { free($0) } }
                    guard posix_spawn(&descendant, "/bin/sleep", nil, nil, &arguments, &environment) == 0 else {
                        XCTFail("could not start the descendant")
                        return
                    }
                    try "\\(descendant)".write(
                        to: markers.appendingPathComponent("descendant.pid"), atomically: true, encoding: .utf8)

                    sleep(300)
                }
            }
            """
        )
    }

    private static func readPID(_ name: String, in directory: AbsolutePath) -> Int32? {
        guard let text = try? String(contentsOfFile: directory.appending(name).pathString, encoding: .utf8) else {
            return nil
        }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

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

    /// Polls `condition` until it holds or `timeout` passes.
    private static func wait(timeout: Duration, until condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    @Test(arguments: SupportedBuildSystemOnAllPlatforms)
    func interruptingTheCommandStopsItsTests(buildSystem: BuildSystemProvider.Kind) async throws {
        try await withTemporaryDirectory(removeTreeOnDeinit: true) { tmpdir in
            let package = tmpdir.appending("Slow")
            let markers = tmpdir.appending("markers")
            try localFileSystem.createDirectory(markers)
            try Self.writeFixture(at: package, markers: markers)

            // Build first, so that the interruption happens while tests are running rather than while building.
            try await executeSwiftBuild(
                package,
                extraArgs: ["--build-tests", "--disable-sandbox"],
                buildSystem: buildSystem
            )

            let process = try SwiftPM.Test.launch(
                getBuildSystemArgs(for: buildSystem) + ["--parallel", "--skip-build", "--disable-sandbox"],
                packagePath: package,
                standardOutputFile: tmpdir.appending("stdout.txt"),
                standardErrorFile: tmpdir.appending("stderr.txt")
            )
            defer { if process.isRunning { process.terminate() } }

            // Wait for the test to be running and to have started its descendant.
            let started = try await Self.wait(timeout: .seconds(120)) {
                Self.readPID("test.pid", in: markers) != nil && Self.readPID("descendant.pid", in: markers) != nil
            }
            try #require(started, "the test never started")
            let testPID = try #require(Self.readPID("test.pid", in: markers))
            let descendantPID = try #require(Self.readPID("descendant.pid", in: markers))

            // Interrupt `swift-test` only. (`Process.interrupt()` can signal the process's whole group on Darwin, which
            // would hide the problem.)
            #expect(kill(process.processIdentifier, SIGINT) == 0)

            let exited = try await Self.wait(timeout: .seconds(60)) { !process.isRunning }
            #expect(exited, "swift-test did not exit after being interrupted")

            let testStopped = try await Self.wait(timeout: .seconds(10)) { !Self.isRunning(testPID) }
            #expect(testStopped, "the test process outlived swift-test")
            let descendantStopped = try await Self.wait(timeout: .seconds(10)) { !Self.isRunning(descendantPID) }
            #expect(descendantStopped, "the test's descendant outlived swift-test")

            // Clean up anything a failed assertion above left behind.
            for pid in [testPID, descendantPID] where Self.isRunning(pid) {
                kill(pid, SIGKILL)
            }

            let stderr = (try? String(contentsOfFile: tmpdir.appending("stderr.txt").pathString, encoding: .utf8)) ?? ""
            #expect(!stderr.contains("Operation cancelled"), "unexpected cancellation errors:\n\(stderr)")
        }
    }
}

#endif
