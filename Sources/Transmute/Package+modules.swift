/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import class PackageDescription.Target
import PackageType
import Utility

extension Package {
    func modules() throws -> [Module] {

        guard !Path.join(path, "module.modulemap").isFile else {
            return [try CModule(name: name, path: path, pkgConfig: manifest.package.pkgConfig, providers: manifest.package.providers)]
        }

        if manifest.package.exclude.contains(".") {
            return []
        }

        let srcroot = try sourceRoot()

        if srcroot != path {
            let invalidRootFiles = walk(path, recursively: false).filter(isValidSource)
            guard invalidRootFiles.isEmpty else {
                throw ModuleError.InvalidLayout(.InvalidLayout(invalidRootFiles))
            }
        }

        let maybeModules = walk(srcroot, recursively: false).filter(shouldConsiderDirectory)

        if maybeModules.count == 1 && maybeModules[0] != srcroot {
            let invalidModuleFiles = walk(srcroot, recursively: false).filter(isValidSource)
            guard invalidModuleFiles.isEmpty else {
                throw ModuleError.InvalidLayout(.InvalidLayout(invalidModuleFiles))
            }
        }

        let modules: [Module]
        if maybeModules.isEmpty {
            do {
                modules = [try modulify(srcroot, name: self.name)]
            } catch Module.Error.NoSources {
                throw ModuleError.NoModules(self)
            }
        } else {
            modules = try maybeModules.map { path in
                let name: String
                if path == srcroot {
                    name = self.name
                } else {
                    name = path.basename
                }
                return try modulify(path, name: name)
            }
        }

        func moduleForName(_ name: String) -> Module? {
            return modules.pick{ $0.name == name }
        }

        for module in modules {
            guard let target = targetForName(module.name) else { continue }

            module.dependencies = try target.dependencies.map { $0
                switch $0 {
                case .Target(let name):
                    guard let module = moduleForName(name) else {
                        throw ModuleError.ModuleNotFound(name)
                    }
                    return module
                }
            }
        }

        return modules
    }
    
    func modulify(_ path: String, name: String) throws -> Module {
        let walked = walk(path, recursing: shouldConsiderDirectory).map{ $0 }
        
        let cSources = walked.filter{ isValidSource($0, validExtensions: Sources.validCExtensions) }
        let swiftSources = walked.filter{ isValidSource($0, validExtensions: Sources.validSwiftExtensions) }
        
        if !cSources.isEmpty {
            guard swiftSources.isEmpty else { throw Module.Error.MixedSources(path) }
            return try ClangModule(name: name, sources: Sources(paths: cSources, root: path))
        }
        
        guard !swiftSources.isEmpty else { throw Module.Error.NoSources(path) }
        return try SwiftModule(name: name, sources: Sources(paths: swiftSources, root: path))
    }

    func isValidSource(_ path: String) -> Bool {
        return isValidSource(path, validExtensions: Sources.validExtensions)
    }
    
    func isValidSource(_ path: String, validExtensions: Set<String>) -> Bool {
        if path.basename.hasPrefix(".") { return false }
        let path = path.normpath
        if path == manifest.path.normpath { return false }
        if excludes.contains(path) { return false }
        if !path.isFile { return false }
        guard let ext = path.fileExt else { return false }
        return validExtensions.contains(ext)
    }

    private func targetForName(_ name: String) -> Target? {
        return manifest.package.targets.pick{ $0.name == name }
    }
}
