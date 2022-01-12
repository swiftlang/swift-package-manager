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

import Basics
import SPMTestSupport
import TSCBasic
import XCTest

final class SandboxTest: XCTestCase {

    func testDefaults() throws {
        let sandboxProfile = SandboxProfile()
        XCTAssertEqual(sandboxProfile.pathAccessRules, [])
        XCTAssertEqual(sandboxProfile.allowNetwork, false)
    }

    func testSandboxOnAllPlatforms() throws {
        try withTemporaryDirectory { path in
            let command = SandboxProfile()
                .apply(to: ["echo", "0"])
            XCTAssertNoThrow(try Process.checkNonZeroExit(arguments: command))
        }
    }

    func testNetworkNotAllowed() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "sandboxing is only supported on macOS")
        #endif

        /// Check that network access isn't allowed by default.
        let command = SandboxProfile()
            .apply(to: ["ping", "-t", "1", "localhost"])

        XCTAssertThrowsError(try Process.checkNonZeroExit(arguments: command)) { error in
            guard case ProcessResult.Error.nonZeroExit(let result) = error else {
                return XCTFail("invalid error \(error)")
            }
            XCTAssertMatch(try! result.utf8stderrOutput(), .contains("Operation not permitted"))
        }
    }

    func testWritableAllowed() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "sandboxing is only supported on macOS")
        #endif

        try withTemporaryDirectory { path in
            let command = SandboxProfile(.writable(path))
                .apply(to: ["touch", path.appending(component: UUID().uuidString).pathString])
            XCTAssertNoThrow(try Process.checkNonZeroExit(arguments: command))
        }
    }

    func testWritableNotAllowed() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "sandboxing is only supported on macOS")
        #endif

        try withTemporaryDirectory { path in
            let command = SandboxProfile()
                .apply(to: ["touch", path.appending(component: UUID().uuidString).pathString])
            XCTAssertThrowsError(try Process.checkNonZeroExit(arguments: command)) { error in
                guard case ProcessResult.Error.nonZeroExit(let result) = error else {
                    return XCTFail("invalid error \(error)")
                }
                XCTAssertMatch(try! result.utf8stderrOutput(), .contains("Operation not permitted"))
            }
        }
    }

    func testRemoveNotAllowed() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "sandboxing is only supported on macOS")
        #endif

        try withTemporaryDirectory { path in
            let file = path.appending(component: UUID().uuidString)
            XCTAssertNoThrow(try Process.checkNonZeroExit(arguments: ["touch", file.pathString]))

            let command = SandboxProfile()
                .apply(to: ["rm", file.pathString])
            XCTAssertThrowsError(try Process.checkNonZeroExit(arguments: command)) { error in
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
        try XCTSkipIf(true, "sandboxing is only supported on macOS")
        #endif

        try withTemporaryDirectory { path in
            let file = path.appending(component: UUID().uuidString)
            XCTAssertNoThrow(try Process.checkNonZeroExit(arguments: ["touch", file.pathString]))

            let command = SandboxProfile()
                .apply(to: ["cat", file.pathString])
            XCTAssertNoThrow(try Process.checkNonZeroExit(arguments: command))
        }
    }

    // FIXME: rdar://75707545 this should not be allowed outside very specific programs
    func testExecuteAllowed() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "sandboxing is only supported on macOS")
        #endif

        try withTemporaryDirectory { path in
            let scriptFile = path.appending(component: UUID().uuidString)
            XCTAssertNoThrow(try Process.checkNonZeroExit(arguments: ["touch", scriptFile.pathString]))
            XCTAssertNoThrow(try Process.checkNonZeroExit(arguments: ["chmod", "+x", scriptFile.pathString]))

            let command = SandboxProfile()
                .apply(to: [scriptFile.pathString])
            XCTAssertNoThrow(try Process.checkNonZeroExit(arguments: command))
        }
    }

    func testWritingToTemporaryDirectoryAllowed() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "sandboxing is only supported on macOS")
        #endif

        // Try writing to the per-user temporary directory, which is under `/var/folders/.../TemporaryItems` unless it
        // is overridden by the TMPDIR environment variable.
        let tmpFile = localFileSystem.tempDirectory.appending(component: UUID().uuidString)
        let command = SandboxProfile(.writable(localFileSystem.tempDirectory))
            .apply(to: ["touch", tmpFile.pathString])
        XCTAssertNoThrow(try Process.checkNonZeroExit(arguments: command))
        try? FileManager.default.removeItem(atPath: tmpFile.pathString)
    }

    func testWritingToReadOnlyInsideWritableNotAllowed() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "sandboxing is only supported on macOS")
        #endif

        try withTemporaryDirectory { tmpDir in
            // Check that we can write into the temporary directory, but not into a read-only directory underneath it.
            let writableDir = tmpDir.appending(component: "ShouldBeWritable")
            try localFileSystem.createDirectory(writableDir)
            let allowedCommand = SandboxProfile(.writable(writableDir))
                .apply(to: ["touch", writableDir.pathString])
            XCTAssertNoThrow(try Process.checkNonZeroExit(arguments: allowedCommand))

            // Check that we cannot write into a read-only directory inside a writable temporary directory.
            let readOnlyDir = writableDir.appending(component: "ShouldBeReadOnly")
            try localFileSystem.createDirectory(readOnlyDir)
            let deniedCommand = SandboxProfile(.writable(tmpDir), .readonly(readOnlyDir))
                .apply(to: ["touch", readOnlyDir.pathString])
            XCTAssertThrowsError(try Process.checkNonZeroExit(arguments: deniedCommand)) { error in
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
             let deniedCommand = SandboxProfile(.writable(tmpDir), .readonly(readOnlyDir))
                 .apply(to: ["touch", readOnlyDir.pathString])
             XCTAssertThrowsError(try Process.checkNonZeroExit(arguments: deniedCommand)) { error in
                 guard case ProcessResult.Error.nonZeroExit(let result) = error else {
                     return XCTFail("invalid error \(error)")
                 }
                 XCTAssertMatch(try! result.utf8stderrOutput(), .contains("Operation not permitted"))
             }

             // Check that we can write into a writable directory underneath it.
             let writableDir = readOnlyDir.appending(component: "ShouldBeWritable")
             try localFileSystem.createDirectory(writableDir)
             let allowedCommand = SandboxProfile(.readonly(readOnlyDir), .writable(writableDir))
                 .apply(to: ["touch", writableDir.pathString])
             XCTAssertNoThrow(try Process.checkNonZeroExit(arguments: allowedCommand))
         }
     }
}
