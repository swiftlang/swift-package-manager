import PackagePlugin
import Foundation

@main
struct MyPlugin: BuildToolPlugin {
    
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
 
        // Check that we can write to the output directory.
        let allowedOutputPath = context.pluginWorkDirectory.string + "/" + UUID().uuidString
        if mkdir(allowedOutputPath, 0o777) != 0 {
             throw StringError("unexpectedly could not write to '\(allowedOutputPath)': \(String(utf8String: strerror(errno)))")
        }
        rmdir(allowedOutputPath)

        // Check that we cannot write to the user's home directory.
        let disallowedOutputPath = NSHomeDirectory() + "/" + UUID().uuidString
        if mkdir(disallowedOutputPath, 0o777) == 0 {
             throw StringError("unexpectedly could write to '\(disallowedOutputPath)'")
        }
        
        // Check that we can write to the temporary directory.
        let allowedTemporaryPath = NSTemporaryDirectory() + "/" + UUID().uuidString
        if mkdir(allowedTemporaryPath, 0o777) != 0 {
             throw StringError("unexpectedly could not write to '\(allowedTemporaryPath)': \(String(utf8String: strerror(errno)))")
        }
        rmdir(allowedTemporaryPath)

        return []
    }

    struct StringError: Error, CustomStringConvertible {
        var error: String
        init(_ error: String) {
            self.error = error
        }
        var description: String { error }
    }
}
