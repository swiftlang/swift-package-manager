/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel
import PackageLoading
import Utility

extension Command {
    static func compile(swiftModule module: SwiftModule, configuration conf: Configuration, prefix: AbsolutePath, otherArgs: [String], compilerExec: AbsolutePath) throws -> Command {
        let otherArgs = otherArgs + module.XccFlags(prefix) + (try module.pkgConfigSwiftcArgs()) + module.moduleCacheArgs(prefix: prefix)
        var args = ["-j\(SwiftcTool.numThreads)", "-D", "SWIFT_PACKAGE"]

        switch conf {
        case .debug:
            args += ["-Onone", "-g", "-enable-testing"]
        case .release:
            args += ["-O"]
        }

      #if os(macOS)
        args += ["-F", try platformFrameworksPath().asString]
      #endif

        let tool = SwiftcTool(module: module, prefix: prefix, otherArgs: args + otherArgs, executable: compilerExec.asString, conf: conf)
        return Command(name: module.targetName, tool: tool)
    }
}
