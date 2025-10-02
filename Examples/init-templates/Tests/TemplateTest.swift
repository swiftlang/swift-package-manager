import Foundation
import Testing

// a possible look into how to test templates
@Suite
final class TemplateCLITests {
    // Struct to collect output from a process
    struct processOutput {
        let terminationStatus: Int32
        let output: String

        init(terminationStatus: Int32, output: String) {
            self.terminationStatus = terminationStatus
            self.output = output
        }
    }

    // function for running a process given arguments, executable, and a directory
    func run(executableURL: URL, args: [String], directory: URL? = nil) throws -> processOutput {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = args

        process.currentDirectoryURL = directory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(decoding: outputData, as: UTF8.self)

        return processOutput(terminationStatus: process.terminationStatus, output: output)
    }

    // test case for your template
    @Test
    func template1_generatesExpectedFilesAndCompiles() throws {
        // Setup temp directory for generating template
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("Template1Test-\(UUID())")
        let appName = "TestApp"

        if fileManager.fileExists(atPath: tempDir.path) {
            try fileManager.removeItem(at: tempDir)
        }
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Path to built TemplateCLI executable
        let binary = self.productsDirectory.appendingPathComponent("simple-template1-tool")

        let output = try run(executableURL: binary, args: ["--name", appName, "--include-readme"], directory: tempDir)
        #expect(output.terminationStatus == 0, "TemplateCLI should exit cleanly")

        // Check files
        let mainSwift = tempDir.appendingPathComponent("Sources/\(appName)/main.swift")
        let readme = tempDir.appendingPathComponent("README.md")

        #expect(fileManager.fileExists(atPath: mainSwift.path), "main.swift is generated")
        #expect(fileManager.fileExists(atPath: readme.path), "README.md is generated")

        let outputBinary = tempDir.appendingPathComponent("main_executable")

        let compileOutput = try run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            args: ["swiftc", mainSwift.path, "-o", outputBinary.path]
        )

        #expect(compileOutput.terminationStatus == 0, "swift file compiles")
    }

    // Find the built products directory when using SwiftPM test
    var productsDirectory: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/debug")
    }
}
