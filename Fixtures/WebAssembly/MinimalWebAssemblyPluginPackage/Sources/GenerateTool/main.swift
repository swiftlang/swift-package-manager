import Foundation
import PluginToolHelpers
import PluginToolSupport

#if os(WASI)
#error("GenerateTool must not be compiled for WebAssembly.")
#endif

let outputFile = ProcessInfo.processInfo.arguments[1]
try generatedSource(returning: pluginToolHelper())
    .write(toFile: outputFile, atomically: true, encoding: .utf8)
