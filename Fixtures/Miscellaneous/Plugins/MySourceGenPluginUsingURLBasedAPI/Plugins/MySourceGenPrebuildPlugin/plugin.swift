import Foundation
import PackagePlugin

#if os(Android)
let touchExe = "/system/bin/touch"
#elseif os(Windows)
let touchExe = "C:/Windows/System32/cmd.exe"
#else
let touchExe = "/usr/bin/touch"
#endif

@main
struct MyPlugin: BuildToolPlugin {

    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        print("Hello from the Prebuild Plugin!")
        guard let target = target as? SourceModuleTarget else { return [] }
        let outputPaths: [URL] = target.sourceFiles.filter{ $0.url.pathExtension == "dat" }.map { file in
            context.pluginWorkDirectoryURL.appendingPathComponent(file.url.lastPathComponent + ".swift")
        }
        let paths = outputPaths.map{ $0.path }
#if os(Windows)
        let args = ["/c", "FOR %F IN (" + paths.joined(separator: " ") + ") DO TYPE NUL > %F"]
#else
        let args = paths
#endif
        var commands: [Command] = []
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
