import PackagePlugin
import Foundation

@main
struct MyPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        for name in ["RemoteTool", "LocalTool", "ImpliedLocalTool"] {
            let tool = try context.tool(named: name)
            print("tool path is \(tool.path)")
            
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: tool.path.string)
                try process.run()
            }
            catch {
                print("error: \(error)")
            }
        }
    }
}
