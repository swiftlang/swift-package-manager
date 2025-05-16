//
//  PIDTests.swift
//  SwiftPM
//
//  Created by John Bute on 2025-05-14.
//

import Basics
import Foundation
import Testing

struct PIDTests {
    @Test
    func testWritePIDMultipleCalls() throws {
        try withTemporaryDirectory { tmpDir in
            let scratchPath = tmpDir.appending(component: "scratch")
            try localFileSystem.createDirectory(scratchPath)

            let pidHandler = PIDFile(scratchDirectory: scratchPath)

            let pid1: Int32 = 1234
            let pid2: Int32 = 5678
            let pid3: Int32 = 9012

            try pidHandler.writePID(pid: pid1)
            try pidHandler.writePID(pid: pid2)
            try pidHandler.writePID(pid: pid3)

            #expect(throws: Never.self) {
                try pidHandler.readPID()
            }

            let pid = try pidHandler.readPID()

            #expect(pid == pid3)
        }
    }

    @Test
    func testDeleteExistingPIDFile() async throws {
        try withTemporaryDirectory { tmpDir in
            let scratchPath = tmpDir.appending(component: "scratch")
            try localFileSystem.createDirectory(scratchPath)

            let pidHandler = PIDFile(scratchDirectory: scratchPath)
            let currentPID = pidHandler.getCurrentPID()
            try pidHandler.writePID(pid: currentPID)

            #expect(throws: Never.self) {
                try pidHandler.deletePIDFile()
            }
        }
    }

    @Test
    func testDeleteNonExistingPIDFile() async throws {
        try withTemporaryDirectory { tmpDir in
            let filePath = tmpDir.appending(component: "scratch")

            let handler = PIDFile(scratchDirectory: filePath)

            #expect(throws: PIDFile.PIDError.noSuchPiDFile) {
                try handler.deletePIDFile()
            }
        }
    }

    @Test
    func testFileDoesNotExist() throws {
        // Create a temporary directory
        try withTemporaryDirectory { tmpDir in
            let filePath = tmpDir.appending(component: "scratch")
            let handler = PIDFile(scratchDirectory: filePath)

            #expect(throws: PIDFile.PIDError.noSuchPiDFile) {
                try handler.readPID()
            }
        }
    }

    @Test
    func testInvalidPIDFormat() async throws {
        // Create a temporary directory
        try withTemporaryDirectory { tmpDir in
            let scratchPath = tmpDir.appending(component: "scratch")
            try localFileSystem.createDirectory(scratchPath)

            let pidFilePath = scratchPath.appending(component: "PackageManager.lock.pid")
            let handler = PIDFile(scratchDirectory: scratchPath)

            // Write invalid content (non-numeric PID)
            let invalidPIDContent = "invalidPID"
            try localFileSystem.writeFileContents(pidFilePath, bytes: .init(encodingAsUTF8: invalidPIDContent))

            #expect(throws: PIDFile.PIDError.invalidPIDFormat) {
                try handler.readPID()
            }
        }
    }

    // Test case to check if the function works when a valid PID is in the file
    @Test
    func testValidPIDFormat() throws {
        // Create a temporary directory
        try withTemporaryDirectory { tmpDir in
            let scratchPath = tmpDir.appending(component: "scratch")
            try localFileSystem.createDirectory(scratchPath)

            let pidFilePath = scratchPath.appending(component: "PackageManager.lock.pid")

            let handler = PIDFile(scratchDirectory: scratchPath)

            // Write a valid PID content
            let validPIDContent = "12345"
            try localFileSystem.writeFileContents(pidFilePath, bytes: .init(encodingAsUTF8: validPIDContent))

            let pid = try handler.readPID()
            #expect(pid == 12345)
        }
    }

    @Test
    func testPIDFileHandlerLifecycle() throws {
        try withTemporaryDirectory { tmpDir in
            let scratchPath = tmpDir.appending(component: "scratch")
            try localFileSystem.createDirectory(scratchPath)

            let pidHandler = PIDFile(scratchDirectory: scratchPath)

            // Ensure no PID file exists initially
            #expect(throws: PIDFile.PIDError.noSuchPiDFile) {
                try pidHandler.readPID()
            }

            // Write current PID
            let currentPID = pidHandler.getCurrentPID()
            try pidHandler.writePID(pid: currentPID)

            // Read PID back
            let readPID = try pidHandler.readPID()
            #expect(readPID == currentPID, "PID read should match written PID")

            // Delete the file
            try pidHandler.deletePIDFile()

            // Ensure file is gone
            #expect(throws: PIDFile.PIDError.noSuchPiDFile) {
                try pidHandler.readPID()
            }
        }
    }

    @Test
    func testMalformedPIDFile() throws {
        try withTemporaryDirectory { tmpDir in
            let scratchPath = tmpDir.appending(component: "scratch")
            try localFileSystem.createDirectory(scratchPath)

            let pidPath = scratchPath.appending(component: "PackageManager.lock.pid")
            try localFileSystem.writeFileContents(pidPath, bytes: "notanumber")

            let pidHandler = PIDFile(scratchDirectory: scratchPath)
            #expect(throws: PIDFile.PIDError.invalidPIDFormat) {
                try pidHandler.readPID()
            }
        }
    }
}
