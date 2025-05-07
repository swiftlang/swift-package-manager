//
//  PID.swift
//  SwiftPM
//
//  Created by John Bute on 2025-04-24.
//

import Foundation

public protocol PIDFileHandler {
    var scratchDirectory: AbsolutePath {get set}

    init(scratchDirectory: AbsolutePath)
    
    func readPID() -> Int32?
    func deletePIDFile() throws
    func writePID(pid: pid_t) throws
    func getCurrentPID() -> Int32
}



public struct PIDFile: PIDFileHandler {
    
    public var scratchDirectory: AbsolutePath
    
    public init(scratchDirectory: AbsolutePath) {
        self.scratchDirectory = scratchDirectory
    }
    
    /// Return the path of the PackageManager.lock.pid file where the PID is located
    private var lockFilePath: AbsolutePath {
        return self.scratchDirectory.appending(component: "PackageManager.lock.pid")
    }

    /// Read the pid file
    public func readPID() -> Int32? {
        // Check if the file exists
        let filePath = lockFilePath.pathString
        guard FileManager.default.fileExists(atPath: filePath)  else {
            print("File does not exist at path: \(filePath)")
            return nil
        }

        do {
            // Read the contents of the file
            let pidString = try String(contentsOf: lockFilePath.asURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)

            // Check if the PID string can be converted to an Int32
            if let pid = Int32(pidString) {
                return pid
            } else {
                return nil
            }
        } catch {
            // Catch any errors and print them
            return nil
        }
    }

    /// Get the current PID of the process
    public func getCurrentPID() -> Int32 {
        return getpid()
    }

    /// Write .pid file containing PID of process currently using .build directory
    public func writePID(pid: pid_t) throws {
        try "\(pid)".write(to: lockFilePath.asURL, atomically: true, encoding: .utf8)
    }
    
    /// Delete PID file at URL
    public func deletePIDFile() throws {
        try FileManager.default.removeItem(at: lockFilePath.asURL)
    }

}
