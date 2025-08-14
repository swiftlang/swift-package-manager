import PackagePlugin
@main struct MyBuildToolPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) throws -> [Command] {
        return []
    }
}
