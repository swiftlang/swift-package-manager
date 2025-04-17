/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import _InternalTestSupport
import _Concurrency
import Basics
import XCTest

import TSCclibc // for SPM_posix_spawn_file_actions_addchdir_np_supported

import class TSCBasic.BufferedOutputByteStream
import struct TSCBasic.ByteString
import struct TSCBasic.Format
import class TSCBasic.Thread
import func TSCBasic.withTemporaryFile
import func TSCTestSupport.withCustomEnv

final class AsyncProcessTests: XCTestCase {
    #if os(Windows)
    let executableExt = ".exe"
    #else
    let executableExt = ""
    #endif

    func testBasics() throws {
        try skipOnWindowsAsTestCurrentlyFails(because: """
            threw error "missingExecutableProgram(program: "echo.exe")"
        """)

        do {
            let process = AsyncProcess(args: "echo\(executableExt)", "hello")
            try process.launch()
            let result = try process.waitUntilExit()
            XCTAssertEqual(try result.utf8Output(), "hello\n")
            XCTAssertEqual(result.exitStatus, .terminated(code: 0))
            XCTAssertEqual(result.arguments, process.arguments)
        }

        do {
            let process = AsyncProcess(scriptName: "exit4")
            try process.launch()
            let result = try process.waitUntilExit()
            XCTAssertEqual(result.exitStatus, .terminated(code: 4))
        }
    }

    func testPopenBasic() throws {
        try skipOnWindowsAsTestCurrentlyFails(because: """
            threw error "missingExecutableProgram(program: "echo.exe")"
        """)

        // Test basic echo.
        XCTAssertEqual(try AsyncProcess.popen(arguments: ["echo\(executableExt)", "hello"]).utf8Output(), "hello\n")
    }

    func testPopenWithBufferLargerThanAllocated() throws {
        try skipOnWindowsAsTestCurrentlyFails(because: """
            threw error "missingExecutableProgram(program: "cat.exe")"
        """)
        // Test buffer larger than that allocated.
        try withTemporaryFile { file in
            let count = 10000
            let stream = BufferedOutputByteStream()
            stream.send(Format.asRepeating(string: "a", count: count))
            try localFileSystem.writeFileContents(file.path, bytes: stream.bytes)
            let outputCount = try AsyncProcess.popen(args: "cat\(executableExt)", file.path.pathString).utf8Output().count
            XCTAssert(outputCount == count)
        }
    }

    func testPopenLegacyAsync() throws {
        #if os(Windows)
        let args = ["where.exe", "where"]
        let answer = "C:\\Windows\\System32\\where.exe"
        #else
        let args = ["whoami"]
        let answer = NSUserName()
        #endif
        var popenResult: Result<AsyncProcessResult, Error>?
        let group = DispatchGroup()
        group.enter()
        AsyncProcess.popen(arguments: args) { result in
            popenResult = result
            group.leave()
        }
        group.wait()
        switch popenResult {
        case .success(let processResult):
            let output = try processResult.utf8Output()
            XCTAssertTrue(output.hasPrefix(answer))
        case .failure(let error):
            XCTFail("error = \(error)")
        case nil:
            XCTFail()
        }
    }

    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    func testPopenAsync() async throws {
        #if os(Windows)
        let args = ["where.exe", "where"]
        let answer = "C:\\Windows\\System32\\where.exe"
        #else
        let args = ["whoami"]
        let answer = NSUserName()
        #endif
        let processResult: AsyncProcessResult
        do {
            processResult = try await AsyncProcess.popen(arguments: args)
        } catch {
            XCTFail("error = \(error)")
            return
        }
        let output = try processResult.utf8Output()
        XCTAssertTrue(output.hasPrefix(answer))
    }

    func testCheckNonZeroExit() throws {
        try skipOnWindowsAsTestCurrentlyFails(because: """
            threw error "missingExecutableProgram(program: "echo.exe")"
        """)

        do {
            let output = try AsyncProcess.checkNonZeroExit(args: "echo\(executableExt)", "hello")
            XCTAssertEqual(output, "hello\n")
        }

        do {
            let output = try AsyncProcess.checkNonZeroExit(scriptName: "exit4")
            XCTFail("Unexpected success \(output)")
        } catch AsyncProcessResult.Error.nonZeroExit(let result) {
            XCTAssertEqual(result.exitStatus, .terminated(code: 4))
        }
    }

    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    func testCheckNonZeroExitAsync() async throws {
        try skipOnWindowsAsTestCurrentlyFails(because: """
            threw error "missingExecutableProgram(program: "echo.exe")"
        """)

        do {
            let output = try await AsyncProcess.checkNonZeroExit(args: "echo\(executableExt)", "hello")
            XCTAssertEqual(output, "hello\n")
        }

        do {
            let output = try await AsyncProcess.checkNonZeroExit(scriptName: "exit4")
            XCTFail("Unexpected success \(output)")
        } catch AsyncProcessResult.Error.nonZeroExit(let result) {
            XCTAssertEqual(result.exitStatus, .terminated(code: 4))
        }
    }

    func testFindExecutable() throws {
        try skipOnWindowsAsTestCurrentlyFails(because: "Assertion failure when trying to find ls executable")

        try testWithTemporaryDirectory { tmpdir in
            // This process should always work.
            XCTAssertTrue(AsyncProcess.findExecutable("ls") != nil)

            XCTAssertEqual(AsyncProcess.findExecutable("nonExistantProgram"), nil)
            XCTAssertEqual(AsyncProcess.findExecutable(""), nil)

            // Create a local nonexecutable file to test.
            let tempExecutable = tmpdir.appending(component: "nonExecutableProgram")
            try localFileSystem.writeFileContents(tempExecutable, bytes: """
            #!/bin/sh
            exit

            """)

            try withCustomEnv(["PATH": tmpdir.pathString]) {
                XCTAssertEqual(AsyncProcess.findExecutable("nonExecutableProgram"), nil)
            }
        }
    }

    func testNonExecutableLaunch() throws {
        try testWithTemporaryDirectory { tmpdir in
            // Create a local nonexecutable file to test.
            let tempExecutable = tmpdir.appending(component: "nonExecutableProgram")
            try localFileSystem.writeFileContents(tempExecutable, bytes: """
            #!/bin/sh
            exit

            """)

            try withCustomEnv(["PATH": tmpdir.pathString]) {
                do {
                    let process = AsyncProcess(args: "nonExecutableProgram")
                    try process.launch()
                    XCTFail("Should have failed to validate nonExecutableProgram")
                } catch AsyncProcess.Error.missingExecutableProgram(let program) {
                    XCTAssert(program == "nonExecutableProgram")
                }
            }
        }
    }

    func testThreadSafetyOnWaitUntilExit() throws {
        try skipOnWindowsAsTestCurrentlyFails(because: """
            threw error "missingExecutableProgram(program: "echo.exe")"
        """)

        let process = AsyncProcess(args: "echo\(executableExt)", "hello")
        try process.launch()

        var result1 = ""
        var result2 = ""

        let t1 = Thread {
            result1 = try! process.waitUntilExit().utf8Output()
        }

        let t2 = Thread {
            result2 = try! process.waitUntilExit().utf8Output()
        }

        t1.start()
        t2.start()
        t1.join()
        t2.join()

        XCTAssertEqual(result1, "hello\n")
        XCTAssertEqual(result2, "hello\n")
    }

    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    func testThreadSafetyOnWaitUntilExitAsync() async throws {
        try skipOnWindowsAsTestCurrentlyFails(because: """
            threw error "missingExecutableProgram(program: "echo.exe")"
        """)

        let process = AsyncProcess(args: "echo\(executableExt)", "hello")
        try process.launch()

        let t1 = Task {
            try await process.waitUntilExit().utf8Output()
        }

        let t2 = Task {
            try await process.waitUntilExit().utf8Output()
        }

        let result1 = try await t1.value
        let result2 = try await t2.value

        XCTAssertEqual(result1, "hello\n")
        XCTAssertEqual(result2, "hello\n")
    }

    func testStdin() throws {
        try skipOnWindowsAsTestCurrentlyFails(because: """
        threw error "Error Domain=NSCocoaErrorDomain Code=3584 "(null)"UserInfo={NSUnderlyingError=Error Domain=org.swift.Foundation.WindowsError Code=193 "(null)"}"
        """)

        var stdout = [UInt8]()
        let process = AsyncProcess(scriptName: "in-to-out", outputRedirection: .stream(stdout: { stdoutBytes in
            stdout += stdoutBytes
        }, stderr: { _ in }))
        let stdinStream = try process.launch()

        stdinStream.write("hello\n")
        stdinStream.flush()

        try stdinStream.close()

        try process.waitUntilExit()

        XCTAssertEqual(String(decoding: stdout, as: UTF8.self), "hello\n")
    }

    func testStdoutStdErr() throws {
        try skipOnWindowsAsTestCurrentlyFails(because: """
        threw error "Error Domain=NSCocoaErrorDomain Code=3584 "(null)"UserInfo={NSUnderlyingError=Error Domain=org.swift.Foundation.WindowsError Code=193 "(null)"}"
        """)

        // A simple script to check that stdout and stderr are captured separatly.
        do {
            let result = try AsyncProcess.popen(scriptName: "simple-stdout-stderr")
            XCTAssertEqual(try result.utf8Output(), "simple output\n")
            XCTAssertEqual(try result.utf8stderrOutput(), "simple error\n")
        }

        // A long stdout and stderr output.
        do {
            let result = try AsyncProcess.popen(scriptName: "long-stdout-stderr")
            let count = 16 * 1024
            XCTAssertEqual(try result.utf8Output(), String(repeating: "1", count: count))
            XCTAssertEqual(try result.utf8stderrOutput(), String(repeating: "2", count: count))
        }

        // This script will block if the streams are not read.
        do {
            let result = try AsyncProcess.popen(scriptName: "deadlock-if-blocking-io")
            let count = 16 * 1024
            XCTAssertEqual(try result.utf8Output(), String(repeating: "1", count: count))
            XCTAssertEqual(try result.utf8stderrOutput(), String(repeating: "2", count: count))
        }
    }

    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    func testStdoutStdErrAsync() async throws {
        try skipOnWindowsAsTestCurrentlyFails(because: """
        threw error "Error Domain=NSCocoaErrorDomain Code=3584 "(null)"UserInfo={NSUnderlyingError=Error Domain=org.swift.Foundation.WindowsError Code=193 "(null)"}"
        """)

        // A simple script to check that stdout and stderr are captured separatly.
        do {
            let result = try await AsyncProcess.popen(scriptName: "simple-stdout-stderr")
            XCTAssertEqual(try result.utf8Output(), "simple output\n")
            XCTAssertEqual(try result.utf8stderrOutput(), "simple error\n")
        }

        // A long stdout and stderr output.
        do {
            let result = try await AsyncProcess.popen(scriptName: "long-stdout-stderr")
            let count = 16 * 1024
            XCTAssertEqual(try result.utf8Output(), String(repeating: "1", count: count))
            XCTAssertEqual(try result.utf8stderrOutput(), String(repeating: "2", count: count))
        }

        // This script will block if the streams are not read.
        do {
            let result = try await AsyncProcess.popen(scriptName: "deadlock-if-blocking-io")
            let count = 16 * 1024
            XCTAssertEqual(try result.utf8Output(), String(repeating: "1", count: count))
            XCTAssertEqual(try result.utf8stderrOutput(), String(repeating: "2", count: count))
        }
    }

    func testStdoutStdErrRedirected() throws {
        try skipOnWindowsAsTestCurrentlyFails(because: """
        threw error "Error Domain=NSCocoaErrorDomain Code=3584 "(null)"UserInfo={NSUnderlyingError=Error Domain=org.swift.Foundation.WindowsError Code=193 "(null)"}"
        """)

        // A simple script to check that stdout and stderr are captured in the same location.
        do {
            let process = AsyncProcess(
                scriptName: "simple-stdout-stderr",
                outputRedirection: .collect(redirectStderr: true)
            )
            try process.launch()
            let result = try process.waitUntilExit()
            XCTAssertEqual(try result.utf8Output(), "simple error\nsimple output\n")
            XCTAssertEqual(try result.utf8stderrOutput(), "")
        }

        // A long stdout and stderr output.
        do {
            let process = AsyncProcess(
                scriptName: "long-stdout-stderr",
                outputRedirection: .collect(redirectStderr: true)
            )
            try process.launch()
            let result = try process.waitUntilExit()

            let count = 16 * 1024
            XCTAssertEqual(try result.utf8Output(), String(repeating: "12", count: count))
            XCTAssertEqual(try result.utf8stderrOutput(), "")
        }
    }

    func testStdoutStdErrStreaming() throws {
        try skipOnWindowsAsTestCurrentlyFails(because: """
        threw error "Error Domain=NSCocoaErrorDomain Code=3584 "(null)"UserInfo={NSUnderlyingError=Error Domain=org.swift.Foundation.WindowsError Code=193 "(null)"}"
        """)

        var stdout = [UInt8]()
        var stderr = [UInt8]()
        let process = AsyncProcess(scriptName: "long-stdout-stderr", outputRedirection: .stream(stdout: { stdoutBytes in
            stdout += stdoutBytes
        }, stderr: { stderrBytes in
            stderr += stderrBytes
        }))
        try process.launch()
        try process.waitUntilExit()

        let count = 16 * 1024
        XCTAssertEqual(String(bytes: stdout, encoding: .utf8), String(repeating: "1", count: count))
        XCTAssertEqual(String(bytes: stderr, encoding: .utf8), String(repeating: "2", count: count))
    }

    func testStdoutStdErrStreamingRedirected() throws {
        try skipOnWindowsAsTestCurrentlyFails(because: """
        threw error "Error Domain=NSCocoaErrorDomain Code=3584 "(null)"UserInfo={NSUnderlyingError=Error Domain=org.swift.Foundation.WindowsError Code=193 "(null)"}"
        """)

        var stdout = [UInt8]()
        var stderr = [UInt8]()
        let process = AsyncProcess(scriptName: "long-stdout-stderr", outputRedirection: .stream(stdout: { stdoutBytes in
            stdout += stdoutBytes
        }, stderr: { stderrBytes in
            stderr += stderrBytes
        }, redirectStderr: true))
        try process.launch()
        try process.waitUntilExit()

        let count = 16 * 1024
        XCTAssertEqual(String(bytes: stdout, encoding: .utf8), String(repeating: "12", count: count))
        XCTAssertEqual(stderr, [])
    }

    func testWorkingDirectory() throws {
        try skipOnWindowsAsTestCurrentlyFails(because: """
            threw error "missingExecutableProgram(program: "cat.exe")"
        """)

        guard #available(macOS 10.15, *) else {
            // Skip this test since it's not supported in this OS.
            return
        }

        #if os(Linux) || os(Android)
        guard SPM_posix_spawn_file_actions_addchdir_np_supported() else {
            // Skip this test since it's not supported in this OS.
            return
        }
        #endif

        try withTemporaryDirectory(removeTreeOnDeinit: true) { tempDirPath in
            let parentPath = tempDirPath.appending(component: "file")
            let childPath = tempDirPath.appending(component: "subdir").appending(component: "file")

            try localFileSystem.writeFileContents(parentPath, bytes: ByteString("parent"))
            try localFileSystem.createDirectory(childPath.parentDirectory, recursive: true)
            try localFileSystem.writeFileContents(childPath, bytes: ByteString("child"))

            do {
                let process = AsyncProcess(arguments: ["cat\(executableExt)", "file"], workingDirectory: tempDirPath)
                try process.launch()
                let result = try process.waitUntilExit()
                XCTAssertEqual(try result.utf8Output(), "parent")
            }

            do {
                let process = AsyncProcess(arguments: ["cat", "file"], workingDirectory: childPath.parentDirectory)
                try process.launch()
                let result = try process.waitUntilExit()
                XCTAssertEqual(try result.utf8Output(), "child")
            }
        }
    }

    func testAsyncStream() async throws {
        // rdar://133548796
        try XCTSkipIfCI()
        try skipOnWindowsAsTestCurrentlyFails(because: """
        threw error "Error Domain=NSCocoaErrorDomain Code=3584 "(null)"UserInfo={NSUnderlyingError=Error Domain=org.swift.Foundation.WindowsError Code=193 "(null)"}"
        """)

        let (stdoutStream, stdoutContinuation) = AsyncProcess.ReadableStream.makeStream()
        let (stderrStream, stderrContinuation) = AsyncProcess.ReadableStream.makeStream()

        let process = AsyncProcess(
            scriptName: "echo\(executableExt)",
            outputRedirection: .stream {
                stdoutContinuation.yield($0)
            } stderr: {
                stderrContinuation.yield($0)
            }
        )

        let result = try await withThrowingTaskGroup(of: Void.self) { group in
            let stdin = try process.launch()

            group.addTask {
                var counter = 0
                stdin.write("Hello \(counter)\n")
                stdin.flush()

                for await output in stdoutStream {
                    XCTAssertEqual(output, .init("Hello \(counter)\n".utf8))
                    counter += 1

                    stdin.write(.init("Hello \(counter)\n".utf8))
                    stdin.flush()
                }

                XCTAssertEqual(counter, 5)

                try stdin.close()
            }

            group.addTask {
                var counter = 0
                for await _ in stderrStream {
                    counter += 1
                }

                XCTAssertEqual(counter, 0)
            }

            defer {
                stdoutContinuation.finish()
                stderrContinuation.finish()
            }

            return try await process.waitUntilExit()
        }

        XCTAssertEqual(result.exitStatus, .terminated(code: 0))
    }

    func testAsyncStreamHighLevelAPI() async throws {
        // rdar://133548796
        try XCTSkipIfCI()
        try skipOnWindowsAsTestCurrentlyFails(because: """
        threw error "Error Domain=NSCocoaErrorDomain Code=3584 "(null)"UserInfo={NSUnderlyingError=Error Domain=org.swift.Foundation.WindowsError Code=193 "(null)"}"
        """)

        let result = try await AsyncProcess.popen(
            scriptName: "echo\(executableExt)",
            stdout: { stdin, stdout in
                var counter = 0
                stdin.write("Hello \(counter)\n")
                stdin.flush()

                for await output in stdout {
                    XCTAssertEqual(output, .init("Hello \(counter)\n".utf8))
                    counter += 1

                    stdin.write(.init("Hello \(counter)\n".utf8))
                    stdin.flush()
                }

                XCTAssertEqual(counter, 5)

                try stdin.close()
            },
            stderr: { stderr in
                var counter = 0
                for await _ in stderr {
                    counter += 1
                }

                XCTAssertEqual(counter, 0)
            }
        )

        XCTAssertEqual(result.exitStatus, .terminated(code: 0))
    }
}

extension AsyncProcess {
    private static func script(_ name: String) -> String {
        AbsolutePath(#file).parentDirectory.appending(components: "processInputs", name).pathString
    }

    fileprivate convenience init(
        scriptName: String,
        arguments: [String] = [],
        outputRedirection: OutputRedirection = .collect
    ) {
        self.init(
            arguments: [Self.script(scriptName)] + arguments,
            environment: .current,
            outputRedirection: outputRedirection
        )
    }

    @available(*, noasync)
    fileprivate static func checkNonZeroExit(
        scriptName: String,
        environment: Environment = .current,
        loggingHandler: LoggingHandler? = .none
    ) throws -> String {
        try self.checkNonZeroExit(
            args: self.script(scriptName),
            environment: environment,
            loggingHandler: loggingHandler
        )
    }

    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    fileprivate static func checkNonZeroExit(
        scriptName: String,
        environment: Environment = .current,
        loggingHandler: LoggingHandler? = .none
    ) async throws -> String {
        try await self.checkNonZeroExit(
            args: self.script(scriptName),
            environment: environment,
            loggingHandler: loggingHandler
        )
    }

    @available(*, noasync)
    @discardableResult
    fileprivate static func popen(
        scriptName: String,
        environment: Environment = .current,
        loggingHandler: LoggingHandler? = .none
    ) throws -> AsyncProcessResult {
        try self.popen(arguments: [self.script(scriptName)], environment: .current, loggingHandler: loggingHandler)
    }

    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    @discardableResult
    fileprivate static func popen(
        scriptName: String,
        environment: Environment = .current,
        loggingHandler: LoggingHandler? = .none
    ) async throws -> AsyncProcessResult {
        try await self.popen(arguments: [self.script(scriptName)], environment: .current, loggingHandler: loggingHandler)
    }

    fileprivate static func popen(
        scriptName: String,
        stdout: @escaping AsyncProcess.DuplexStreamHandler,
        stderr: AsyncProcess.ReadableStreamHandler? = nil
    ) async throws -> AsyncProcessResult {
        try await self.popen(arguments: [self.script(scriptName)], stdoutHandler: stdout, stderrHandler: stderr)
    }
}
