import Foundation
import PackagePlugin

#if os(Android)
let touchExe = "/system/bin/touch"
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
        var commands: [Command] = []
        if !outputPaths.isEmpty {
            commands.append(.prebuildCommand(
                displayName:
                    "Running prebuild command for target \(target.name)",
                executable:
                    URL(fileURLWithPath: touchExe),
                arguments: 
                    outputPaths.map{ $0.path },
                outputFilesDirectory:
                    context.pluginWorkDirectoryURL
            ))
        }
        return commands
    }
}
