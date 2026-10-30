import PackagePlugin

@main
struct PublicCmd: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) throws {
        print("This is PublicCmd.")
    }
}
