import Foundation
import PackagePlugin

@main
struct CheckTestability: CommandPlugin {
    // This is a helper for testing target builds to ensure that they are testable.
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        // Parse the arguments: <targetName> <config> <shouldTestable>
        guard arguments.count == 3 else {
            fatalError("Usage: <targetName> <config> <shouldTestable>")
        }
        let rawSubsetName = arguments[0]
        var subset: PackageManager.BuildSubset
        switch rawSubsetName {
        // Special subset names
        case "all-with-tests":
            subset = .all(includingTests: true)
        // By default, treat the subset as a target name
        default:
            subset = .target(rawSubsetName)
        }
        guard let config = PackageManager.BuildConfiguration(rawValue: arguments[1]) else {
            fatalError("Invalid configuration: \(arguments[1])")
        }
        let shouldTestable = arguments[2] == "true"

        var parameters = PackageManager.BuildParameters()
        parameters.configuration = config
        parameters.logging = .verbose

        // Perform the build
        let result = try packageManager.build(subset, parameters: parameters)

        // Check if the build was successful
        guard result.succeeded else {
            fatalError("Build failed: \(result.logText)")
        }

        // Check if the build log contains "-enable-testing" flag
        let isTestable = result.logText.contains("-enable-testing")
        if isTestable != shouldTestable {
            fatalError("Testability mismatch: expected \(shouldTestable), but got \(isTestable):\n\(result.logText)")
        }
    }
}
