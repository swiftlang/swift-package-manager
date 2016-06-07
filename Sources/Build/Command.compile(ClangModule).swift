/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageModel
import Utility
import POSIX

private extension ClangModule {
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

    func optimizationFlags(_ conf: Configuration) -> [String] {
        switch conf {
        case .debug:
            return ["-g", "-O0"]
        case .release:
            return ["-O2"]
        }
    }

    var productName: String {
        switch type {
        case .library:
            return c99name.soname
        case .executable:
            return c99name
        }
    }
}

/// A helper struct for ClangModule to compute basic
/// flags needed to compile and link C language targets.
struct ClangModuleBuildMetadata {

    /// The ClangModule to compute flags for.
    let module: ClangModule

    /// Path to working directiory.
    let prefix: String

    /// Extra arguments to append to basic compile and link args.
    let otherArgs: [String]

    /// Path to build directory for this module.
    var buildDirectory: String { return Path.join(prefix, "\(module.c99name).build") }

    /// Targets this module depends on.
    var inputs: [String] { return module.recursiveDependencies.map { $0.targetName } }

    /// An array of tuple containing filename, source path, object path and dependency path
    /// for each of the source in this module.
    func compilePaths() -> [(filename: String, source: String, object: String, deps: String)] {
        return module.sources.relativePaths.map { source in
            let path = Path.join(module.sources.root, source)
            let object = Path.join(buildDirectory, "\(source).o")
            let deps = Path.join(buildDirectory, "\(source).d")
            return (source, path, object, deps)
        }
    }

    /// Basic flags needed to compile this module.
    func basicCompileArgs() throws -> [String] {
        return try basicArgs() + ["-fobjc-arc", "-fmodules", "-fmodule-name=\(module.c99name)"] + otherArgs + module.moduleCacheArgs(prefix: prefix)
    }

    /// Basic flags needed to link this module.
    func basicLinkArgs() throws -> [String] {
        return try basicArgs() + linkDependenciesFlags + otherArgs + module.languageLinkArgs
    }

    /// Flags to link the C language dependencies of this module.
    private var linkDependenciesFlags: [String] {
        var args: [String] = []
        for case let dep as ClangModule in module.dependencies {
            args += ["-l\(dep.c99name)"]
        }
        return args
    }

    /// Basic arguments needed for both compiling and linking.
    private func basicArgs() throws -> [String] {
        var args: [String] = []
      #if os(OSX)
        args += ["-F", try platformFrameworksPath()]
      #else
        args += ["-fPIC"]
      #endif
        return args
    }
}

extension Command {
    static func compile(clangModule module: ClangModule, externalModules: Set<Module>, configuration conf: Configuration, prefix: String, CC: String, Xcc: [String], Xld: [String]) throws -> [Command] {

        var buildMeta = ClangModuleBuildMetadata(module: module, prefix: prefix, otherArgs: Xcc)
        
        if module.type == .library {
            try module.generateModuleMap(inDir: buildMeta.buildDirectory)
        }
        
        ///------------------------------ Compile -----------------------------------------
        var compileCommands = [Command]()
        var basicArgs = try buildMeta.basicCompileArgs() + module.includeFlagsWithExternalModules(externalModules)
        basicArgs += module.optimizationFlags(conf)

        for path in buildMeta.compilePaths() {
            var args = basicArgs
            args += ["-MD", "-MT", "dependencies", "-MF", path.deps]
            args += ["-c", path.source, "-o", path.object]
            // Add include directory in include search paths.
            args += ["-I", module.path]

            let clang = ClangTool(desc: "Compile \(module.name) \(path.filename)",
                                  inputs: buildMeta.inputs + [path.source],
                                  outputs: [path.object],
                                  args: [CC] + args,
                                  deps: path.deps)

            let command = Command(node: path.object, tool: clang)

            compileCommands.append(command)
        }


        ///FIXME: This probably doesn't belong here
        ///------------------------------ Product -----------------------------------------

        buildMeta = ClangModuleBuildMetadata(module: module, prefix: prefix, otherArgs: Xld)

        var args = try buildMeta.basicLinkArgs()
        args += ["-L\(prefix)"]
        args += buildMeta.compilePaths().map{$0.object}

        if module.type == .library {
            args += ["-shared"]
        }

        let productPath = Path.join(prefix, module.productName)
        args += ["-o", productPath]
        
        let shell = ShellTool(description: "Linking \(module.name)",
                              inputs: buildMeta.inputs + compileCommands.map{$0.node},
                              outputs: [productPath, module.targetName],
                              args: [CC] + args)
        
        let command = Command(node: module.targetName, tool: shell)

        return compileCommands + [command]
    }
}
