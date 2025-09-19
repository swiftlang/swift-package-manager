import PackagePlugin

@main
struct DumpArtifactsPlugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) throws {
        do {
            var parameters = PackageManager.BuildParameters()
            parameters.configuration = .debug
            parameters.logging = .concise
            let result = try packageManager.build(.all(includingTests: false), parameters: parameters)
            print("succeeded: \(result.succeeded)")
            for artifact in result.builtArtifacts {
                print("artifact-path: \(artifact.path.string)")
                print("artifact-kind: \(artifact.kind)")
            }
        }
        catch {
            print("error from the plugin host: \\(error)")
        }
    }
}
