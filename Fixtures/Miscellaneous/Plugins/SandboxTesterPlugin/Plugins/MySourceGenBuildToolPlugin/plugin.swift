import PackagePlugin
import Foundation

@main
struct MyPlugin: BuildToolPlugin {
    
    func createBuildCommands(context: TargetBuildContext) throws -> [Command] {
 
        // Check that we can write to the output directory.
        let allowedOutputPath = context.pluginWorkDirectory.appending("Foo")
        if mkdir(allowedOutputPath.string, 0o777) != 0 {
             throw StringError("unexpectedly could not write to '\(allowedOutputPath)': \(String(utf8String: strerror(errno)))")
        }

        // Check that we cannot write to the source directory.
        let disallowedOutputPath = context.targetDirectory.appending("Bar")
        if mkdir(disallowedOutputPath.string, 0o777) == 0 {
             throw StringError("unexpectedly could write to '\(disallowedOutputPath)'")
        }
        
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
