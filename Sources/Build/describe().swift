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
public func describe(_ prefix: String, _ conf: Configuration, _ modules: [Module], _ externalModules: Set<Module>, _ products: [Product], Xcc: [String], Xld: [String], Xswiftc: [String], toolchain: Toolchain) throws -> String {

    guard modules.count > 0 else {
        throw Error.NoModules
    }

    let Xcc = Xcc.flatMap{ ["-Xcc", $0] }
    let Xld = Xld.flatMap{ ["-Xlinker", $0] }
    let prefix = try mkdir(prefix, conf.dirname)  //TODO llbuild this
    let swiftcArgs = Xcc + Xswiftc + verbosity.ccArgs

    let SWIFT_EXEC = toolchain.SWIFT_EXEC
    let CC = getenv("CC") ?? "clang"

    var commands = [Command]()
    var targets = Targets()

    for module in modules {
        switch module {
        case let module as SwiftModule:
            let (compile, mkdirs) = try Command.compile(swiftModule: module, configuration: conf, prefix: prefix, otherArgs: swiftcArgs + toolchain.platformArgs, SWIFT_EXEC: SWIFT_EXEC)
            commands.append(contentsOf: mkdirs + [compile])
            targets.append(compile, for: module)

        case let module as ClangModule:
            let (compile, mkdir) = try Command.compile(clangModule: module, externalModules: externalModules, configuration: conf, prefix: prefix, CC: CC)
            commands += compile
            commands.append(mkdir)
            targets.main.cmds += compile

        case is CModule:
            continue

        default:
            fatalError("unhandled module type: \(module)")
        }
    }

    for product in products {
        let command = try Command.link(product, configuration: conf, prefix: prefix, otherArgs: Xld + swiftcArgs + toolchain.platformArgs, SWIFT_EXEC: SWIFT_EXEC)
        commands.append(command)
        targets.append(command, for: product)
    }

    return try write("\(prefix).yaml") { writeln in
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

private func write(path: String, write: ((String) -> Void) -> Void) throws -> String {
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

    mutating func append(_ command: Command, for buildable: Buildable) {
        if buildable.isTest {
            test.cmds.append(command)
        } else {
            main.cmds.append(command)
        }
    }
}
