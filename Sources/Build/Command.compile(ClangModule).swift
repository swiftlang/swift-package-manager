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

//FIXME: Incremental builds

extension Command {
    static func compile(clangModule module: ClangModule, externalModules: Set<Module>, configuration conf: Configuration, prefix: String) -> (Command, Command) {

        let wd = Path.join(prefix, "\(module.c99name).build")
        let mkdir = Command.createDirectory(wd)

        let inputs = module.dependencies.map{ $0.targetName } + module.sources.paths + [mkdir.node]
        let productPath = Path.join(prefix, module.type == .Library ? "lib\(module.c99name).so" : module.c99name)

        var args: [String] = []
    #if os(Linux)
        args += ["-fPIC"]
    #endif
        args += ["-fmodules", "-fmodule-name=\(module.name)"]
        args += ["-L\(prefix)"]

        for case let dep as ClangModule in module.dependencies {
            let includeFlag: String
            //add `-iquote` argument to the include directory of every target in the package in the
            //transitive closure of the target being built allowing the use of `#include "..."`
            //add `-I` argument to the include directory of every target outside the package in the
            //transitive closure of the target being built allowing the use of `#include <...>`

            includeFlag = externalModules.contains(dep) ? "-I" : "-iquote"
            args += [includeFlag, dep.path]
            args += ["-l\(dep.c99name)"] //FIXME: giving path to other module's -fmodule-map-file is not linking that module
        }

        switch conf {
        case .Debug:
            args += ["-g", "-O0"]
        case .Release:
            args += ["-O2"]
        }

        args += module.sources.paths
        
        if module.type == .Library {
            args += ["-shared"]
        }
        
        args += ["-o", productPath]

        let clang = ShellTool(
            description: "Compiling \(module.name)",
            inputs: inputs,
            outputs: [productPath, module.targetName],
            args: [Toolchain.clang] + args)

        let command = Command(node: module.targetName, tool: clang)

        return (command, mkdir)
    }
}
