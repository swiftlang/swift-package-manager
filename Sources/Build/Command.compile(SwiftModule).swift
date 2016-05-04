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

        let otherArgs = otherArgs + module.XccFlags(prefix) + (try module.pkgConfigArgs())
        
        func cmd(_ tool: ToolProtocol) -> Command {
            return Command(node: module.targetName, tool: tool)
        }

        var args = ["-j8", "-D", "SWIFT_PACKAGE"]

        switch conf {
        case .Debug:
            args += ["-Onone", "-g", "-enable-testing"]
        case .Release:
            args += ["-O"]
        }

        #if os(OSX)
        args += ["-F", try platformFrameworksPath()]
        #endif

        let tool = SwiftcTool(module: module, prefix: prefix, otherArgs: args + otherArgs, executable: SWIFT_EXEC, conf: conf)

        //FIXME these should be inferred as implicit inputs by llbuild
        let mkdirs = Set(tool.objects.map{ $0.parentDirectory }).map(Command.createDirectory)
        return (cmd(tool), mkdirs)
    }
}
