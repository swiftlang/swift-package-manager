/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public protocol TargetBuildContext {
    var targetName: String { get }
    var inputs: [String] { get }
    var targetBuildDirectory: String { get }
    var buildDirectory: String { get }
}

public protocol TaskGenerationDelegate {
    func createCommand(inputs: [String], outputs: [String], commandLine: [String], description: String)

    func declareSwiftSource(_ path: String)
}

public protocol BuildRule {
    init()
    func constructTasks(target: TargetBuildContext, delegate: TaskGenerationDelegate) throws
}

public protocol PackageManager {
    func registerBuildRule(name: String, implementation: BuildRule.Type)
}

public protocol PackageExtension {
    static func initialize(packageManager: PackageManager)
}
