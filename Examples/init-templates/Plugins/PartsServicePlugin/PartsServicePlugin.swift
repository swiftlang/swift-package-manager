import Foundation

import PackagePlugin

/// plugin that will kickstart the template executable
@main
struct PartsServiceTemplatePlugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {
        let tool = try context.tool(named: "PartsService")
        let packageDirectory = context.package.directoryURL.path
        let packageName = context.package.displayName

        let process = Process()

        process.executableURL = URL(filePath: tool.url.path())
        process.arguments = ["--pkg-dir", packageDirectory, "--name", packageName] + arguments.filter { $0 != "--" }

        try process.run()
        process.waitUntilExit()
    }
}
