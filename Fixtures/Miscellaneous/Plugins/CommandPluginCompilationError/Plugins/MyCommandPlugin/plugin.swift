import PackagePlugin
@main struct MyCommandPlugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) throws {
        this is an error
    }
}
