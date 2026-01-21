
import Foundation

import PackagePlugin

@main
struct TemplateExamplePlugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {
        let tool = try context.tool(named: "TemplateExample")
        process.executableURL = URL(filePath: tool.url.path())
        process.arguments = arguments.filter { $0 != "--" }

        try process.run()
        process.waitUntilExit()
    }
}
