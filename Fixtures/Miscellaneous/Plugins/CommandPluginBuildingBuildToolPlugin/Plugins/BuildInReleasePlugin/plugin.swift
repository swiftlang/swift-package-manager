import PackagePlugin

@main
struct BuildInReleasePlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var parameters = PackageManager.BuildParameters()
        parameters.configuration = .release
        let result = try packageManager.build(.product("MyLibrary"), parameters: parameters)
        guard result.succeeded else {
            print("Build failed: \(result.logText)")
            return
        }
        print("Built successfully")
    }
}
