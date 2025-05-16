//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

public protocol PIDFileHandler {
    var scratchDirectory: AbsolutePath { get set }

    init(scratchDirectory: AbsolutePath)

    func readPID() throws -> Int32
    func deletePIDFile() throws
    func writePID(pid: Int32) throws
    func getCurrentPID() -> Int32
}

public struct PIDFile: PIDFileHandler {
    public var scratchDirectory: AbsolutePath

    public init(scratchDirectory: AbsolutePath) {
        self.scratchDirectory = scratchDirectory
    }

    /// Return the path of the PackageManager.lock.pid file where the PID is located
    private var lockFilePath: AbsolutePath {
        self.scratchDirectory.appending(component: "PackageManager.lock.pid")
    }

    /// Read the pid file
    public func readPID() throws -> Int32 {
        // Check if the file exists
        let filePath = self.lockFilePath.pathString
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw PIDError.noSuchPiDFile
        }

        let pidString = try String(contentsOf: lockFilePath.asURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to convert to Int32, or throw an error
        guard let pid = Int32(pidString) else {
            throw PIDError.invalidPIDFormat
        }

        return pid
    }

    /// Get the current PID of the proces
    public func getCurrentPID() -> Int32 {
        ProcessInfo.processInfo.processIdentifier
    }

    /// Write .pid file containing PID of process currently using .build directory
    public func writePID(pid: Int32) throws {
        let parent = self.lockFilePath.parentDirectory
        try FileManager.default.createDirectory(
            at: parent.asURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        try "\(pid)".write(to: self.lockFilePath.asURL, atomically: true, encoding: .utf8)
    }

    /// Delete PID file at URL
    public func deletePIDFile() throws {
        do {
            try FileManager.default.removeItem(at: self.lockFilePath.asURL)
        } catch {
            throw PIDError.noSuchPiDFile
        }
    }

    public enum PIDError: Error {
        case invalidPIDFormat
        case noSuchPiDFile
    }
}
