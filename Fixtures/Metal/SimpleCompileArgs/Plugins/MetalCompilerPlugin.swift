import PackagePlugin
import struct Foundation.URL

@main
struct MetalCompilerPlugin: BuildToolPlugin {

    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        Diagnostics.remark("MetalCompilerPlugin: Starting plugin execution")

        guard let sourceFiles = target.sourceModule?.sourceFiles else {
            Diagnostics.remark("MetalCompilerPlugin: No source files found")
            return [] 
        }

        Diagnostics.remark("MetalCompilerPlugin: Found \(sourceFiles.count) source files")
        for file in sourceFiles {
            Diagnostics.remark("  - \(file.path.lastComponent)")
        }

        let metalFiles = sourceFiles.filter { $0.path.extension == "metal" }
        
        Diagnostics.remark("MetalCompilerPlugin: Found \(metalFiles.count) .metal files")
        
        guard !metalFiles.isEmpty else {
            Diagnostics.remark("MetalCompilerPlugin: No .metal files to compile")
            return []
        }

        var commands: [Command] = []
        var airFiles: [URL] = []
        
        // Compile each .metal file to .air
        for metalFile in metalFiles {
            let airFile = context.pluginWorkDirectoryURL.appendingPathComponent(
                metalFile.path.stem + ".air"
            )
            airFiles.append(airFile)
            
            commands.append(.buildCommand(
                displayName: "Compiling Metal shader \(metalFile.path.lastComponent)",
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: [
                    "metal",
                    "-c",
                    "-g",  // Include debug symbols
                    metalFile.url.path,
                    "-o",
                    airFile.path
                ],
                inputFiles: [metalFile.url],
                outputFiles: [airFile]
            ))
        }
        
        // Link all .air files into default.metallib
        let metallibPath = context.pluginWorkDirectoryURL.appendingPathComponent("default.metallib")
        
        var metallibArgs = ["metallib", "-o", metallibPath.path]
        metallibArgs.append(contentsOf: airFiles.map { $0.path })
        
        commands.append(.buildCommand(
            displayName: "Linking Metal library",
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: metallibArgs,
            inputFiles: airFiles,
            outputFiles: [metallibPath]
        ))
        
        Diagnostics.remark("MetalCompilerPlugin: Will generate metallib at \(metallibPath.path)")
        
        return commands
    }
}

