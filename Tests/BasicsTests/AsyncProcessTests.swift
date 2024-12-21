/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */
import Foundation

import _InternalTestSupport
import _Concurrency
import Basics
import Testing

import TSCclibc // for SPM_posix_spawn_file_actions_addchdir_np_supported

import class TSCBasic.BufferedOutputByteStream
import struct TSCBasic.ByteString
import struct TSCBasic.Format
import class TSCBasic.Thread
import func TSCBasic.withTemporaryFile
import func TSCTestSupport.withCustomEnv

@Suite(
    // because suite is very flaky otherwise. Need to investigate whether the tests can run in parallel
    .serialized
)
struct AsyncProcessTests {
    @Test
    func basics() throws {
        do {
            let process = AsyncProcess(args: "echo", "hello")
            try process.launch()
            let result = try process.waitUntilExit()
            #expect(try result.utf8Output() == "hello\n")
            #expect(result.exitStatus == .terminated(code: 0))
            #expect(result.arguments == process.arguments)
        }

        do {
            let process = AsyncProcess(scriptName: "exit4")
            try process.launch()
            let result = try process.waitUntilExit()
            #expect(result.exitStatus == .terminated(code: 4))
        }
    }

    @Test
    func popen() throws {
#if os(Windows)
        let echo = "echo.exe"
#else
        let echo = "echo"
#endif
        // Test basic echo.
        #expect(try AsyncProcess.popen(arguments: [echo, "hello"]).utf8Output() == "hello\n")

        // Test buffer larger than that allocated.
        try withTemporaryFile { file in
            let count = 10000
            let stream = BufferedOutputByteStream()
            stream.send(Format.asRepeating(string: "a", count: count))
            try localFileSystem.writeFileContents(file.path, bytes: stream.bytes)
#if os(Windows)
            let cat = "cat.exe"
#else
            let cat = "cat"
#endif
            let outputCount = try AsyncProcess.popen(args: cat, file.path.pathString).utf8Output().count
            #expect(outputCount == count)
        }
    }

    @Test
    func popenLegacyAsync() throws {
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
                #expect(output.hasPrefix(answer))
            case .failure(let error):
                throw error
            case nil:
                Issue.record("AsyncProcess.popen did not yield a result!")
        }
    }

    @Test
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    func popenAsync() async throws {
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
            throw error
        }
        let output = try processResult.utf8Output()
        #expect(output.hasPrefix(answer))
    }

    @Test
    func checkNonZeroExit() throws {
        do {
            let output = try AsyncProcess.checkNonZeroExit(args: "echo", "hello")
            #expect(output == "hello\n")
        }

        do {
            let output = try AsyncProcess.checkNonZeroExit(scriptName: "exit4")
            Issue.record("Unexpected success \(output)")
        } catch AsyncProcessResult.Error.nonZeroExit(let result) {
            #expect(result.exitStatus == .terminated(code: 4))
        }
    }

    @Test
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    func checkNonZeroExitAsync() async throws {
        do {
            let output = try await AsyncProcess.checkNonZeroExit(args: "echo", "hello")
            #expect(output == "hello\n")
        }

        do {
            let output = try await AsyncProcess.checkNonZeroExit(scriptName: "exit4")
            Issue.record("Unexpected success \(output)")
        } catch AsyncProcessResult.Error.nonZeroExit(let result) {
            #expect(result.exitStatus == .terminated(code: 4))
        }
    }

    @Test
    func findExecutable() throws {
        try testWithTemporaryDirectory { tmpdir in
            // This process should always work.
            #expect(AsyncProcess.findExecutable("ls") != nil)

            #expect(AsyncProcess.findExecutable("nonExistantProgram") == nil)
            #expect(AsyncProcess.findExecutable("") == nil)

            // Create a local nonexecutable file to test.
            let tempExecutable = tmpdir.appending(component: "nonExecutableProgram")
            try localFileSystem.writeFileContents(tempExecutable, bytes: """
            #!/bin/sh
            exit

            """)

            try withCustomEnv(["PATH": tmpdir.pathString]) {
                #expect(AsyncProcess.findExecutable("nonExecutableProgram") == nil)
            }
        }
    }

    @Test
    func nonExecutableLaunch() throws {
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
                    Issue.record("Should have failed to validate nonExecutableProgram")
                } catch AsyncProcess.Error.missingExecutableProgram(let program) {
                    #expect(program == "nonExecutableProgram")
                }
            }
        }
    }

    @Test
    func threadSafetyOnWaitUntilExit() throws {
        let process = AsyncProcess(args: "echo", "hello")
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

        #expect(result1 == "hello\n")
        #expect(result2 == "hello\n")
    }

    @Test
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    func threadSafetyOnWaitUntilExitAsync() async throws {
        let process = AsyncProcess(args: "echo", "hello")
        try process.launch()

        let t1 = Task {
            try await process.waitUntilExit().utf8Output()
        }

        let t2 = Task {
            try await process.waitUntilExit().utf8Output()
        }

        let result1 = try await t1.value
        let result2 = try await t2.value

        #expect(result1 == "hello\n")
        #expect(result2 == "hello\n")
    }

    @Test
    func stdin() throws {
        var stdout = [UInt8]()
        let process = AsyncProcess(scriptName: "in-to-out", outputRedirection: .stream(stdout: { stdoutBytes in
            stdout += stdoutBytes
        }, stderr: { _ in }))
        let stdinStream = try process.launch()

        stdinStream.write("hello\n")
        stdinStream.flush()

        try stdinStream.close()

        try process.waitUntilExit()

        #expect(String(decoding: stdout, as: UTF8.self) == "hello\n")
    }

    @Test
    func stdoutStdErr() throws {
        do {
            let result = try AsyncProcess.popen(scriptName: "simple-stdout-stderr")
            #expect(try result.utf8Output() == "simple output\n")
            #expect(try result.utf8stderrOutput() == "simple error\n")
        }

        // A long stdout and stderr output.
        do {
            let result = try AsyncProcess.popen(scriptName: "long-stdout-stderr")
            let count = 16 * 1024
            #expect(try result.utf8Output() == String(repeating: "1", count: count))
            #expect(try result.utf8stderrOutput() == String(repeating: "2", count: count))
        }

        // This script will block if the streams are not read.
        do {
            let result = try AsyncProcess.popen(scriptName: "deadlock-if-blocking-io")
            let count = 16 * 1024
            #expect(try result.utf8Output() == String(repeating: "1", count: count))
            #expect(try result.utf8stderrOutput() == String(repeating: "2", count: count))
        }
    }

    @Test
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    func stdoutStdErrAsync() async throws {
        // A simple script to check that stdout and stderr are captured separatly
        do {
            let result = try await AsyncProcess.popen(scriptName: "simple-stdout-stderr")
            #expect(try result.utf8Output() == "simple output\n")
            #expect(try result.utf8stderrOutput() == "simple error\n")
        }

        // A long stdout and stderr output.
        do {
            let result = try await AsyncProcess.popen(scriptName: "long-stdout-stderr")
            let count = 16 * 1024
            #expect(try result.utf8Output() == String(repeating: "1", count: count))
            #expect(try result.utf8stderrOutput() == String(repeating: "2", count: count))
        }

        // This script will block if the streams are not read.
        do {
            let result = try await AsyncProcess.popen(scriptName: "deadlock-if-blocking-io")
            let count = 16 * 1024
            #expect(try result.utf8Output() == String(repeating: "1", count: count))
            #expect(try result.utf8stderrOutput() == String(repeating: "2", count: count))
        }
    }

    @Test
    func stdoutStdErrRedirected() throws {
        do {
            let process = AsyncProcess(
                scriptName: "simple-stdout-stderr",
                outputRedirection: .collect(redirectStderr: true)
            )
            try process.launch()
            let result = try process.waitUntilExit()
            #expect(try result.utf8Output() == "simple error\nsimple output\n")
            #expect(try result.utf8stderrOutput() == "")
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
            #expect(try result.utf8Output() == String(repeating: "12", count: count))
            #expect(try result.utf8stderrOutput() == "")
        }
    }

    @Test
    func stdoutStdErrStreaming() throws {
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
        #expect(String(bytes: stdout, encoding: .utf8) == String(repeating: "1", count: count))
        #expect(String(bytes: stderr, encoding: .utf8) == String(repeating: "2", count: count))
    }

    @Test
    func stdoutStdErrStreamingRedirected() throws {
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
        #expect(String(bytes: stdout, encoding: .utf8) == String(repeating: "12", count: count))
        #expect(stderr == [])
    }

    @Test
    @available(macOS 10.15, *)
    func workingDirectory() throws {

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
                let process = AsyncProcess(arguments: ["cat", "file"], workingDirectory: tempDirPath)
                try process.launch()
                let result = try process.waitUntilExit()
                #expect(try result.utf8Output() == "parent")
            }

            do {
                let process = AsyncProcess(arguments: ["cat", "file"], workingDirectory: childPath.parentDirectory)
                try process.launch()
                let result = try process.waitUntilExit()
                #expect(try result.utf8Output() == "child")
            }
        }
    }

    @Test(
        .disabled(if: isRunninginCI(), "Disabled in CI"),
        .bug("rdar://133548796")
    )
    func asyncStream() async throws {
        let (stdoutStream, stdoutContinuation) = AsyncProcess.ReadableStream.makeStream()
        let (stderrStream, stderrContinuation) = AsyncProcess.ReadableStream.makeStream()

        let process = AsyncProcess(
            scriptName: "echo",
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
                    #expect(output == .init("Hello \(counter)\n".utf8))
                    counter += 1

                    stdin.write(.init("Hello \(counter)\n".utf8))
                    stdin.flush()
                }

                #expect(counter == 5)

                try stdin.close()
            }

            group.addTask {
                var counter = 0
                for await _ in stderrStream {
                    counter += 1
                }

                #expect(counter == 0)
            }

            defer {
                stdoutContinuation.finish()
                stderrContinuation.finish()
            }

            return try await process.waitUntilExit()
        }

        #expect(result.exitStatus == .terminated(code: 0))
    }

    @Test(
        .disabled(if: isRunninginCI(), "Disabled in CI"),
        .bug("rdar://133548796")
    )
    func asyncStreamHighLevelAPI() async throws {
        let result = try await AsyncProcess.popen(
            scriptName: "echo",
            stdout: { stdin, stdout in
                var counter = 0
                stdin.write("Hello \(counter)\n")
                stdin.flush()

                for await output in stdout {
                    #expect(output == .init("Hello \(counter)\n".utf8))
                    counter += 1

                    stdin.write(.init("Hello \(counter)\n".utf8))
                    stdin.flush()
                }

                #expect(counter == 5)

                try stdin.close()
            },
            stderr: { stderr in
                var counter = 0
                for await _ in stderr {
                    counter += 1
                }

                #expect(counter == 0)
            }
        )

        #expect(result.exitStatus == .terminated(code: 0))
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
