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

    let Xcc = Xcc.flatMap{ ["-Xcc", $0] }
    let Xld = Xld.flatMap{ ["-Xlinker", $0] }
    let prefix = Path.join(prefix, conf.dirname)
    try Utility.makeDirectories(prefix)
    let swiftcArgs = Xcc + Xswiftc + verbosity.ccArgs

    let SWIFT_EXEC = toolchain.SWIFT_EXEC
    let CC = getenv("CC") ?? "clang"

    var commands = [Command]()

    var mainTarget = Target(node: "main", cmds: [])
    var testTarget = Target(node: "test", cmds: [])
    var replTarget = Target(node: "repl", cmds: [])

    let mainProducts = Set(products)

    for module in modules {
        switch module {
        case let module as SwiftModule:
            let compile = try Command.compile(swiftModule: module, configuration: conf, prefix: prefix, otherArgs: swiftcArgs + toolchain.platformArgsSwiftc, SWIFT_EXEC: SWIFT_EXEC)
            commands.append(compile)

            mainTarget.cmds += [compile]
            testTarget.cmds += [compile]
            replTarget.cmds += [compile]

        case let module as ClangModule:
            // FIXME: Ignore C language test modules on linux for now.
          #if os(Linux)
            if module.isTest { continue }
          #endif
            let compile = try Command.compile(clangModule: module, externalModules: externalModules, configuration: conf, prefix: prefix, CC: CC, otherArgs: Xcc + toolchain.platformArgsClang)
            commands += compile

            mainTarget.cmds += compile
            testTarget.cmds += compile
            replTarget.cmds += compile

        case is CModule:
            continue

        default:
            fatalError("unhandled module type: \(module)")
        }
    }

    /// TODO: handle system modules here.
    let productsForREPL = modules.filter{ !($0 is CModule) }.map{ Product(name: $0.c99name, type: .Library(.Dynamic), modules: [$0]) }

    let allProducts = Set<Product>(products).union(productsForREPL)

    for product in allProducts {
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

        testTarget.cmds.append(command)
        replTarget.cmds.append(command)

        if mainProducts.contains(product) {
            mainTarget.cmds.append(command)
        }
    }

    return try! write(path: yamlPath(forPrefix: AbsolutePath(prefix))) { stream in
        stream <<< "client:\n"
        stream <<< "  name: swift-build\n"
        stream <<< "tools: {}\n"
        stream <<< "targets:\n"
        for target in [replTarget, mainTarget, testTarget] {
            stream <<< "  " <<< Format.asJSON(target.node) <<< ": " <<< Format.asJSON(target.cmds.map{$0.node}) <<< "\n"
        }
        stream <<< "default: " <<< Format.asJSON(mainTarget.node) <<< "\n"
        stream <<< "commands: \n"
        for command in commands {
            stream <<< "  " <<< Format.asJSON(command.node) <<< ":\n"
            command.tool.append(to: stream)
            stream <<< "\n"
        }
    }
}

private func write(path: AbsolutePath, write: (OutputByteStream) -> Void) throws -> String {
    let stream = OutputByteStream()
    write(stream)
    try localFS.writeFileContents(path, bytes: stream.bytes)
    return path.asString
}

public func yamlPath(forPrefix prefix: AbsolutePath) -> AbsolutePath {
    return prefix.parentDirectory.appending("debug.yaml")
}
