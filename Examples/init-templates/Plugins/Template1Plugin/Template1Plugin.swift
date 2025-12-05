//
//  plugin.swift
//  TemplateWorkflow
//
//  Created by John Bute on 2025-04-14.
//
import Foundation

import PackagePlugin

/// plugin that will kickstart the template executable
@main
struct TemplatePlugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {
        let tool = try context.tool(named: "Template1")
        let packageDirectory = context.package.directoryURL.path
        let process = Process()
        let stderrPipe = Pipe()

        process.executableURL = URL(filePath: tool.url.path())
        process.arguments = ["--pkg-dir", packageDirectory] + arguments.filter { $0 != "--" }
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrOutput = String(data: stderrData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw PluginError.executionFailed(code: process.terminationStatus, stderrOutput: stderrOutput)
        }
    }

    enum PluginError: Error, CustomStringConvertible {
        case executionFailed(code: Int32, stderrOutput: String)

        var description: String {
            switch self {
            case .executionFailed(let code, let stderrOutput):
                """

                Plugin subprocess failed with exit code \(code).

                Output:
                \(stderrOutput)

                """
            }
        }
    }
}
