import PackagePlugin

@main
struct CrashingPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) throws -> [Command] {
        fatalError("intentional build-tool plugin crash")
    }
}
