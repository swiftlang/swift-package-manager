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
            return [CModule(name: name, path: path)]
        }

        let srcroot = try sourceRoot()

        if srcroot != path {
            guard walk(path, recursively: false).filter(isValidSource).isEmpty else {
                throw ModuleError.InvalidLayout(.InvalidLayout)
            }
        }

        let maybeModules = walk(srcroot, recursively: false).filter(shouldConsiderDirectory)

        if maybeModules.count == 1 && maybeModules[0] != srcroot {
            guard walk(srcroot, recursively: false).filter(isValidSource).isEmpty else {
                throw ModuleError.InvalidLayout(.InvalidLayout)
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

        func moduleForName(name: String) -> Module? {
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
    
    func modulify(path: String, name: String) throws -> Module {
        let walked = walk(path, recursing: shouldConsiderDirectory).map{ $0 }
        
        let cSources = walked.filter{ isValidSource($0, validExtensions: Sources.validCExtensions) }
        let swiftSources = walked.filter{ isValidSource($0, validExtensions: Sources.validSwiftExtensions) }
                
        guard cSources.count > 0 || swiftSources.count > 0 else { throw Module.Error.NoSources(path) }
        guard !(cSources.count > 0 && swiftSources.count > 0) else { throw Module.Error.MixedSources(path) }
        
        let isSwiftModule = swiftSources.count > 0 //We've already made sure that it'll can be only either of the two.
            let sources = Sources(paths: isSwiftModule ? swiftSources : cSources, root: path)
        
        if isSwiftModule {
            return SwiftModule(name: name, sources: sources)
        }
        return ClangModule(name: name, sources: sources)
    }

    func isValidSource(path: String) -> Bool {
        return isValidSource(path, validExtensions: Sources.validExtensions)
    }
    
    func isValidSource(path: String, validExtensions: Set<String>) -> Bool {
        if path.basename.hasPrefix(".") { return false }
        let path = path.normpath
        if path == manifest.path.normpath { return false }
        if excludes.contains(path) { return false }
        if !path.isFile { return false }
        guard let ext = path.fileExt else { return false }
        return validExtensions.contains(ext)
    }

    private func targetForName(name: String) -> Target? {
        return manifest.package.targets.pick{ $0.name == name }
    }
}
