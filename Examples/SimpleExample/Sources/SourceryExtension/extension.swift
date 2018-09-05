import PackageExtension
import Foundation

public struct SourceryRule: BuildRule {
    public init() {}

    public func constructTasks(target: TargetBuildContext, delegate: TaskGenerationDelegate) throws {
        let codegen = target.buildDirectory + "/sourcery"

        for input in target.inputs {
            let basename = URL(string: input)!.lastPathComponent
            let output = target.targetBuildDirectory + "/" + basename + ".generated.swift"
            delegate.declareSwiftSource(output)

            delegate.createCommand(
                inputs: [input],
                outputs: [output],
                commandLine: ["sourcery", "--quiet", "--sources", input, "--templates", "/Users/ankit/dotfiles/scripts/Sourcery/playground/Templates", "--output", output],
                description: "Generating \(URL(string: output)!.lastPathComponent)"
            )
        }
    }
}

public class SourceryExtension: PackageExtension {
    public static func initialize(packageManager: PackageManager) {
        packageManager.registerBuildRule(
            name: "SourceryRule", implementation: SourceryRule.self)
    }
}
