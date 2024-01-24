import PackagePlugin

@main
struct test: CommandPlugin {
    // This plugin exists to test that the executable it requires is built correctly when cross-compiling
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        print("Hello from dependencies-stub")
        let _ = try packageManager.build(
            .product("placeholder"),
            parameters: .init(configuration: .debug, logging: .concise)
        )
    }
}