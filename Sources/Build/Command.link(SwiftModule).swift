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

//FIXME messy :/

extension Command {
    static func linkSwiftModule(_ product: Product, configuration conf: Configuration, prefix: String, otherArgs: [String], SWIFT_EXEC: String) throws -> Command {
        precondition(prefix.isAbsolute)

        // Get the set of all input modules.
        //
        // FIXME: This needs to handle C language targets.
        let buildables = product.modules.flatMap{ [$0] + $0.recursiveDependencies }.flatMap{ $0 as? SwiftModule }.unique()
        
        var objects = buildables.flatMap { SwiftcTool(module: $0, prefix: prefix, otherArgs: [], executable: SWIFT_EXEC, conf: conf).objects }

        let outpath = product.outpath(prefix)

        var args: [String]
        switch product.type {
        case .Library(.Dynamic), .Executable, .Test:
            args = [SWIFT_EXEC] + otherArgs

            if conf == .debug {
                args += ["-g"]
            }
            args += ["-L\(prefix)"]
            args += ["-o", outpath]

          #if os(OSX)
            args += ["-F", try platformFrameworksPath()]
          #endif

        case .Library(.Static):
            return Command(node: outpath, tool: ArchiveTool(inputs: objects, outputs: [outpath]))
        }

        switch product.type {
        case .Library(.Static):
            args.append(outpath)
        case .Test:
            args += ["-module-name", product.name]
            // Link all the Clang Module's objects into XCTest executable.
            objects += product.modules.flatMap{ $0 as? ClangModule }.flatMap{ ClangModuleBuildMetadata(module: $0, prefix: prefix, otherArgs: []).objects }
          #if os(OSX)
            args += ["-Xlinker", "-bundle"]
            args += ["-F", try platformFrameworksPath()]

            // TODO should be llbuild rules∫
            if conf == .debug {
                let infoPlistPath = Path.join(outpath.parentDirectory.parentDirectory, "Info.plist")
                try localFS.createDirectory(outpath.parentDirectory, recursive: true)
                try localFS.writeFileContents(infoPlistPath, bytes: ByteString(encodingAsUTF8: product.Info.plist))
            }
          #else
            // HACK: To get a path to LinuxMain.swift, we just grab the
            //       parent directory of the first test module we can find.
            let firstTestModule = product.modules.flatMap{$0 as? SwiftModule}.filter{ $0.isTest }.first!
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
        
        for module in product.modules {
            args += try module.pkgConfigSwiftcArgs()
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
            inputs: objects,
            outputs: [outpath],
            args: args)

        return Command(node: outpath, tool: shell)
    }
}
