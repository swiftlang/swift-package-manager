/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType
import Utility

extension Command {
    static func compile(swiftModule module: SwiftModule, configuration conf: Configuration, prefix: String, otherArgs: [String], SWIFT_EXEC: String) throws -> (Command, [Command]) {

        let otherArgs = otherArgs + module.XccFlags(prefix)

        func cmd(_ tool: ToolProtocol) -> Command {
            return Command(node: module.targetName, tool: tool)
        }

        switch conf {
        case .Debug:
            var args = ["-j8","-Onone","-g","-D","SWIFT_PACKAGE", "-enable-testing"]

          #if os(OSX)
            args += ["-F", try platformFrameworksPath()]
          #endif

            let tool = SwiftcTool(module: module, prefix: prefix, otherArgs: args + otherArgs, executable: SWIFT_EXEC)

            //FIXME these should be inferred as implicit inputs by llbuild
            let mkdirs = Set(tool.objects.map{ $0.parentDirectory }).map(Command.createDirectory)
            return (cmd(tool), mkdirs)

        case .Release:
            let inputs = module.dependencies.map{ $0.targetName } + module.sources.paths
            var args = ["-c", "-emit-module", "-D", "SWIFT_PACKAGE", "-O", "-whole-module-optimization", "-I", prefix] + otherArgs
            let productPath = Path.join(prefix, "\(module.c99name).o")

            if module.type == .Library {
                args += ["-parse-as-library"]
            }

            let tool = ShellTool(
                description: "Compile \(module.name)",
                inputs: inputs,
                outputs: [productPath, module.targetName],
                args: [SWIFT_EXEC, "-o", productPath] + args + module.sources.paths + otherArgs)

            return (cmd(tool), [])
        }
    }
}
