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

    func testDefaults() throws {
        let sandboxProfile = SandboxProfile()
        XCTAssertEqual(sandboxProfile.pathAccessRules, [])
    }

    func testSandboxOnAllPlatforms() throws {
        try withTemporaryDirectory { path in
            let profile = SandboxProfile()
#if os(Windows)
            let command = try profile.apply(to: ["tar.exe", "-h"])
#else
            let command = try profile.apply(to: ["echo", "0"])
#endif
            XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: command))
        }
    }

    func testNetworkNotAllowed() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "sandboxing is only supported on macOS")
        #endif

        /// Check that network access isn't allowed by default.
        let profile = SandboxProfile()
        let command = try profile.apply(to: ["ping", "-t", "1", "localhost"])

        XCTAssertThrowsError(try TSCBasic.Process.checkNonZeroExit(arguments: command)) { error in
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
            let profile = SandboxProfile([.writable(path)])
            let command = try profile.apply(to: ["touch", path.appending(component: UUID().uuidString).pathString])
            XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: command))
        }
    }

    func testWritableNotAllowed() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "sandboxing is only supported on macOS")
        #endif

        try withTemporaryDirectory { path in
            let profile = SandboxProfile()
            let command = try profile.apply(to: ["touch", path.appending(component: UUID().uuidString).pathString])
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
        try XCTSkipIf(true, "sandboxing is only supported on macOS")
        #endif

        try withTemporaryDirectory { path in
            let file = path.appending(component: UUID().uuidString)
            XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: ["touch", file.pathString]))

            let profile = SandboxProfile()
            let command = try profile.apply(to: ["rm", file.pathString])
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
        try XCTSkipIf(true, "sandboxing is only supported on macOS")
        #endif

        try withTemporaryDirectory { path in
            let file = path.appending(component: UUID().uuidString)
            XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: ["touch", file.pathString]))

            let profile = SandboxProfile()
            let command = try profile.apply(to: ["cat", file.pathString])
            XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: command))
        }
    }

    // FIXME: rdar://75707545 this should not be allowed outside very specific programs
    func testExecuteAllowed() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "sandboxing is only supported on macOS")
        #endif

        try withTemporaryDirectory { path in
            let scriptFile = path.appending(component: UUID().uuidString)
            XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: ["touch", scriptFile.pathString]))
            XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: ["chmod", "+x", scriptFile.pathString]))

            let profile = SandboxProfile()
            let command = try profile.apply(to: [scriptFile.pathString])
            XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: command))
        }
    }

    func testWritingToTemporaryDirectoryAllowed() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "sandboxing is only supported on macOS")
        #endif

        // Try writing to the per-user temporary directory, which is under `/var/folders/.../TemporaryItems` unless it
        // is overridden by the TMPDIR environment variable.
        let tmpFile = try localFileSystem.tempDirectory.appending(component: UUID().uuidString)
        let profile = SandboxProfile([.writable(try localFileSystem.tempDirectory)])
        let command = try profile.apply(to: ["touch", tmpFile.pathString])
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
            let allowanceProfile = SandboxProfile([.writable(writableDir)])
            let allowedCommand = try allowanceProfile.apply(to: ["touch", writableDir.pathString])
            XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: allowedCommand))

            // Check that we cannot write into a read-only directory inside a writable temporary directory.
            let readOnlyDir = writableDir.appending(component: "ShouldBeReadOnly")
            try localFileSystem.createDirectory(readOnlyDir)
            let denialProfile = SandboxProfile([.writable(tmpDir), .readonly(readOnlyDir)])
            let deniedCommand = try denialProfile.apply(to: ["touch", readOnlyDir.pathString])
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
             let denialProfile = SandboxProfile([.writable(tmpDir), .readonly(readOnlyDir)])
             let deniedCommand = try denialProfile.apply(to: ["touch", readOnlyDir.pathString])
             XCTAssertThrowsError(try TSCBasic.Process.checkNonZeroExit(arguments: deniedCommand)) { error in
                 guard case ProcessResult.Error.nonZeroExit(let result) = error else {
                     return XCTFail("invalid error \(error)")
                 }
                 XCTAssertMatch(try! result.utf8stderrOutput(), .contains("Operation not permitted"))
             }

             // Check that we can write into a writable directory underneath it.
             let writableDir = readOnlyDir.appending(component: "ShouldBeWritable")
             try localFileSystem.createDirectory(writableDir)
             let allowanceProfile = SandboxProfile([.readonly(readOnlyDir), .writable(writableDir)])
             let allowedCommand = try allowanceProfile.apply(to: ["touch", writableDir.pathString])
             XCTAssertNoThrow(try TSCBasic.Process.checkNonZeroExit(arguments: allowedCommand))
         }
     }
}
