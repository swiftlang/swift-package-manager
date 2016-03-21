/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType
import Utility


protocol ToolProtocol {
    var name: String { get }
    var inputs: [String] { get }
    var outputs: [String] { get }
    var YAMLDescription: String { get }
}

struct ShellTool: ToolProtocol {
    var name: String {
        return "shell"
    }

    var YAMLDescription: String {
        let args: String
        if self.args.count == 1 {
            // if one argument is specified we assume pre-escaped and have
            // llbuild execute it passed through to the shell
            args = self.args.first!
        } else {
            args = self.args.YAML
        }

        var yaml = ""
        yaml += "    tool: " + name.YAML + "\n"
        yaml += "    description: " + description.YAML + "\n"
        yaml += "    inputs: " + inputs.YAML + "\n"
        yaml += "    outputs: " + outputs.YAML + "\n"
        yaml += "    args: " + args + "\n"
        return yaml
    }

    let description: String
    let inputs: [String]
    let outputs: [String]
    let args: [String]
}


struct SwiftcTool: ToolProtocol {
    var name: String {
        return "swift-compiler"
    }

    let module: SwiftModule
    let prefix: String
    let otherArgs: [String]
    let executable: String

    var inputs: [String] {
        return module.recursiveDependencies.map{ $0.targetName }
    }

    var outputs: [String]        { return [module.targetName] + objects }
    var moduleName: String       { return module.c99name }
    var moduleOutputPath: String { return Path.join(prefix, "\(module.c99name).swiftmodule") }
    var importPaths: String      { return prefix }
    var tempsPath: String        { return Path.join(prefix, "\(module.c99name).build") }
    var objects: [String]        { return module.sources.relativePaths.map{ Path.join(tempsPath, "\($0).o") } }
    var sources: [String]        { return module.sources.paths }
    var isLibrary: Bool          { return module.type == .Library }

    var YAMLDescription: String {
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

struct Target {
    let node: String
    var cmds: [Command]
}

struct MkdirTool: ToolProtocol {
    let path: String

    var name: String { return "mkdir" }
    var inputs: [String] { return [] }
    var outputs: [String] { return [path] }

    var YAMLDescription: String {
        var yaml = ""
        yaml += "    tool: \(name.YAML)\n"
        yaml += "    outputs: \(outputs.YAML)\n"
        return yaml
    }
}

struct ClangTool: ToolProtocol {
    let desc: String
    let inputs: [String]
    let outputs: [String]
    let args: [String]
    let deps: String?

    var name: String { return "clang" }

    var YAMLDescription: String {
        var yaml = ""
        yaml += "    tool: " + name.YAML + "\n"
        yaml += "    description: " + desc.YAML + "\n"
        yaml += "    inputs: " + inputs.YAML + "\n"
        yaml += "    outputs: " + outputs.YAML + "\n"
        yaml += "    args: " + args.joined(separator: " ").YAML + "\n"
        if let deps = deps {
            yaml += "    deps: " + deps.YAML + "\n"
        }
        return yaml
    }
}

struct ArchiveTool: ToolProtocol {
    let inputs: [String]
    let outputs: [String]

    var name: String { return "archive" }

    var YAMLDescription: String {
        var yaml = [(String, String)]()
        yaml.append(("tool", name.YAML))
        yaml.append(("inputs", inputs.YAML))
        yaml.append(("outputs", outputs.YAML))
        return yaml.map{ return "    \($0): \($1)" }.joined(separator: "\n")
    }
}
