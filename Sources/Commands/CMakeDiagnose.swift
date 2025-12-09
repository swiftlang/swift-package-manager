//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import Foundation

struct DiagnoseCMake: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diagnose-cmake",
        abstract: "Diagnose CMake availability and configuration"
    )

    func run() throws {
        print("CMake Diagnostics")
        print("=================")
        print()

        // Check for cmake
        if let cmakePath = which("cmake") {
            print("cmake: \(cmakePath)")
            if let version = getCMakeVersion(at: cmakePath) {
                print("  version: \(version)")
            }
        } else {
            print("cmake: NOT FOUND")
            print("  Install CMake from https://cmake.org/download/")
        }

        print()

        // Check for ninja
        if let ninjaPath = which("ninja") {
            print("ninja: \(ninjaPath)")
            if let version = getNinjaVersion(at: ninjaPath) {
                print("  version: \(version)")
            }
        } else {
            print("ninja: NOT FOUND (optional, but recommended for faster builds)")
            print("  Install Ninja from https://ninja-build.org/")
        }

        print()

        // Check PATH
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            print("PATH directories:")
            for dir in path.split(separator: ":") {
                print("  - \(dir)")
            }
        }
    }

    private func which(_ program: String) -> String? {
        guard let path = ProcessInfo.processInfo.environment["PATH"] else {
            return nil
        }

        let fm = FileManager.default
        for dir in path.split(separator: ":") {
            let candidate = dir + "/" + program
            if fm.isExecutableFile(atPath: String(candidate)) {
                return String(candidate)
            }
        }
        return nil
    }

    private func getCMakeVersion(at path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return nil
            }

            // Parse first line: "cmake version X.Y.Z"
            if let firstLine = output.split(separator: "\n").first {
                let parts = firstLine.split(separator: " ")
                if parts.count >= 3 && parts[0] == "cmake" && parts[1] == "version" {
                    return String(parts[2])
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    private func getNinjaVersion(at path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return nil
            }

            // Ninja version output is just the version number
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
