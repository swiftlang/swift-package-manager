import PackagePlugin

@main
struct PackageCmd: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) throws {
        print("This is PackageCmd.")
    }
}
