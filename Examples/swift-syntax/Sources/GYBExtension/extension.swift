import PackageExtension
import Foundation

public struct GYBRule: BuildRule {
    public init() {}

    public func constructTasks(target: TargetBuildContext, delegate: TaskGenerationDelegate) throws {
        let gyb = URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("gyb").path
        for input in target.inputs {
            let basename = URL(string: input)!.lastPathComponent
            let output = target.targetBuildDirectory + "/" + String(basename.dropLast(4))
            delegate.declareSwiftSource(output)

            delegate.createCommand(
                inputs: [input],
                outputs: [output],
                commandLine: [
                    gyb,
                    input, "-o", output,
                ],
                description: "Generating \(URL(string: output)!.lastPathComponent)"
            )
        }
    }
}

public class GYBExtension: PackageExtension {
    public static func initialize(packageManager: PackageManager) {
        packageManager.registerBuildRule(
            name: "GYBRule", implementation: GYBRule.self)
    }
}
