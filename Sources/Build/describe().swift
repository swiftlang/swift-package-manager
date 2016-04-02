/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func POSIX.getenv
import func POSIX.mkdir
import func POSIX.fopen
import func libc.fclose
import PackageType
import Utility

/**
  - Returns: path to generated YAML for consumption by the llbuild based swift-build-tool
*/
public func describe(prefix: String, _ conf: Configuration, _ modules: [Module], _ externalModules: Set<Module> , _ products: [Product], Xcc: [String], Xld: [String], Xswiftc: [String]) throws -> String {

    guard modules.count > 0 else {
        throw Error.NoModules
    }

    let Xcc = Xcc.flatMap{ ["-Xcc", $0] }
    let Xld = Xld.flatMap{ ["-Xlinker", $0] }
    let prefix = try mkdir(prefix, conf.dirname)  //TODO llbuild this
    let swiftcArgs = Xcc + Xswiftc + verbosity.ccArgs

    var commands = [Command]()
    var targets = Targets()

    for module in modules {
        switch module {
        case let module as SwiftModule:
            let (compile, mkdirs) = try Command.compile(swiftModule: module, configuration: conf, prefix: prefix, otherArgs: swiftcArgs + platformArgs())
            commands.append(contentsOf: mkdirs + [compile])
            targets.append(compile, for: module)

        case let module as ClangModule:
            //FIXME: Generate modulemaps if possible
            //Since we're not generating modulemaps currently we'll just emit empty module map file
            //if it not present
            if module.type == .Library && !module.moduleMapPath.isFile {
                try POSIX.mkdir(module.moduleMapPath.parentDirectory)
                try fopen(module.moduleMapPath, mode: .Write) { fp in
                    try fputs("\n", fp)
                }
            }

            let (compile, mkdir) = Command.compile(clangModule: module, externalModules: externalModules, configuration: conf, prefix: prefix)
            commands.append(compile)
            commands.append(mkdir)
            targets.main.cmds.append(compile)

        case is CModule:
            continue

        default:
            fatalError("unhandled module type: \(module)")
        }
    }

    for product in products {
        let command = try Command.link(product, configuration: conf, prefix: prefix, otherArgs: Xld + swiftcArgs + platformArgs())
        commands.append(command)
        targets.append(command, for: product)
    }

    return try write(path: "\(prefix).yaml") { writeln in
        writeln("client:")
        writeln("  name: swift-build")
        writeln("tools: {}")
        writeln("targets:")
        for target in [targets.test, targets.main] {
            writeln("  \(target.node): " + target.cmds.map{$0.node}.YAML)
        }
        writeln("commands: ")
        for command in commands {
            writeln("  \(command.node):")
            writeln(command.tool.YAMLDescription)
        }
    }
}

private func write(path path: String, write: ((String) -> Void) -> Void) throws -> String {
    var storedError: ErrorProtocol?

    try fopen(path, mode: .Write) { fp in
        write { line in
            do {
                if storedError == nil {
                    try fputs(line, fp)
                    try fputs("\n", fp)
                }
            } catch {
                storedError = error
            }
        }
    }

    guard storedError == nil else {
        throw storedError!
    }

    return path
}

private struct Targets {
    var test = Target(node: "test", cmds: [])
    var main = Target(node: "default", cmds: [])

    mutating func append(command: Command, for buildable: Buildable) {
        if buildable.isTest {
            test.cmds.append(command)
        } else {
            main.cmds.append(command)
        }
    }
}
