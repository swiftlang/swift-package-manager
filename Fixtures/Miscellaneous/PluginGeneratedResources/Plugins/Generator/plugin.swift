import PackagePlugin
import Foundation

#if os(Android)
let touchExe = "/system/bin/touch"
let touchArgs: [String] = []
#elseif os(Windows)
let touchExe = "C:/Windows/System32/cmd.exe"
let touchArgs = ["/c", "copy", "NUL"]
#else
let touchExe = "/usr/bin/touch"
let touchArgs: [String] = []
#endif

@main
struct GeneratorPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        return [
            .prebuildCommand(
                displayName: "Generating empty file",
                executable: .init(fileURLWithPath: touchExe),
                arguments: touchArgs + [context.pluginWorkDirectoryURL.appendingPathComponent("best.txt").path],
                outputFilesDirectory: context.pluginWorkDirectoryURL
            )
        ]
    }
}
