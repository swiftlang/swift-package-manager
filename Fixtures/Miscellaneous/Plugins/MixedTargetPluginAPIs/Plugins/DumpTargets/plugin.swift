import Foundation
import PackagePlugin

@main
struct DumpTargets: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) throws {
        for module in context.package.sourceModules.sorted(by: { $0.name < $1.name }) {
            let type: String
            if module is SwiftSourceModuleTarget {
                type = "swift"
            } else if module is ClangSourceModuleTarget {
                type = "clang"
            } else {
                type = "mixed"
            }
            let name = module.name
            print("\(name).type = \(type)")
            print("\(name).moduleName = \(module.moduleName)")
            print("\(name).kind = \(module.kind)")
            print("\(name).publicHeaders = \(module.publicHeadersDirectoryURL?.lastPathComponent ?? "none")")
            print("\(name).swiftDefinitions = \(module.swiftCompilationConditions)")
            print("\(name).clangDefinitions = \(module.clangPreprocessorDefinitions)")
            print("\(name).headerSearchPaths = \(module.headerSearchPaths)")
            print("\(name).sourceFiles = \(module.sourceFiles.map(\.url.lastPathComponent))")
        }
    }
}
