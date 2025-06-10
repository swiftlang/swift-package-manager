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

#if os(Windows)
let catExecutable = "type"
#else
let catExecutable = "cat"
#endif

final class AsyncProcessTests: XCTestCase {
    let echoExecutableArgs = getAsyncProcessArgs(executable: "echo")
    let catExecutableArgs = getAsyncProcessArgs(executable: catExecutable)

    func testBasicsProcess() throws {
            let process = AsyncProcess(arguments: echoExecutableArgs + ["hello"])
            try process.launch()
            let result = try process.waitUntilExit()
            XCTAssertEqual(try result.utf8Output(), "hello\(ProcessInfo.EOL)")
            XCTAssertEqual(result.exitStatus, .terminated(code: 0))
            XCTAssertEqual(result.arguments, process.arguments)
    }

    func testBasicsScript() throws {
            let process = AsyncProcess(scriptName: "exit4\(ProcessInfo.batSuffix)")
            try process.launch()
            let result = try process.waitUntilExit()
            XCTAssertEqual(result.exitStatus, .terminated(code: 4))
    }

    func testPopenBasic() throws {
        // Test basic echo.
        XCTAssertEqual(try AsyncProcess.popen(arguments: echoExecutableArgs + ["hello"]).utf8Output(), "hello\(ProcessInfo.EOL)")
    }

    func testPopenWithBufferLargerThanAllocated() throws {
        // Test buffer larger than that allocated.
        try withTemporaryFile { file in
            let count = 10000
            let stream = BufferedOutputByteStream()
            stream.send(Format.asRepeating(string: "a", count: count))
            try localFileSystem.writeFileContents(file.path, bytes: stream.bytes)
            let actualStreamCount = stream.bytes.count
            XCTAssertTrue(actualStreamCount == count, "Actual stream count (\(actualStreamCount)) is not as exxpected (\(count))")
            let outputCount = try AsyncProcess.popen(arguments: catExecutableArgs + [file.path.pathString]).utf8Output().count
            XCTAssert(outputCount == count, "Actual count (\(outputCount)) is not as expected (\(count))")
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

    func testCheckNonZeroExit() async throws {
        do {
            let output = try await AsyncProcess.checkNonZeroExit(args: echoExecutableArgs + ["hello"])
            XCTAssertEqual(output, "hello\(ProcessInfo.EOL)")
        }

        do {
            let output = try await AsyncProcess.checkNonZeroExit(scriptName: "exit4\(ProcessInfo.batSuffix)")
            XCTFail("Unexpected success \(output)")
        } catch AsyncProcessResult.Error.nonZeroExit(let result) {
            XCTAssertEqual(result.exitStatus, .terminated(code: 4))
        }
    }

    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    func testCheckNonZeroExitAsync() async throws {
        do {
            let output = try await AsyncProcess.checkNonZeroExit(args: echoExecutableArgs + ["hello"])
            XCTAssertEqual(output, "hello\(ProcessInfo.EOL)")
        }

        do {
            let output = try await AsyncProcess.checkNonZeroExit(scriptName: "exit4\(ProcessInfo.batSuffix)")
            XCTFail("Unexpected success \(output)")
        } catch AsyncProcessResult.Error.nonZeroExit(let result) {
            XCTAssertEqual(result.exitStatus, .terminated(code: 4))
        }
    }

    func testFindExecutable() throws {
        try testWithTemporaryDirectory { tmpdir in
            // This process should always work.
            #if os(Windows)
            XCTAssertTrue(AsyncProcess.findExecutable("cmd.exe") != nil)
            #else
            XCTAssertTrue(AsyncProcess.findExecutable("ls") != nil)
            #endif

            XCTAssertEqual(AsyncProcess.findExecutable("nonExistantProgram"), nil)
            XCTAssertEqual(AsyncProcess.findExecutable(""), nil)

            // Create a local nonexecutable file to test.
            let tempExecutable = tmpdir.appending(component: "nonExecutableProgram")
            #if os(Windows)
            let exitScriptContent = ByteString("EXIT /B")
            #else
            let exitScriptContent = ByteString("""
            #!/bin/sh
            exit

            """)
            #endif
            try localFileSystem.writeFileContents(tempExecutable, bytes: exitScriptContent)

            try Environment.makeCustom(["PATH": tmpdir.pathString]) {
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

            try Environment.makeCustom(["PATH": tmpdir.pathString]) {
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
        let process = AsyncProcess(args: echoExecutableArgs + ["hello"])
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

        XCTAssertEqual(result1, "hello\(ProcessInfo.EOL)")
        XCTAssertEqual(result2, "hello\(ProcessInfo.EOL)")
    }

    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    func testThreadSafetyOnWaitUntilExitAsync() async throws {
        let process = AsyncProcess(args: echoExecutableArgs + ["hello"])
        try process.launch()

        let t1 = Task {
            try await process.waitUntilExit().utf8Output()
        }

        let t2 = Task {
            try await process.waitUntilExit().utf8Output()
        }

        let result1 = try await t1.value
        let result2 = try await t2.value

        XCTAssertEqual(result1, "hello\(ProcessInfo.EOL)")
        XCTAssertEqual(result2, "hello\(ProcessInfo.EOL)")
    }

    func testStdin() throws {
        var stdout = [UInt8]()
        let process = AsyncProcess(scriptName: "in-to-out\(ProcessInfo.batSuffix)", outputRedirection: .stream(stdout: { stdoutBytes in
            stdout += stdoutBytes
        }, stderr: { _ in }))
        let stdinStream = try process.launch()

        stdinStream.write("hello\(ProcessInfo.EOL)")
        stdinStream.flush()

        try stdinStream.close()

        try process.waitUntilExit()

        XCTAssertEqual(String(decoding: stdout, as: UTF8.self), "hello\(ProcessInfo.EOL)")
    }

    func testStdoutStdErr() throws {
        // A simple script to check that stdout and stderr are captured separatly.
        do {
            let result = try AsyncProcess.popen(scriptName: "simple-stdout-stderr\(ProcessInfo.batSuffix)")
            XCTAssertEqual(try result.utf8Output(), "simple output\(ProcessInfo.EOL)")
            XCTAssertEqual(try result.utf8stderrOutput(), "simple error\(ProcessInfo.EOL)")
        }

        // A long stdout and stderr output.
        do {
            let result = try AsyncProcess.popen(scriptName: "long-stdout-stderr\(ProcessInfo.batSuffix)")
            let count = 16 * 1024
            XCTAssertEqual(try result.utf8Output(), String(repeating: "1", count: count))
            XCTAssertEqual(try result.utf8stderrOutput(), String(repeating: "2", count: count))
        }

        // This script will block if the streams are not read.
        do {
            let result = try AsyncProcess.popen(scriptName: "deadlock-if-blocking-io\(ProcessInfo.batSuffix)")
            let count = 16 * 1024
            XCTAssertEqual(try result.utf8Output(), String(repeating: "1", count: count))
            XCTAssertEqual(try result.utf8stderrOutput(), String(repeating: "2", count: count))
        }
    }

    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    func testStdoutStdErrAsync() async throws {
        // A simple script to check that stdout and stderr are captured separatly.
        do {
            let result = try await AsyncProcess.popen(scriptName: "simple-stdout-stderr\(ProcessInfo.batSuffix)")
            XCTAssertEqual(try result.utf8Output(), "simple output\(ProcessInfo.EOL)")
            XCTAssertEqual(try result.utf8stderrOutput(), "simple error\(ProcessInfo.EOL)")
        }

        // A long stdout and stderr output.
        do {
            let result = try await AsyncProcess.popen(scriptName: "long-stdout-stderr\(ProcessInfo.batSuffix)")
            let count = 16 * 1024
            XCTAssertEqual(try result.utf8Output(), String(repeating: "1", count: count))
            XCTAssertEqual(try result.utf8stderrOutput(), String(repeating: "2", count: count))
        }

        // This script will block if the streams are not read.
        do {
            let result = try await AsyncProcess.popen(scriptName: "deadlock-if-blocking-io\(ProcessInfo.batSuffix)")
            let count = 16 * 1024
            XCTAssertEqual(try result.utf8Output(), String(repeating: "1", count: count))
            XCTAssertEqual(try result.utf8stderrOutput(), String(repeating: "2", count: count))
        }
    }

    func testStdoutStdErrRedirected() throws {
        // A simple script to check that stdout and stderr are captured in the same location.
        do {
            let process = AsyncProcess(
                scriptName: "simple-stdout-stderr\(ProcessInfo.batSuffix)",
                outputRedirection: .collect(redirectStderr: true)
            )
            try process.launch()
            let result = try process.waitUntilExit()
            #if os(Windows)
            let expectedStdout = "simple output\(ProcessInfo.EOL)"
            let expectedStderr = "simple error\(ProcessInfo.EOL)"
            #else
            let expectedStdout = "simple error\(ProcessInfo.EOL)simple output\(ProcessInfo.EOL)"
            let expectedStderr = ""
            #endif
            XCTAssertEqual(try result.utf8Output(), expectedStdout)
            XCTAssertEqual(try result.utf8stderrOutput(), expectedStderr)
        }

        // A long stdout and stderr output.
        do {
            let process = AsyncProcess(
                scriptName: "long-stdout-stderr\(ProcessInfo.batSuffix)",
                outputRedirection: .collect(redirectStderr: true)
            )
            try process.launch()
            let result = try process.waitUntilExit()

            let count = 16 * 1024
            #if os(Windows)
            let expectedStdout = String(repeating: "1", count: count)
            let expectedStderr = String(repeating: "2", count: count)
            #else
            let expectedStdout = String(repeating: "12", count: count)
            let expectedStderr = ""
            #endif
            XCTAssertEqual(try result.utf8Output(), expectedStdout)
            XCTAssertEqual(try result.utf8stderrOutput(), expectedStderr)
        }
    }

    func testStdoutStdErrStreaming() throws {
        var stdout = [UInt8]()
        var stderr = [UInt8]()
        let process = AsyncProcess(scriptName: "long-stdout-stderr\(ProcessInfo.batSuffix)", outputRedirection: .stream(stdout: { stdoutBytes in
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
        var stdout = [UInt8]()
        var stderr = [UInt8]()
        let process = AsyncProcess(scriptName: "long-stdout-stderr\(ProcessInfo.batSuffix)", outputRedirection: .stream(stdout: { stdoutBytes in
            stdout += stdoutBytes
        }, stderr: { stderrBytes in
            stderr += stderrBytes
        }, redirectStderr: true))
        try process.launch()
        try process.waitUntilExit()

        let count = 16 * 1024
        #if os(Windows)
        let expectedStdout = String(repeating: "1", count: count)
        let expectedStderr = String(repeating: "2", count: count)
        #else
        let expectedStdout = String(repeating: "12", count: count)
        let expectedStderr = ""
        #endif
        XCTAssertEqual(String(bytes: stdout, encoding: .utf8), expectedStdout)
        XCTAssertEqual(String(bytes: stderr, encoding: .utf8), expectedStderr)
    }

    func testWorkingDirectory() throws {
        #if !os(Windows)
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
                let process = AsyncProcess(arguments: catExecutableArgs + ["file"], workingDirectory: tempDirPath)
                try process.launch()
                let result = try process.waitUntilExit()
                XCTAssertEqual(try result.utf8Output(), "parent")
            }

            do {
                let process = AsyncProcess(arguments: catExecutableArgs + ["file"], workingDirectory: childPath.parentDirectory)
                try process.launch()
                let result = try process.waitUntilExit()
                XCTAssertEqual(try result.utf8Output(), "child")
            }
        }
    }

    func testAsyncStream() async throws {
        // rdar://133548796
        try XCTSkipIfPlatformCI()
        try XCTSkipOnWindows(because: "https://github.com/swiftlang/swift-package-manager/issues/8547: 'swift test' was hanging.")

        let (stdoutStream, stdoutContinuation) = AsyncProcess.ReadableStream.makeStream()
        let (stderrStream, stderrContinuation) = AsyncProcess.ReadableStream.makeStream()

        let process = AsyncProcess(
            scriptName: "echo\(ProcessInfo.batSuffix)",
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
                stdin.write("Hello \(counter)\(ProcessInfo.EOL)")
                stdin.flush()

                for await output in stdoutStream {
                    XCTAssertEqual(output, .init("Hello \(counter)\(ProcessInfo.EOL)".utf8))
                    counter += 1

                    stdin.write(.init("Hello \(counter)\(ProcessInfo.EOL)".utf8))
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
        try XCTSkipIfPlatformCI()
        try XCTSkipOnWindows(because: "https://github.com/swiftlang/swift-package-manager/issues/8547: 'swift test' was hanging.")

        let result = try await AsyncProcess.popen(
            scriptName: "echo\(ProcessInfo.batSuffix)", // maps to 'processInputs/echo' script
            stdout: { stdin, stdout in
                var counter = 0
                stdin.write("Hello \(counter)\(ProcessInfo.EOL)")
                stdin.flush()

                for await output in stdout {

                    XCTAssertEqual(output, .init("Hello \(counter)\(ProcessInfo.EOL)".utf8))
                    counter += 1

                    stdin.write(.init("Hello \(counter)\(ProcessInfo.EOL)".utf8))
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
            arguments: getAsyncProcessArgs(executable: AsyncProcess.script(scriptName)) + arguments,
            environment: .current,
            outputRedirection: outputRedirection
        )
    }

    @discardableResult
    fileprivate static func checkNonZeroExit(
        args: [String],
        environment: Environment = .current,
        loggingHandler: LoggingHandler? = .none
    ) async throws -> String {
        try await self.checkNonZeroExit(
            arguments: args,
            environment: environment,
            loggingHandler: loggingHandler
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
        try self.popen(arguments: getAsyncProcessArgs(executable: self.script(scriptName)), environment: .current, loggingHandler: loggingHandler)
    }

    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    @discardableResult
    fileprivate static func popen(
        scriptName: String,
        environment: Environment = .current,
        loggingHandler: LoggingHandler? = .none
    ) async throws -> AsyncProcessResult {
        try await self.popen(arguments: getAsyncProcessArgs(executable: self.script(scriptName)), environment: .current, loggingHandler: loggingHandler)
    }

    fileprivate static func popen(
        scriptName: String,
        stdout: @escaping AsyncProcess.DuplexStreamHandler,
        stderr: AsyncProcess.ReadableStreamHandler? = nil
    ) async throws -> AsyncProcessResult {
        try await self.popen(arguments: getAsyncProcessArgs(executable: self.script(scriptName)), stdoutHandler: stdout, stderrHandler: stderr)
    }
}

fileprivate func getAsyncProcessArgs(executable: String) -> [String] {
    #if os(Windows)
    let args = ["cmd.exe", "/c", executable]
    #else
    let args = [executable]
    #endif
    return args
}
