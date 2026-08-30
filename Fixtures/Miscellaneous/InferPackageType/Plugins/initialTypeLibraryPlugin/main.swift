import Foundation

import PackagePlugin

/// The plugin that kickstarts the template executable.
@main
struct FooPlugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {}
}
