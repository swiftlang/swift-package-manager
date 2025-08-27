import Foundation

import PackagePlugin

/// plugin that will kickstart the template executable
@main
struct FooPlugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {}
}

