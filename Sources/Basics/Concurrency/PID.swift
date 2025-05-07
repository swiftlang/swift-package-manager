//
//  PID.swift
//  SwiftPM
//
//  Created by John Bute on 2025-04-24.
//

import Foundation

public protocol pidFileManipulator {
    var scratchDirectory: AbsolutePath {get set}
    var pidFilePath: AbsolutePath { get }

    init(scratchDirectory: AbsolutePath)

    
    func readPID(from path: AbsolutePath) -> Int32?
    func deletePIDFile(file: URL) throws
    func writePID(pid: pid_t, to: URL, atomically: Bool, encoding: String.Encoding) throws
    func getCurrentPID() -> Int32
}



public struct pidFile: pidFileManipulator {
    
    public var scratchDirectory: AbsolutePath
    
    public init(scratchDirectory: AbsolutePath) {
        self.scratchDirectory = scratchDirectory
    }
    
    /// Return the path of the PackageManager.lock.pid file where the PID is located
    public var pidFilePath: AbsolutePath {
        return self.scratchDirectory.appending(component: "PackageManager.lock.pid")
    }

    /// Read the pid file
    public func readPID(from path: AbsolutePath) -> Int32? {
        // Check if the file exists
        let filePath = path.pathString
        if !FileManager.default.fileExists(atPath: filePath) {
            print("File does not exist at path: \(filePath)")
            return nil
        }

        do {
            // Read the contents of the file
            let pidString = try String(contentsOf: path.asURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)

            // Print the PID string to debug the content
            print("PID string: \(pidString)")

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
    public func writePID(pid: pid_t, to: URL, atomically: Bool, encoding: String.Encoding) throws {
        try "\(pid)".write(to: pidFilePath.asURL, atomically: true, encoding: .utf8)
    }
    
    /// Delete PID file at URL
    public func deletePIDFile(file: URL) throws {
        try FileManager.default.removeItem(at: file)
    }

}
