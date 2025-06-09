//
//  plugin.swift
//  app
//
//  Created by John Bute on 2025-06-03.
//

import Foundation

import PackagePlugin

/// plugin that will kickstart the template executable=≠≠
@main

struct TemplatePlugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {
        let tool = try context.tool(named: "doo")
        let process = Process()

        process.executableURL = URL(filePath: tool.url.path())
        process.arguments = arguments.filter { $0 != "--" }

        try process.run()
        process.waitUntilExit()
    }
}
