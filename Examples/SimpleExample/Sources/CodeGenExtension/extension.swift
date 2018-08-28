import PackageExtension
import Foundation

public struct MyCodeGenRule: BuildRule {
    public init() {}

    public func constructTasks(target: TargetBuildContext, delegate: TaskGenerationDelegate) throws {
        let codegen = target.buildDirectory + "/codegen-tool"
        let output = target.targetBuildDirectory + "/generated.swift"

        delegate.createCommand(
            inputs: target.inputs,
            outputs: [output],
            commandLine: [codegen] + target.inputs + [output],
            description: "codegen-tool: Generate Swift code"
        )
        delegate.declareSwiftSource(output)
    }
}

public class CodeGenExtension: PackageExtension {
    public static func initialize(packageManager: PackageManager) {
        packageManager.registerBuildRule(
            name: "MyCodeGenRule", implementation: MyCodeGenRule.self)
    }
}
