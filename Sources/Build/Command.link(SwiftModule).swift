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
    static func linkSwiftModule(_ product: Product, configuration conf: Configuration, prefix: AbsolutePath, otherArgs: [String], SWIFT_EXEC: String) throws -> Command {

        // Get the unique set of all input modules.
        //
        // FIXME: This needs to handle C language targets.
        let buildables = OrderedSet(product.modules.flatMap{ [$0] + $0.recursiveDependencies }.flatMap{ $0 as? SwiftModule }).contents
        
        var objects = buildables.flatMap { SwiftcTool(module: $0, prefix: prefix, otherArgs: [], executable: SWIFT_EXEC, conf: conf).objects }

        let outpath = prefix.appending(product.outname)

        var args: [String]
        switch product.type {
        case .Library(.Dynamic), .Executable, .Test:
            args = [SWIFT_EXEC] + otherArgs

            if conf == .debug {
                args += ["-g"]
            }
            args += ["-L\(prefix.asString)"]
            args += ["-o", outpath.asString]

          #if os(macOS)
            args += ["-F", try platformFrameworksPath().asString]
          #endif

        case .Library(.Static):
            let inputs = buildables.map{ $0.targetName } + objects.map{ $0.asString }
            let outputs = [product.targetName, outpath.asString]
            return Command(node: product.targetName, tool: ArchiveTool(inputs: inputs, outputs: outputs))
        }

        switch product.type {
        case .Library(.Static):
            args.append(outpath.asString)
        case .Test:
            args += ["-module-name", product.name]
            // Link all the Clang Module's objects into XCTest executable.
            objects += product.modules.flatMap{ $0 as? ClangModule }.flatMap{ ClangModuleBuildMetadata(module: $0, prefix: prefix, otherArgs: []).objects }
          #if os(macOS)
            args += ["-Xlinker", "-bundle"]
            args += ["-F", try platformFrameworksPath().asString]

            // TODO should be llbuild rules∫
            if conf == .debug {
                let infoPlistPath = outpath.parentDirectory.parentDirectory.appending(component: "Info.plist")
                try localFileSystem.createDirectory(outpath.parentDirectory, recursive: true)
                try localFileSystem.writeFileContents(infoPlistPath, bytes: ByteString(encodingAsUTF8: product.Info.plist))
            }
          #else
            // HACK: To get a path to LinuxMain.swift, we just grab the
            //       parent directory of the first test module we can find.
            let firstTestModule = product.modules.flatMap{$0 as? SwiftModule}.filter{ $0.isTest }.first!
            let testDirectory = firstTestModule.sources.root.parentDirectory
            let main = testDirectory.appending(component: "LinuxMain.swift")
            args.append(main.asString)
            for module in product.modules {
                args += module.XccFlags(prefix)
            }
            args.append("-emit-executable")
            args += ["-I", prefix.asString]
          #endif
        case .Library(.Dynamic):
            args.append("-emit-library")
        case .Executable:
            args.append("-emit-executable")
        }
        
        for module in product.modules {
            args += try module.pkgConfigSwiftcArgs()
        }
        
        args += objects.map{ $0.asString }

        if case .Library(.Static) = product.type {
            //HACK we need to be executed passed-through to the shell
            // otherwise we cannot do the rm -f first
            //FIXME make a proper static archive tool for llbuild
            args = [args.joined(separator: " ")] //TODO escape!
        }

        let shell = ShellTool(
            description: "Linking \(outpath.prettyPath)",
            inputs: objects.map{ $0.asString },
            outputs: [product.targetName, outpath.asString],
            args: args)

        return Command(node: product.targetName, tool: shell)
    }
}
