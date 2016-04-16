/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType
import struct Utility.Path

protocol Buildable {
    var targetName: String { get }
    var isTest: Bool { get }
}

extension CModule {
    ///Returns the build directory path of a CModule
    func buildDirectory(_ prefix: String) -> String {
        return Path.join(prefix, "\(c99name).build")
    }
}

extension Module: Buildable {
    var isTest: Bool {
        return self is TestModule
    }

    func XccFlags(_ prefix: String) -> [String] {
        return recursiveDependencies.flatMap { module -> [String] in
            if let module = module as? ClangModule {
                ///For ClangModule we check if there is a user provided module map
                ///otherwise we return with path of generated one.
                ///We will fail before this is ever called if there is no module map.
                ///FIXME: The user provided modulemap should be copied to build dir
                ///but that requires copying the complete include dir because it'll
                ///mostly likely contain relative paths.
                ///FIXME: This is already computed when trying to generate modulemap
                ///in ClangModule's `generateModuleMap(inDir wd: String)`
                ///there shouldn't be need to redo this but is difficult in 
                ///current architecture
                if module.moduleMapPath.isFile {
                    return ["-Xcc", "-fmodule-map-file=\(module.moduleMapPath)"]
                }
                let genModuleMap = Path.join(module.buildDirectory(prefix), module.moduleMap)
                return ["-Xcc", "-fmodule-map-file=\(genModuleMap)"]
            } else if let module = module as? CModule {
                return ["-Xcc", "-fmodule-map-file=\(module.moduleMapPath)"]
            } else {
                return []
            }
        }
    }

    var targetName: String {
        return "<\(name).module>"
    }
}

extension SwiftModule {
    var pkgConfigArgs: [String] {
        return recursiveDependencies.flatMap { module -> [String] in
            guard case let module as CModule = module, let pkgConfigName = module.pkgConfig else {
                return []
            }
            guard var pkgConfig = try? PkgConfig(name: pkgConfigName) else {
                // .pc not found
                return []
            }
            do {
                try pkgConfig.load()
            }
            catch {
                
            }
            return pkgConfig.cFlags.map{["-Xcc", $0]}.flatten() + pkgConfig.libs
        }
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
