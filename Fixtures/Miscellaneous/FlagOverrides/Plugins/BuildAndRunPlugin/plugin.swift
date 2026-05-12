import PackagePlugin

@main
struct BuildAndRunPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var parameters = PackageManager.BuildParameters()
        parameters.otherSwiftcFlags = arguments
        let result = try packageManager.build(.product("FlagOverrides"), parameters: parameters)
        guard result.succeeded else {
            throw "Build failed: \(result.logText)"
        }
        guard let executable = result.builtArtifacts.first(where: { $0.kind == .executable }) else {
            throw "No executable artifact found"
        }
        print(executable.url.path)
    }
}

extension String: @retroactive Error {}
