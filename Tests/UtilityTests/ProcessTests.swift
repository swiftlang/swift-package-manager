/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
import Basic
import libc
import Utility
import TestSupport

typealias ProcessID = Utility.Process.ProcessID

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
        let outputCount = try Process.popen(args: "cat", file.path.asString).utf8Output().characters.count
        XCTAssert(outputCount == count)
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

    static var allTests = [
        ("testBasics", testBasics),
        ("testPopen", testPopen),
        ("testSignals", testSignals),
        ("testThreadSafetyOnWaitUntilExit", testThreadSafetyOnWaitUntilExit),
    ]
}
