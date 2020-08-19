/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCTestSupport
import XCTest
import TSCLibc

import TSCBasic

typealias ProcessID = TSCBasic.Process.ProcessID
typealias Process = TSCBasic.Process

class ProcessTests: XCTestCase {
    func script(_ name: String) -> String {
        return AbsolutePath(#file).parentDirectory.appending(components: "processInputs", name).pathString
    }

    func testBasics() throws {
        do {
            let process = Process(args: "echo", "hello")
            try process.launch()
            let result = try process.waitUntilExit()
            XCTAssertEqual(try result.utf8Output(), "hello\n")
            XCTAssertEqual(result.exitStatus, .terminated(code: 0))
            XCTAssertEqual(result.arguments, process.arguments)
        }

        do {
            let process = Process(args: script("exit4"))
            try process.launch()
            let result = try process.waitUntilExit()
            XCTAssertEqual(result.exitStatus, .terminated(code: 4))
        }
    }

    func testPopen() throws {
        // Test basic echo.
        XCTAssertEqual(try Process.popen(arguments: ["echo", "hello"]).utf8Output(), "hello\n")

        // Test buffer larger than that allocated.
        try withTemporaryFile { file in
            let count = 10_000
            let stream = BufferedOutputByteStream()
            stream <<< Format.asRepeating(string: "a", count: count)
            try localFileSystem.writeFileContents(file.path, bytes: stream.bytes)
            let outputCount = try Process.popen(args: "cat", file.path.pathString).utf8Output().count
            XCTAssert(outputCount == count)
        }
    }

    func testCheckNonZeroExit() throws {
        do {
            let output = try Process.checkNonZeroExit(args: "echo", "hello")
            XCTAssertEqual(output, "hello\n")
        }

        do {
            let output = try Process.checkNonZeroExit(args: script("exit4"))
            XCTFail("Unexpected success \(output)")
        } catch ProcessResult.Error.nonZeroExit(let result) {
            XCTAssertEqual(result.exitStatus, .terminated(code: 4))
        }
    }

    func testFindExecutable() throws {
        mktmpdir { path in
            // This process should always work.
            XCTAssertTrue(Process.findExecutable("ls") != nil)

            XCTAssertEqual(Process.findExecutable("nonExistantProgram"), nil)
            XCTAssertEqual(Process.findExecutable(""), nil)

            // Create a local nonexecutable file to test.
            let tempExecutable = path.appending(component: "nonExecutableProgram")
            try localFileSystem.writeFileContents(tempExecutable, bytes: """
                #!/bin/sh
                exit

                """)

            try withCustomEnv(["PATH": path.pathString]) {
                XCTAssertEqual(Process.findExecutable("nonExecutableProgram"), nil)
            }
        }
    }

    func testNonExecutableLaunch() throws {
        mktmpdir { path in
            // Create a local nonexecutable file to test.
            let tempExecutable = path.appending(component: "nonExecutableProgram")
            try localFileSystem.writeFileContents(tempExecutable, bytes: """
                #!/bin/sh
                exit

                """)

            try withCustomEnv(["PATH": path.pathString]) {
                do {
                    let process = Process(args: "nonExecutableProgram")
                    try process.launch()
                    XCTFail("Should have failed to validate nonExecutableProgram")
                } catch Process.Error.missingExecutableProgram (let program){
                    XCTAssert(program == "nonExecutableProgram")
                }
            }
        }
    }

    func testSignals() throws {

        // Test sigint terminates the script.
        mktmpdir { path in
            let file = path.appending(component: "pidfile")
            let waitFile = path.appending(component: "waitFile")
            let process = Process(args: script("print-pid"), file.pathString, waitFile.pathString)
            try process.launch()
            guard waitForFile(waitFile) else {
                return XCTFail("Couldn't launch the process")
            }
            // Ensure process has started running.
            XCTAssertTrue(try Process.running(process.processID))
            process.signal(SIGINT)
            try process.waitUntilExit()
            // Ensure the process's pid was written.
            let contents = try localFileSystem.readFileContents(file).description
            XCTAssertEqual("\(process.processID)", contents)
            XCTAssertFalse(try Process.running(process.processID))
        }

        // Test SIGKILL terminates the subprocess and any of its subprocess.
        mktmpdir { path in
            let file = path.appending(component: "pidfile")
            let waitFile = path.appending(component: "waitFile")
            let process = Process(args: script("subprocess"), file.pathString, waitFile.pathString)
            try process.launch()
            guard waitForFile(waitFile) else {
                return XCTFail("Couldn't launch the process")
            }
            // Ensure process has started running.
            XCTAssertTrue(try Process.running(process.processID))
            process.signal(SIGKILL)
            let result = try process.waitUntilExit()
            XCTAssertEqual(result.exitStatus, .signalled(signal: SIGKILL))
            let json = try JSON(bytes: localFileSystem.readFileContents(file))
            guard case let .dictionary(dict) = json,
                  case let .int(parent)? = dict["parent"],
                  case let .int(child)? = dict["child"] else {
                return XCTFail("Couldn't launch the process")
            }
            XCTAssertEqual(process.processID, ProcessID(parent))
            // We should have killed the process and any subprocess spawned by it.
            XCTAssertFalse(try Process.running(ProcessID(parent)))
            // FIXME: The child process becomes defunct when executing the tests using docker directly without entering the bash.
            XCTAssertFalse(try Process.running(ProcessID(child), orDefunct: true))
        }
    }

    func testThreadSafetyOnWaitUntilExit() throws {
        let process = Process(args: "echo", "hello")
        try process.launch()

        var result1: String = ""
        var result2: String = ""

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

    func testStdoutStdErr() throws {
        // A simple script to check that stdout and stderr are captured separatly.
        do {
            let result = try Process.popen(args: script("simple-stdout-stderr"))
            XCTAssertEqual(try result.utf8Output(), "simple output\n")
            XCTAssertEqual(try result.utf8stderrOutput(), "simple error\n")
        }

        // A long stdout and stderr output.
        do {
            let result = try Process.popen(args: script("long-stdout-stderr"))
            let count = 16 * 1024
            XCTAssertEqual(try result.utf8Output(), String(repeating: "1", count: count))
            XCTAssertEqual(try result.utf8stderrOutput(), String(repeating: "2", count: count))
        }

        // This script will block if the streams are not read.
        do {
            let result = try Process.popen(args: script("deadlock-if-blocking-io"))
            let count = 16 * 1024
            XCTAssertEqual(try result.utf8Output(), String(repeating: "1", count: count))
            XCTAssertEqual(try result.utf8stderrOutput(), String(repeating: "2", count: count))
        }
    }

    func testStdoutStdErrRedirected() throws {
        // A simple script to check that stdout and stderr are captured in the same location.
        do {
            let process = Process(args: script("simple-stdout-stderr"), outputRedirection: .collect(redirectStderr: true))
            try process.launch()
            let result = try process.waitUntilExit()
            XCTAssertEqual(try result.utf8Output(), "simple error\nsimple output\n")
            XCTAssertEqual(try result.utf8stderrOutput(), "")
        }

        // A long stdout and stderr output.
        do {
            let process = Process(args: script("long-stdout-stderr"), outputRedirection: .collect(redirectStderr: true))
            try process.launch()
            let result = try process.waitUntilExit()

            let count = 16 * 1024
            XCTAssertEqual(try result.utf8Output(), String(repeating: "12", count: count))
            XCTAssertEqual(try result.utf8stderrOutput(), "")
        }
    }

    func testStdoutStdErrStreaming() throws {
        var stdout = [UInt8]()
        var stderr = [UInt8]()
        let process = Process(args: script("long-stdout-stderr"), outputRedirection: .stream(stdout: { stdoutBytes in
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
        let process = Process(args: script("long-stdout-stderr"), outputRedirection: .stream(stdout: { stdoutBytes in
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
                let process = Process(arguments: ["cat", "file"], workingDirectory: tempDirPath)
                try process.launch()
                let result = try process.waitUntilExit()
                XCTAssertEqual(try result.utf8Output(), "parent")
            }

            do {
                let process = Process(arguments: ["cat", "file"], workingDirectory: childPath.parentDirectory)
                try process.launch()
                let result = try process.waitUntilExit()
                XCTAssertEqual(try result.utf8Output(), "child")
            }
        }
    }
}
