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
                let sourcified = try sourcify(srcroot)
                if sourcified.isSwiftModule {
                    modules = [SwiftModule(name: self.name, sources: sourcified.sources)]
                } else {
                    modules = [CLangModule(name: self.name, sources: sourcified.sources)]
                }
                
            } catch Module.Error.NoSources {
                throw ModuleError.NoModules(self)
            }
        } else {
            modules = try maybeModules.map(sourcify).map { sourcified in
                let name: String
                if sourcified.sources.root == srcroot {
                    name = self.name
                } else {
                    name = sourcified.sources.root.basename
                }
                if sourcified.isSwiftModule {
                    return SwiftModule(name: name, sources: sourcified.sources)
                }
                return CLangModule(name: name, sources: sourcified.sources)
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

    func sourcify(path: String) throws -> (sources: Sources, isSwiftModule: Bool) {
        let sources = walk(path, recursing: shouldConsiderDirectory).filter(isValidSource)
        guard sources.count > 0 else { throw Module.Error.NoSources(path) }
        let partioned = sources.partition { $0.hasSuffix(".swift") }
        guard !(partioned.0.count > 0 && partioned.1.count > 0) else { throw Module.Error.MixedSources(path) }
        return (sources: Sources(paths: sources, root: path), isSwiftModule: partioned.0.count > 0)
    }

    func isValidSource(path: String) -> Bool {
        if path.basename.hasPrefix(".") { return false }
        let path = path.normpath
        if path == manifest.path.normpath { return false }
        if excludes.contains(path) { return false }
        if !path.isFile { return false }
        for ext in Sources.validExtensions {
            if path.lowercased().hasSuffix(ext) {
                return true
            }
        }
        return false
    }

    private func targetForName(name: String) -> Target? {
        return manifest.package.targets.pick{ $0.name == name }
    }
}
