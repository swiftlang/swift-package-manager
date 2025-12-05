//
//  Template2Plugin.swift
//  TemplateWorkflow
//
//  Created by John Bute on 2025-04-23.
//

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
struct DeclarativeTemplatePlugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {
        let tool = try context.tool(named: "Template2")
        let process = Process()

        process.executableURL = URL(filePath: tool.url.path())
        process.arguments = arguments.filter { $0 != "--" }

        try process.run()
        process.waitUntilExit()
    }
}
