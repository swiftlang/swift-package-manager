/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel
import Utility

import func POSIX.getenv

/**
  - Returns: path to generated YAML for consumption by the llbuild based swift-build-tool
*/
public func describe(_ prefix: String, _ conf: Configuration, _ modules: [Module], _ externalModules: Set<Module>, _ products: [Product], Xcc: [String], Xld: [String], Xswiftc: [String], toolchain: Toolchain) throws -> String {
    precondition(prefix.isAbsolute)

    guard modules.count > 0 else {
        throw Error.noModules
    }

    if modules.count == 1, let module = modules.first as? CModule, !(module is ClangModule) {
        throw Error.onlyCModule(name: module.name)
    }

    let Xcc = Xcc.flatMap{ ["-Xcc", $0] }
    let Xld = Xld.flatMap{ ["-Xlinker", $0] }
    let prefix = Path.join(prefix, conf.dirname)
    try Utility.makeDirectories(prefix)
    let swiftcArgs = Xcc + Xswiftc + verbosity.ccArgs

    let SWIFT_EXEC = toolchain.SWIFT_EXEC
    let CC = getenv("CC") ?? "clang"

    var commands = [Command]()
    var targets = Targets()

    for module in modules {
        switch module {
        case let module as SwiftModule:
            let compile = try Command.compile(swiftModule: module, configuration: conf, prefix: prefix, otherArgs: swiftcArgs + toolchain.platformArgsSwiftc, SWIFT_EXEC: SWIFT_EXEC)
            commands.append(compile)
            targets.append([compile], for: module)

        case let module as ClangModule:
            // FIXME: Ignore C language test modules on linux for now.
          #if os(Linux)
            if module.isTest { continue }
          #endif
            let compile = try Command.compile(clangModule: module, externalModules: externalModules, configuration: conf, prefix: prefix, CC: CC, otherArgs: Xcc + toolchain.platformArgsClang)
            commands += compile
            targets.append(compile, for: module)

        case is CModule:
            continue

        default:
            fatalError("unhandled module type: \(module)")
        }
    }

    for product in products {
        var rpathArgs = [String]()
        
        // On Linux, always embed an RPATH adjacent to the linked binary. Note
        // that the '$ORIGIN' here is literal, it is a reference which is
        // understood by the dynamic linker.
#if os(Linux)
        rpathArgs += ["-Xlinker", "-rpath=$ORIGIN"]
#endif
        let command: Command
        if product.containsOnlyClangModules {
            command = try Command.linkClangModule(product, configuration: conf, prefix: prefix, otherArgs: Xld, CC: CC)
        } else {
            command = try Command.linkSwiftModule(product, configuration: conf, prefix: prefix, otherArgs: Xld + swiftcArgs + toolchain.platformArgsSwiftc + rpathArgs, SWIFT_EXEC: SWIFT_EXEC)
        }

        commands.append(command)
        targets.append([command], for: product)
    }

    return try! write(path: "\(prefix).yaml") { stream in
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

private func write(path: String, write: (OutputByteStream) -> Void) throws -> String {
    let stream = OutputByteStream()
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
