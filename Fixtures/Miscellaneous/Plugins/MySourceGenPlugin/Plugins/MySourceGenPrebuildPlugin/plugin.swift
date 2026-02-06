import PackagePlugin
import Foundation

#if os(Android)
let touchExe = "/system/bin/touch"
let touchArgs: [String]  = []
#elseif os(Windows)
let touchExe = "C:/Windows/System32/cmd.exe"
let touchArgs = ["/c", "copy", "NUL"]
#else
let touchExe = "/usr/bin/touch"
let touchArgs: [String]  = []
#endif

@main
struct MyPlugin: BuildToolPlugin {

    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        print("Hello from the Prebuild Plugin!")
        guard let target = target as? SourceModuleTarget else { return [] }
        let outputPaths: [URL] = target.sourceFiles.filter{ $0.url.pathExtension == "dat" }.map { file in
            context.pluginWorkDirectoryURL.appendingPathComponent(file.url.deletingPathExtension().appendingPathExtension("swift").lastPathComponent)
        }
        var commands: [Command] = []
        let paths = outputPaths.map{ $0.path }
#if os(Windows)
        let args = ["/c", "FOR %F IN (" + paths.joined(separator: " ") + ") DO TYPE NUL > %F"]
#else
        let args = paths
#endif
        if !outputPaths.isEmpty {
            commands.append(.prebuildCommand(
                displayName:
                    "Running prebuild command for target \(target.name)",
                executable:
                    .init(fileURLWithPath: touchExe),
                arguments:
                    args,
                outputFilesDirectory:
                    context.pluginWorkDirectoryURL
            ))
        }
        return commands
    }
}
