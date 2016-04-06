/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func POSIX.mkdir
import PackageType
import Utility


//FIXME messy :/


extension Command {
    static func link(product: Product, configuration conf: Configuration, prefix: String, otherArgs: [String], SWIFT_EXEC: String) throws -> Command {

        let objects: [String]
        switch conf {
        case .Release:
            objects = product.buildables.map{ Path.join(prefix, "\($0.c99name).o") }
        case .Debug:
            objects = product.buildables.flatMap{ return SwiftcTool(module: $0, prefix: prefix, otherArgs: [], executable: SWIFT_EXEC).objects }
        }

        let outpath = Path.join(prefix, product.outname)

        var args: [String]
        switch product.type {
        case .Library(.Dynamic), .Executable, .Test:
            args = [SWIFT_EXEC] + otherArgs

            if conf == .Debug {
                args += ["-g"]
            }
            args += ["-L\(prefix)"]
            args += ["-o", outpath]

        case .Library(.Static):
            //FIXME proper static archive llbuild tool
            //NOTE HACK this works because llbuild runs it with via a shell
            //FIXME this is coincidental, do properly
            args = ["rm", "-f", outpath, "&&", "ar", "cr"]
        }

        let inputs = product.modules.flatMap { module -> [String] in
            switch conf {
            case .Debug:
                let tool = SwiftcTool(module: module, prefix: prefix, otherArgs: [], executable: SWIFT_EXEC)
                // must return tool’s outputs and inputs as shell nodes don't calculate more than that
                return tool.inputs + tool.outputs
            case .Release:
                return objects
            }
        }

        switch product.type {
        case .Library(.Static):
            args.append(outpath)
        case .Test:
          #if os(OSX)
            args += ["-Xlinker", "-bundle"]
            args += ["-F", try platformFrameworksPath()]

            // TODO should be llbuild rules∫
            if conf == .Debug {
                try mkdir(outpath.parentDirectory)
                try fopen(outpath.parentDirectory.parentDirectory, "Info.plist", mode: .Write) { fp in
                    try fputs(product.Info.plist, fp)
                }
            }
          #else
            // HACK: To get a path to LinuxMain.swift, we just grab the
            //       parent directory of the first test module we can find.
            let firstTestModule = product.modules.flatMap{ $0 as? TestModule }.first!
            let testDirectory = firstTestModule.sources.root.parentDirectory
            let main = Path.join(testDirectory, "LinuxMain.swift")
            args.append(main)
            for module in product.modules {
                args += module.XccFlags(prefix)
            }
            args.append("-emit-executable")
            args += ["-I", prefix]
          #endif
        case .Library(.Dynamic):
            args.append("-emit-library")
        case .Executable:
            args.append("-emit-executable")
        }

        args += objects

        if case .Library(.Static) = product.type {
            //HACK we need to be executed passed-through to the shell
            // otherwise we cannot do the rm -f first
            //FIXME make a proper static archive tool for llbuild
            args = [args.joined(separator: " ")] //TODO escape!
        }

        let shell = ShellTool(
            description: "Linking \(outpath.prettyPath)",
            inputs: inputs,
            outputs: [product.targetName, outpath],
            args: args)

        return Command(node: product.targetName, tool: shell)
    }
}

extension Product {
    private var buildables: [SwiftModule] {
        return recursiveDependencies(modules.map{$0}).flatMap{ $0 as? SwiftModule }
    }
}
