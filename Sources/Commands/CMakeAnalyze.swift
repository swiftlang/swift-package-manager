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
import BuildSystemCMake
import Foundation

struct AnalyzeCMake: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analyze-cmake",
        abstract: "Analyze a CMake library and suggest module map configuration"
    )

    @Argument(help: "Path to the CMake library directory (containing CMakeLists.txt)")
    var libraryPath: String

    @Option(help: "Module name to use in suggestions")
    var moduleName: String = "YourModule"

    @Flag(help: "Write suggested configuration files")
    var write: Bool = false

    func run() throws {
        print("🔍 Analyzing CMake library at: \(libraryPath)")
        print()

        // Check for CMakeLists.txt
        let cmakeListsPath = (libraryPath as NSString).appendingPathComponent("CMakeLists.txt")
        guard FileManager.default.fileExists(atPath: cmakeListsPath) else {
            print("❌ No CMakeLists.txt found in \(libraryPath)")
            throw ExitCode.failure
        }
        print("✓ Found CMakeLists.txt")

        // Look for include directory
        let possibleIncludeDirs = ["include", "inc", "public", "src"]
        var includeDir: String?

        for dir in possibleIncludeDirs {
            let path = (libraryPath as NSString).appendingPathComponent(dir)
            if FileManager.default.fileExists(atPath: path) {
                includeDir = path
                print("✓ Found include directory: \(dir)/")
                break
            }
        }

        guard let incDir = includeDir else {
            print("⚠️  No standard include directory found")
            print("   Looked for: \(possibleIncludeDirs.joined(separator: ", "))")
            print()
            print("💡 You can still configure manually")
            return
        }

        // Analyze headers
        print()
        print("📋 Analyzing headers...")
        let analysis = HeaderAnalyzer.analyze(includeDir: incDir)

        if !analysis.textualHeaders.isEmpty {
            print()
            print("📄 Suggested textual headers:")
            for header in analysis.textualHeaders {
                print("  - \(header)")
            }
        }

        if !analysis.excludedHeaders.isEmpty {
            print()
            print("🚫 Suggested excluded headers (require external dependencies):")
            for header in analysis.excludedHeaders {
                print("  - \(header)")
            }
        }

        if !analysis.warnings.isEmpty {
            print()
            print("⚠️  Warnings:")
            for warning in analysis.warnings {
                print("  - \(warning)")
            }
        }

        print()
        print("📝 Suggested module map:")
        print("─" * 60)
        let moduleMap = analysis.suggestedModuleMap.replacingOccurrences(of: "YourModule", with: moduleName)
        print(moduleMap)
        print("─" * 60)

        print()
        print("📝 Suggested .spm-cmake.json:")
        print("─" * 60)
        let config = HeaderAnalyzer.suggestConfig(for: analysis, libraryName: moduleName)
        print(config)
        print("─" * 60)

        if write {
            print()
            print("💾 Writing configuration files...")

            let configDir = (libraryPath as NSString).appendingPathComponent("config")
            try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)

            let moduleMapPath = (configDir as NSString).appendingPathComponent("\(moduleName).modulemap")
            try moduleMap.write(toFile: moduleMapPath, atomically: true, encoding: .utf8)
            print("✓ Wrote \(moduleMapPath)")

            let jsonPath = (libraryPath as NSString).appendingPathComponent(".spm-cmake.json")
            try config.write(toFile: jsonPath, atomically: true, encoding: .utf8)
            print("✓ Wrote \(jsonPath)")

            print()
            print("✨ Done! Review and customize as needed.")
        } else {
            print()
            print("💡 To write these files, run with --write flag")
        }
    }
}

private func * (left: String, right: Int) -> String {
    String(repeating: left, count: right)
}
