import PackagePlugin

@main
struct B: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        print("Hello B!")
    }
}
