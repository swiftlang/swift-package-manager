import Foundation
import PackagePlugin

@main
struct targetbuild_stub: CommandPlugin {
    // This is a helper for testing target builds performed on behalf of plugins.
    // It sends asks SwiftPM to build a target with different options depending on its arguments.
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        // Build a target
        var parameters = PackageManager.BuildParameters()
        if arguments.contains("build-debug") {
            parameters.configuration = .debug
        } else if arguments.contains("build-release") {
            parameters.configuration = .release
        } else if arguments.contains("build-inherit") {
            parameters.configuration = .inherit
        }
        // If no 'build-*' argument is present, the default (.debug) will be used.

        let _ = try packageManager.build(
            .product("placeholder"),
            parameters: parameters
        )
    }
}