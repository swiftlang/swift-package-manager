//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@testable import Basics
import SPMTestSupport
import TSCBasic
import XCTest

final class SandboxTest: XCTestCase {
    func testSandboxOnAllPlatforms() throws {
        try withTemporaryDirectory { path in
#if os(Windows)
            let command = Sandbox.apply(command: ["tar.exe", "-h"], strictness: .default, writableDirectories: [])
#else
            let command = Sandbox.apply(command: ["echo", "0"], strictness: .default, writableDirectories: [])
#endif
            XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: command))
        }
    }

    func testNetworkNotAllowed() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif

        let command = Sandbox.apply(command: ["ping", "-t", "1", "localhost"], strictness: .default, writableDirectories: [])

        XCTAssertThrowsError(try TSCBasic.Process.checkNonZeroExit(arguments: command)) { error in
            guard case ProcessResult.Error.nonZeroExit(let result) = error else {
                return XCTFail("invalid error \(error)")
            }
            XCTAssertMatch(try! result.utf8stderrOutput(), .contains("Operation not permitted"))
        }
    }

    func testWritableAllowed() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif

        try withTemporaryDirectory { path in
            let command = Sandbox.apply(command: ["touch", path.appending(component: UUID().uuidString).pathString], strictness: .default, writableDirectories: [path])
            XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: command))
        }
    }

    func testWritableNotAllowed() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif

        try withTemporaryDirectory { path in
            let command = Sandbox.apply(command: ["touch", path.appending(component: UUID().uuidString).pathString], strictness: .default, writableDirectories: [])
            XCTAssertThrowsError(try TSCBasic.Process.checkNonZeroExit(arguments: command)) { error in
                guard case ProcessResult.Error.nonZeroExit(let result) = error else {
                    return XCTFail("invalid error \(error)")
                }
                XCTAssertMatch(try! result.utf8stderrOutput(), .contains("Operation not permitted"))
            }
        }
    }

    func testRemoveNotAllowed() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif

        try withTemporaryDirectory { path in
            let file = path.appending(component: UUID().uuidString)
            XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: ["touch", file.pathString]))

            let command = Sandbox.apply(command: ["rm", file.pathString], strictness: .default, writableDirectories: [])
            XCTAssertThrowsError(try TSCBasic.Process.checkNonZeroExit(arguments: command)) { error in
                guard case ProcessResult.Error.nonZeroExit(let result) = error else {
                    return XCTFail("invalid error \(error)")
                }
                XCTAssertMatch(try! result.utf8stderrOutput(), .contains("Operation not permitted"))
            }
        }
    }

    // FIXME: rdar://75707545 this should not be allowed outside very specific read locations
    func testReadAllowed() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif

        try withTemporaryDirectory { path in
            let file = path.appending(component: UUID().uuidString)
            XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: ["touch", file.pathString]))

            let command = Sandbox.apply(command: ["cat", file.pathString], strictness: .default, writableDirectories: [])
            XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: command))
        }
    }

    // FIXME: rdar://75707545 this should not be allowed outside very specific programs
    func testExecuteAllowed() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif

        try withTemporaryDirectory { path in
            let file = path.appending(component: UUID().uuidString)
            XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: ["touch", file.pathString]))
            XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: ["chmod", "+x", file.pathString]))

            let command = Sandbox.apply(command: [file.pathString], strictness: .default, writableDirectories: [])
            XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: command))
        }
    }

    func testWritingToTemporaryDirectoryAllowed() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif

        // Try writing to the per-user temporary directory, which is under /var/folders/.../TemporaryItems.
        let tmpFile1 = NSTemporaryDirectory() + "/" + UUID().uuidString
        let command1 = Sandbox.apply(command: ["touch", tmpFile1], strictness: .writableTemporaryDirectory)
        XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: command1))
        try? FileManager.default.removeItem(atPath: tmpFile1)

        let tmpFile2 = "/tmp" + "/" + UUID().uuidString
        let command2 = Sandbox.apply(command: ["touch", tmpFile2], strictness: .writableTemporaryDirectory)
        XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: command2))
        try? FileManager.default.removeItem(atPath: tmpFile2)
    }

    func testWritingToReadOnlyInsideWritableNotAllowed() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "sandboxing is only supported on macOS")
        #endif

        try withTemporaryDirectory { tmpDir in
            // Check that we can write into the temporary directory, but not into a read-only directory underneath it.
            let writableDir = tmpDir.appending(component: "ShouldBeWritable")
            try localFileSystem.createDirectory(writableDir)
            let allowedCommand = Sandbox.apply(command: ["touch", writableDir.pathString], strictness: .default, writableDirectories: [writableDir])
            XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: allowedCommand))

            // Check that we cannot write into a read-only directory inside a writable temporary directory.
            let readOnlyDir = writableDir.appending(component: "ShouldBeReadOnly")
            try localFileSystem.createDirectory(readOnlyDir)
            let deniedCommand = Sandbox.apply(command: ["touch", readOnlyDir.pathString], strictness: .writableTemporaryDirectory, readOnlyDirectories: [readOnlyDir])
            XCTAssertThrowsError(try TSCBasic.Process.checkNonZeroExit(arguments: deniedCommand)) { error in
                guard case ProcessResult.Error.nonZeroExit(let result) = error else {
                    return XCTFail("invalid error \(error)")
                }
                XCTAssertMatch(try! result.utf8stderrOutput(), .contains("Operation not permitted"))
            }
        }
    }

    func testWritingToWritableInsideReadOnlyAllowed() throws {
         #if !os(macOS)
         try XCTSkipIf(true, "sandboxing is only supported on macOS")
         #endif

         try withTemporaryDirectory { tmpDir in
             // Check that we cannot write into a read-only directory, but into a writable directory underneath it.
             let readOnlyDir = tmpDir.appending(component: "ShouldBeReadOnly")
             try localFileSystem.createDirectory(readOnlyDir)
             let deniedCommand = Sandbox.apply(command: ["touch", readOnlyDir.pathString], strictness: .writableTemporaryDirectory, readOnlyDirectories: [readOnlyDir])
             XCTAssertThrowsError(try TSCBasic.Process.checkNonZeroExit(arguments: deniedCommand)) { error in
                 guard case ProcessResult.Error.nonZeroExit(let result) = error else {
                     return XCTFail("invalid error \(error)")
                 }
                 XCTAssertMatch(try! result.utf8stderrOutput(), .contains("Operation not permitted"))
             }

             // Check that we can write into a writable directory underneath it.
             let writableDir = readOnlyDir.appending(component: "ShouldBeWritable")
             try localFileSystem.createDirectory(writableDir)
             let allowedCommand = Sandbox.apply(command: ["touch", writableDir.pathString], strictness: .default, writableDirectories:[writableDir], readOnlyDirectories: [readOnlyDir])
             XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: allowedCommand))
         }
     }
}
