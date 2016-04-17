/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType
import Utility
import POSIX

private extension ClangModule {
    var basicArgs: [String] {
        var args: [String] = []
        #if os(Linux)
            args += ["-fPIC"]
        #endif
        args += ["-fmodules", "-fmodule-name=\(name)"]
        return args
    }

    func includeFlagsWithExternalModules(_ externalModules: Set<Module>) -> [String] {
        var args: [String] = []
        for case let dep as ClangModule in dependencies {
            let includeFlag: String
            //add `-iquote` argument to the include directory of every target in the package in the
            //transitive closure of the target being built allowing the use of `#include "..."`
            //add `-I` argument to the include directory of every target outside the package in the
            //transitive closure of the target being built allowing the use of `#include <...>`

            includeFlag = externalModules.contains(dep) ? "-I" : "-iquote"
            args += [includeFlag, dep.path]
        }
        return args
    }

    var linkFlags: [String] {
        var args: [String] = []
        for case let dep as ClangModule in dependencies {
            args += ["-l\(dep.c99name)"]
        }
        return args
    }

    func optimizationFlags(_ conf: Configuration) -> [String] {
        switch conf {
        case .Debug:
            return ["-g", "-O0"]
        case .Release:
            return ["-O2"]
        }
    }
}

private extension Sources {
    func compilePathsForBuildDir(_ wd: String) -> [(filename: String, source: String, object: String, deps: String)] {
        return relativePaths.map { source in
            let path = Path.join(root, source)
            let object = Path.join(wd, "\(source).o")
            let deps = Path.join(wd, "\(source).d")
            return (source, path, object, deps)
        }
    }
}

extension Command {
    static func compile(clangModule module: ClangModule, externalModules: Set<Module>, configuration conf: Configuration, prefix: String, CC: String) throws -> ([Command], Command) {

        let wd = module.buildDirectory(prefix)
        
        if module.type == .Library {
            try module.generateModuleMap(inDir: wd)
        }
        
        let mkdir = Command.createDirectory(wd)

        ///------------------------------ Compile -----------------------------------------
        var compileCommands = [Command]()
        let dependencies = module.dependencies.map{ $0.targetName }
        let basicArgs = module.basicArgs + module.includeFlagsWithExternalModules(externalModules) + module.optimizationFlags(conf)
        for path in module.sources.compilePathsForBuildDir(wd) {
            var args = basicArgs
            args += ["-MD", "-MT", "dependencies", "-MF", path.deps]
            args += ["-c", path.source, "-o", path.object]

            let clang = ClangTool(desc: "Compile \(module.name) \(path.filename)",
                                  inputs: dependencies + [path.source, mkdir.node],
                                  outputs: [path.object],
                                  args: [CC] + args,
                                  deps: path.deps)

            let command = Command(node: path.object, tool: clang)

            compileCommands.append(command)
        }


        ///FIXME: This probably doesn't belong here
        ///------------------------------ Product -----------------------------------------

        var args = module.basicArgs
        args += module.optimizationFlags(conf)
        args += ["-L\(prefix)"]
        args += module.linkFlags
        args += module.sources.compilePathsForBuildDir(wd).map{$0.object}

        if module.type == .Library {
            args += ["-shared"]
        }

        let productPath = Path.join(prefix, module.type == .Library ? "lib\(module.c99name).so" : module.c99name)
        args += ["-o", productPath]
        
        let shell = ShellTool(description: "Linking \(module.name)",
                              inputs: dependencies + compileCommands.map{$0.node} + [mkdir.node],
                              outputs: [productPath, module.targetName],
                              args: [CC] + args)
        
        let command = Command(node: module.targetName, tool: shell)

        return (compileCommands + [command], mkdir)
    }
}
