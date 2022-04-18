import PackagePlugin

@main
struct PluginScript: CommandPlugin {
    
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        dump(context)
        if let target = try context.package.targets(named: ["MySnippet"]).first as? SourceModuleTarget {
            print("type of snippet target: \(target.kind)")
        }
    }
}
