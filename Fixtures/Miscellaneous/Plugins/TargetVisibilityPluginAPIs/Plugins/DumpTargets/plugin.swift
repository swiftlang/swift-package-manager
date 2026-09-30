import Foundation
import PackagePlugin

@main
struct DumpTargets: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) throws {
        for target in context.package.targets.sorted(by: { $0.name < $1.name }) {
            let name = target.name
            print("\(name).visibility = \(target.visibility)")
            if let module = target.sourceModule {
                print("\(name).kind = \(module.kind)")
            } else {
                print("\(name).kind = none")
            }
        }
    }
}
