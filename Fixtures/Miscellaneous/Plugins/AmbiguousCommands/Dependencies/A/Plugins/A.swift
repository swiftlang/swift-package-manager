import PackagePlugin

@main
struct A: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        print("Hello A!")
    }
}

