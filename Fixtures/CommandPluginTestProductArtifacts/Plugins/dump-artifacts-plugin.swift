import PackagePlugin

// Builds a subset of the package selected by the command-line arguments and prints the resulting
// built artifacts so tests can verify how the synthetic umbrella test product and individual test
// products are reported.
//
// Usage:
//   dump-artifacts-plugin all
//   dump-artifacts-plugin product <product-name>
//   dump-artifacts-plugin target <target-name>
@main
struct DumpArtifactsPlugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) throws {
        do {
            let subset: PackageManager.BuildSubset
            switch arguments.first {
            case "product":
                subset = .product(arguments[1])
            case "target":
                subset = .target(arguments[1])
            default:
                subset = .all(includingTests: true)
            }

            var parameters = PackageManager.BuildParameters()
            parameters.configuration = .debug
            parameters.logging = .concise
            let result = try packageManager.build(subset, parameters: parameters)
            print("succeeded: \(result.succeeded)")
            for artifact in result.builtArtifacts {
                print("artifact-path: \(artifact.path.string)")
                print("artifact-kind: \(artifact.kind)")
            }
        }
        catch {
            print("error from the plugin host: \(error)")
        }
    }
}
