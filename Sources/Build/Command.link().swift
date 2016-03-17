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

extension Command {
    static func link(product: Product, configuration conf: Configuration, prefix: String, otherArgs: [String]) throws -> Command {

        let objects: [String]
        switch conf {
        case .Release:
            objects = product.buildables.map{ Path.join(prefix, "\($0.c99name).o") }
        case .Debug:
            objects = product.buildables.flatMap{ return SwiftcTool(module: $0, prefix: prefix, otherArgs: []).objects }
        }

        let outpath = Path.join(prefix, product.outname)

        var args = [Toolchain.swiftc] + otherArgs

        switch product.type {
        case .Library(.Static):
            fatalError("Unimplemented")
        case .Test:
          #if os(OSX)
            args += ["-Xlinker", "-bundle"]

            if let platformPath = Toolchain.platformPath {
                let path = Path.join(platformPath, "Developer/Library/Frameworks")
                args += ["-F", path]
            } else {
                throw Error.InvalidPlatformPath
            }

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
                args += module.Xcc
            }
            args.append("-emit-executable")
            args += ["-I", prefix]
          #endif
        case .Library(.Dynamic):
            args.append("-emit-library")
        case .Executable:
            args.append("-emit-executable")
            if conf == .Release {
                args += ["-Xlinker", "-dead_strip"]
            }
        }

        if conf == .Debug {
            args += ["-g"]
        }

        args += ["-L\(prefix)"]
        args += ["-o", outpath]
        args += objects

        let inputs = product.modules.flatMap{ [$0.targetName] + SwiftcTool(module: $0, prefix: prefix, otherArgs: []).inputs }

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
