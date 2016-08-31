/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageGraph
import PackageModel
import Utility

import func POSIX.getenv

/**
  - Returns: path to generated YAML for consumption by the llbuild based swift-build-tool
*/
public func describe(_ prefix: AbsolutePath, _ conf: Configuration, _ graph: PackageGraph, flags: BuildFlags, toolchain: Toolchain) throws -> AbsolutePath {
    guard graph.modules.count > 0 else {
        throw Error.noModules
    }

    if graph.modules.count == 1, let module = graph.modules.first as? CModule {
        throw Error.onlyCModule(name: module.name)
    }

    let Xld = flags.linkerFlags.flatMap{ ["-Xlinker", $0] }
    let prefix = prefix.appending(component: conf.dirname)
    try makeDirectories(prefix)
    let swiftcArgs = flags.cCompilerFlags.flatMap{ ["-Xcc", $0] } + flags.swiftCompilerFlags + verbosity.ccArgs

    var commands = [Command]()
    var targets = Targets()

    for module in graph.modules {
        switch module {
        case let module as SwiftModule:
            let compile = try Command.compile(swiftModule: module, configuration: conf, prefix: prefix, otherArgs: swiftcArgs + toolchain.swiftPlatformArgs, compilerExec: toolchain.swiftCompiler)
            commands.append(compile)
            targets.append([compile], for: module)

        case let module as ClangModule:
            // FIXME: Ignore C language test modules on linux for now.
          #if os(Linux)
            if module.isTest { continue }
          #endif
            // FIXME: Find a way to eliminate `externalModules` from here.
            let compile = try Command.compile(clangModule: module, externalModules: graph.externalModules, configuration: conf, prefix: prefix, otherArgs: flags.cCompilerFlags + toolchain.clangPlatformArgs, compilerExec: toolchain.clangCompiler)
            commands += compile
            targets.append(compile, for: module)

        case is CModule:
            continue

        default:
            fatalError("unhandled module type: \(module)")
        }
    }

    for product in graph.products {
        var rpathArgs = [String]()
        
        // On Linux, always embed an RPATH adjacent to the linked binary. Note
        // that the '$ORIGIN' here is literal, it is a reference which is
        // understood by the dynamic linker.
#if os(Linux)
        rpathArgs += ["-Xlinker", "-rpath=$ORIGIN"]
#endif
        let command: Command
        if product.containsOnlyClangModules {
            command = try Command.linkClangModule(product, configuration: conf, prefix: prefix, otherArgs: Xld, linkerExec: toolchain.clangCompiler)
        } else {
            command = try Command.linkSwiftModule(product, configuration: conf, prefix: prefix, otherArgs: Xld + swiftcArgs + toolchain.swiftPlatformArgs + rpathArgs, linkerExec: toolchain.swiftCompiler)
        }

        commands.append(command)
        targets.append([command], for: product)
    }

    return try! write(path: AbsolutePath("\(prefix.asString).yaml")) { stream in
        stream <<< "client:\n"
        stream <<< "  name: swift-build\n"
        stream <<< "tools: {}\n"
        stream <<< "targets:\n"
        for target in [targets.test, targets.main] {
            stream <<< "  " <<< Format.asJSON(target.node) <<< ": " <<< Format.asJSON(target.cmds.map{$0.node}) <<< "\n"
        }
        stream <<< "default: " <<< Format.asJSON(targets.main.node) <<< "\n"
        stream <<< "commands: \n"
        for command in commands {
            stream <<< "  " <<< Format.asJSON(command.node) <<< ":\n"
            command.tool.append(to: stream)
            stream <<< "\n"
        }
    }
}

private func write(path: AbsolutePath, write: (OutputByteStream) -> Void) throws -> AbsolutePath {
    let stream = BufferedOutputByteStream()
    write(stream)
    try localFileSystem.writeFileContents(path, bytes: stream.bytes)
    return path
}

private struct Targets {
    var test = Target(node: "test", cmds: [])
    var main = Target(node: "main", cmds: [])

    mutating func append(_ commands: [Command], for buildable: Buildable) {
        if !buildable.isTest {
            main.cmds += commands
        }

        // Always build everything for the test target.
        test.cmds += commands
    }
}
