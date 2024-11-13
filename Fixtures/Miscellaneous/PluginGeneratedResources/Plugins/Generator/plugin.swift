import PackagePlugin

#if os(Android)
let touchExe = "/system/bin/touch"
#else
let touchExe = "/usr/bin/touch"
#endif

@main
struct GeneratorPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        return [
            .prebuildCommand(
                displayName: "Generating empty file",
                executable: .init(touchExe),
                arguments: [context.pluginWorkDirectory.appending("best.txt")],
                outputFilesDirectory: context.pluginWorkDirectory
            )
        ]
    }
}
