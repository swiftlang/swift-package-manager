/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel
import var PackageLoading.moduleMapFilename

protocol Buildable {
    var targetName: String { get }
    var isTest: Bool { get }
}

extension Module: Buildable {
    func XccFlags(_ buildDir: AbsolutePath) -> [String] {
        return recursiveDependencies.flatMap { module -> [String] in
            if let module = module as? ClangModule {
                // For ClangModule we check if there is a user provided module
                // map; otherwise we return with path of generated one.  We will
                // have failed before we ever get here if there's no module map.
                // FIXME: The user-provided module map should be copied to build
                // dir but that would require copying the complete include dir
                // because it will mostly likely contain relative paths.
                // FIXME: This is already computed when trying to generate a
                // module map in ClangModule's `generateModuleMap()` function.
                // There shouldn't be need to redo this but it is difficult in
                // current architecture.

                let moduleMapFile: String
                // Locate the modulemap file for this clang module. Either user provided or we should have generated one.
                if isFile(module.moduleMapPath) {
                    moduleMapFile = module.moduleMapPath.asString
                } else {
                    let buildMeta = ClangModuleBuildMetadata(module: module, prefix: buildDir, otherArgs: [])
                    let genModuleMap = buildMeta.buildDirectory.appending(component: moduleMapFilename)
                    moduleMapFile = genModuleMap.asString
                }
                return ["-Xcc", "-fmodule-map-file=\(moduleMapFile)", "-I", module.includeDir.asString]
            } else if let module = module as? CModule {
                return ["-Xcc", "-fmodule-map-file=\(module.moduleMapPath.asString)"]
            } else {
                return []
            }
        }
    }

    var targetName: String {
        return "<\(name).module>"
    }
}

extension Product: Buildable {
    var isTest: Bool {
        if case .Test = type {
            return true
        }
        return false
    }

    var targetName: String {
        switch type {
        case .Library(.Dynamic):
            return "<\(name).dylib>"
        case .Test:
            return "<\(name).test>"
        case .Library(.Static):
            return "<\(name).a>"
        case .Executable:
            return "<\(name).exe>"
        }
    }
}
