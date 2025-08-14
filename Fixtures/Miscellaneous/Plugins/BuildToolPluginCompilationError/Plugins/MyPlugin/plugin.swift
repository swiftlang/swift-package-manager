import PackagePlugin
import Foundation
@main
struct MyBuildToolPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) throws -> [Command] {
        print("This is text from the plugin")
        throw "This is an error from the plugin"
        return []
    }

}
extension String : Error {}
