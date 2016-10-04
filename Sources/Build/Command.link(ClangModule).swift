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
    static func linkClangModule(_ product: Product, configuration conf: Configuration, prefix: AbsolutePath, otherArgs: [String], linkerExec: AbsolutePath) throws -> Command {
        precondition(product.containsOnlyClangModules)

        let clangModules = product.modules.flatMap { $0 as? ClangModule }
        var args = [String]()

        // Collect all the objects.
        var objects = [AbsolutePath]()
        var inputs = [String]()
        var linkFlags = [String]()
        for module in clangModules {
            let buildMeta = ClangModuleBuildMetadata(module: module, prefix: prefix, otherArgs: [])
            objects += buildMeta.objects
            inputs += buildMeta.inputs
            linkFlags += buildMeta.linkDependenciesFlags
        }

        args += try ClangModuleBuildMetadata.basicArgs() + otherArgs
        args += ["-L\(prefix.asString)"]
        // Linux doesn't search executable directory for shared libs so embed runtime search path.
      #if os(Linux)
        args += ["-Xlinker", "-rpath=$ORIGIN"]
      #endif
        args += linkFlags
        args += objects.map{ $0.asString }

        switch product.type {
        case .Executable: break
        case .Library(.Dynamic):
            args += ["-shared"]
        case .Test, .Library(.Static):
            fatalError("Can't build \(product.name), \(product.type) is not yet supported.")
        }

        let productPath = prefix.appending(product.outname)
        args += ["-o", productPath.asString]
        
        let shell = ShellTool(description: "Linking \(product.name)",
                              inputs: objects.map{ $0.asString } + inputs,
                              outputs: [productPath.asString, product.targetName],
                              args: [linkerExec.asString] + args)
        
        return Command(name: product.targetName, tool: shell)
    }
}
