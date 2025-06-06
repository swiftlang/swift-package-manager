import Foundation
import PackagePlugin

@main
final class BuildToolPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        _ = try context.tool(named: "BuildTool")
    }
}
