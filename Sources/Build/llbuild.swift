/*
This source file is part of the Swift.org open source project

Copyright 2015 - 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

protocol ToolType {
    var name: String { get }
    var inputs: [String] { get }
    var outputs: [String] { get }
    ///YAML representation of the tool
    var llbuildYAML: String { get }
}

protocol ShellToolType: ToolType {
    var description: String { get }
    var args: [String] { get }
}

extension ShellToolType {
    
    var name: String {
        return "shell"
    }
    
    var llbuildYAML: String {
        var yaml = ""
        yaml += "    tool: " + name.YAML + "\n"
        yaml += "    description: " + description.YAML + "\n"
        yaml += "    inputs: " + inputs.YAML + "\n"
        yaml += "    outputs: " + outputs.YAML + "\n"
        yaml += "    args: " + args.YAML + "\n"
        return yaml
    }
}

struct ShellTool: ShellToolType {
    let description: String
    let inputs: [String]
    let outputs: [String]
    let args: [String]
}

protocol SwiftcToolType: ToolType {
    var executable: String { get }
    var moduleName: String { get }
    var moduleOutputPath: String { get }
    var importPaths: String { get }
    var tempsPath: String { get }
    var objects: [String] { get }
    var otherArgs: [String] { get }
    var sources: [String] { get }
    var isLibrary: Bool { get }
}

extension SwiftcToolType {
    
    var name: String {
        return "swift-compiler"
    }
    
    var llbuildYAML: String {
        var yaml = ""
        yaml += "    tool: " + name.YAML + "\n"
        yaml += "    executable: " + executable.YAML + "\n"
        yaml += "    module-name: " + moduleName.YAML + "\n"
        yaml += "    module-output-path: " + moduleOutputPath.YAML + "\n"
        yaml += "    inputs: " + inputs.YAML + "\n"
        yaml += "    outputs: " + outputs.YAML + "\n"
        yaml += "    import-paths: " + importPaths.YAML + "\n"
        yaml += "    temps-path: " + tempsPath.YAML + "\n"
        yaml += "    objects: " + objects.YAML + "\n"
        yaml += "    other-args: " + otherArgs.YAML + "\n"
        yaml += "    sources: " + sources.YAML + "\n"
        yaml += "    is-library: " + isLibrary.YAML + "\n"
        return yaml
    }
}

struct SwiftcTool: SwiftcToolType {
    let inputs: [String]
    let outputs: [String]
    let executable: String
    let moduleName: String
    let moduleOutputPath: String
    let importPaths: String
    let tempsPath: String
    let objects: [String]
    let otherArgs: [String]
    let sources: [String]
    let isLibrary: Bool
}

typealias Command = (name: String, tool: ToolType)

struct Target {
    let name: String
    let commands: [Command]
}

func llbuildYAML(targets targets: [Target]) -> String {
    
    var yaml = ""
    yaml += "client:" + "\n"
    yaml += "  name: swift-build" + "\n"
    yaml += "tools: {}" + "\n"
    
    yaml += "targets:" + "\n"
    for target in targets {
        yaml += "  \(target.name): " + target.commands.map{$0.name}.YAML + "\n"
    }
    
    yaml += "commands: " + "\n"
    
    let commands = targets.reduce([Command]()) { $0 + $1.commands }
    for command in commands {
        yaml += "  " + command.name + ":" + "\n"
        yaml += command.tool.llbuildYAML
    }
    
    return yaml
}
