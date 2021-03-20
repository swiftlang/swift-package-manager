/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

@testable import Basics
import TSCBasic
import TSCUtility
import XCTest

final class SandboxTest: XCTestCase {
    #if os(macOS)
    func testSandbox() {
        let writableDirectories = (0 ..< Int.random(in: 5 ..< 10)).map { AbsolutePath.root.appending(components: "writable", "\($0)") }
        let command = Sandbox.apply(command: ["hello", "world"], writableDirectories: writableDirectories, strictness: .default)
        XCTAssertEqual(command.count, 5)
        XCTAssertEqual(command[0], "/usr/bin/sandbox-exec")
        XCTAssertEqual(command[1], "-p")
        XCTAssertEqual(command[3], "hello")
        XCTAssertEqual(command[4], "world")

        let sandbox = Array(command[2].split(separator: "\n"))
        XCTAssertEqual(sandbox.count, 5 + (writableDirectories.count + 2))
        XCTAssertEqual(sandbox[0], "(version 1)")
        XCTAssertEqual(sandbox[1], "(deny default)")
        XCTAssertEqual(sandbox[2], "(import \"system.sb\")")
        XCTAssertEqual(sandbox[3], "(allow file-read*)")
        XCTAssertEqual(sandbox[4], "(allow process*)")
        // writable directories
        XCTAssertEqual(sandbox[5], "(allow file-write*")
        for (index, directory) in writableDirectories.enumerated() {
            XCTAssertEqual(sandbox[6 + index], "    (subpath \"\(directory)\")")
        }
        XCTAssertEqual(sandbox[6 + writableDirectories.count], ")")
    }

    func testNonWritable() {
        let command = Sandbox.apply(command: ["hello", "world"], writableDirectories: [], strictness: .default)
        XCTAssertEqual(command.count, 5)
        XCTAssertEqual(command[0], "/usr/bin/sandbox-exec")
        XCTAssertEqual(command[1], "-p")
        XCTAssertEqual(command[3], "hello")
        XCTAssertEqual(command[4], "world")

        let sandbox = Array(command[2].split(separator: "\n"))
        XCTAssertEqual(sandbox.count, 5)
        XCTAssertEqual(sandbox[0], "(version 1)")
        XCTAssertEqual(sandbox[1], "(deny default)")
        XCTAssertEqual(sandbox[2], "(import \"system.sb\")")
        XCTAssertEqual(sandbox[3], "(allow file-read*)")
        XCTAssertEqual(sandbox[4], "(allow process*)")

        XCTAssertFalse(command[2].contains("allow file-write*"))
    }

    func testManifestPre53Sandbox() {
        let darwinCacheDirectories = TSCUtility.Platform.darwinCacheDirectories()
        let writableDirectories = (0 ..< Int.random(in: 5 ..< 10)).map { AbsolutePath.root.appending(components: "writable", "\($0)") }
        let command = Sandbox.apply(command: ["hello", "world"], writableDirectories: writableDirectories, strictness: .manifest_pre_53)
        XCTAssertEqual(command.count, 5)
        XCTAssertEqual(command[0], "/usr/bin/sandbox-exec")
        XCTAssertEqual(command[1], "-p")
        XCTAssertEqual(command[3], "hello")
        XCTAssertEqual(command[4], "world")

        let sandbox = Array(command[2].split(separator: "\n"))
        XCTAssertEqual(sandbox.count, 6 + (writableDirectories.count + darwinCacheDirectories.count + 2))
        XCTAssertEqual(sandbox[0], "(version 1)")
        XCTAssertEqual(sandbox[1], "(deny default)")
        XCTAssertEqual(sandbox[2], "(import \"system.sb\")")
        XCTAssertEqual(sandbox[3], "(allow file-read*)")
        XCTAssertEqual(sandbox[4], "(allow process*)")
        // manifest_pre_53
        XCTAssertEqual(sandbox[5], "(allow sysctl*)")
        // writable directories
        XCTAssertEqual(sandbox[6], "(allow file-write*")
        for (index, directory) in writableDirectories.enumerated() {
            XCTAssertEqual(sandbox[7 + index], "    (subpath \"\(directory)\")")
        }
        for (index, directory) in darwinCacheDirectories.enumerated() {
            XCTAssertEqual(sandbox[7 + writableDirectories.count + index], "    (regex #\"^\(directory)/org\\.llvm\\.clang.*\")")
        }
        XCTAssertEqual(sandbox[7 + writableDirectories.count + darwinCacheDirectories.count], ")")
    }

    #endif
}
