import PackagePlugin

@main struct SymbolGraphExtractPlugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) throws {
        let result = try self.packageManager.getSymbolGraph(for: context.package.targets.first!, options: .init())
        print(result.directoryPath)
    }
}