/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TestSupport
import XCTest
import libc

@testable import Basic

typealias ProcessID = Basic.Process.ProcessID
typealias Process = Basic.Process

class ProcessTests: XCTestCase {
    func script(_ name: String) -> String {
        return AbsolutePath(#file).parentDirectory.appending(components: "processInputs", name).asString
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
        let file = try TemporaryFile()
        let count = 10_000
        let stream = BufferedOutputByteStream()
        stream <<< Format.asRepeating(string: "a", count: count)
        try localFileSystem.writeFileContents(file.path, bytes: stream.bytes)
        let outputCount = try Process.popen(args: "cat", file.path.asString).utf8Output().count
        XCTAssert(outputCount == count)
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
            XCTAssertTrue(Process().findExecutable("ls"))

            XCTAssertFalse(Process().findExecutable("nonExistantProgram"))
            XCTAssertFalse(Process().findExecutable(""))

            // Create a local nonexecutable file to test.
            let tempExecutable = path.appending(component: "nonExecutableProgram")
            try localFileSystem.writeFileContents(tempExecutable, bytes: """
                #!/bin/sh
                exit
                
                """)

            try withCustomEnv(["PATH": path.asString]) {
                XCTAssertFalse(Process().findExecutable("nonExecutableProgram"))
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

            try withCustomEnv(["PATH": path.asString]) {
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
            let process = Process(args: script("print-pid"), file.asString, waitFile.asString)
            try process.launch()
            guard waitForFile(waitFile) else {
                return XCTFail("Couldn't launch the process")
            }
            // Ensure process has started running.
            XCTAssertTrue(try Process.running(process.processID))
            process.signal(SIGINT)
            try process.waitUntilExit()
            // Ensure the process's pid was written.
            let contents = try localFileSystem.readFileContents(file).asString!
            XCTAssertEqual("\(process.processID)", contents)
            XCTAssertFalse(try Process.running(process.processID))
        }

        // Test SIGKILL terminates the subprocess and any of its subprocess.
        mktmpdir { path in
            let file = path.appending(component: "pidfile")
            let waitFile = path.appending(component: "waitFile")
            let process = Process(args: script("subprocess"), file.asString, waitFile.asString)
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
            XCTAssertEqual(try result.utf8stderrOutput(), "simple error")
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

    static var allTests = [
        ("testBasics", testBasics),
        ("testCheckNonZeroExit", testCheckNonZeroExit),
        ("testFindExecutable", testFindExecutable),
        ("testNonExecutableLaunch", testNonExecutableLaunch),
        ("testPopen", testPopen),
        ("testSignals", testSignals),
        ("testThreadSafetyOnWaitUntilExit", testThreadSafetyOnWaitUntilExit),
        ("testStdoutStdErr", testStdoutStdErr),
    ]
}
