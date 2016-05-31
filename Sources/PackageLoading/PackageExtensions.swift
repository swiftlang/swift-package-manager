/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageModel
import Utility

import class PackageDescription.Target

extension Package {
    /// An error in the package organization of modules.
    enum ModuleError: ErrorProtocol {
        case noModules(Package)
        case modulesNotFound([String])
        case invalidLayout(InvalidLayoutType)
        case executableAsDependency(String)
    }

    enum InvalidLayoutType {
        case multipleSourceRoots([String])
        case invalidLayout([String])
    }
}

extension Package.InvalidLayoutType: CustomStringConvertible {
    var description: String {
        switch self {
        case .multipleSourceRoots(let paths):
            return "multiple source roots found: " + paths.joined(separator: ", ")
        case .invalidLayout(let paths):
            return "unexpected source file(s) found: " + paths.joined(separator: ", ")
        }
    }
}

extension Module {
    /// An error in the organization of an individual module.
    enum Error: ErrorProtocol {
        case noSources(String)
        case mixedSources(String)
        case duplicateModule(String)
    }
}

extension Product {
    /// An error in a product definition.
    enum Error: ErrorProtocol {
        case noModules(String)
    }
}

extension Package {
    private func sourceRoot() throws -> String {
        let viableRoots = walk(path, recursively: false).filter { entry in
            switch entry.basename.lowercased() {
            case "sources", "source", "src", "srcs":
                return entry.isDirectory && !manifest.package.exclude.contains(entry)
            default:
                return false
            }
        }

        switch viableRoots.count {
        case 0:
            return path.normpath
        case 1:
            return viableRoots[0]
        default:
            // eg. there is a `Sources' AND a `src'
            throw ModuleError.invalidLayout(.multipleSourceRoots(viableRoots))
        }
    }

    /// Collects the modules which are defined by a package.
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
                throw ModuleError.invalidLayout(.invalidLayout(invalidRootFiles))
            }
        }

        let maybeModules = walk(srcroot, recursively: false).filter(shouldConsiderDirectory)

        if maybeModules.count == 1 && maybeModules[0] != srcroot {
            let invalidModuleFiles = walk(srcroot, recursively: false).filter(isValidSource)
            guard invalidModuleFiles.isEmpty else {
                throw ModuleError.invalidLayout(.invalidLayout(invalidModuleFiles))
            }
        }

        let modules: [Module]
        if maybeModules.isEmpty {
            do {
                modules = [try modulify(srcroot, name: self.name)]
            } catch Module.Error.noSources {
                throw ModuleError.noModules(self)
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

            module.dependencies = try target.dependencies.map {
                switch $0 {
                case .Target(let name):
                    guard let dependency = moduleForName(name) else {
                        throw ModuleError.modulesNotFound([name])
                    }
                    if let moduleType = dependency as? ModuleTypeProtocol where moduleType.type != .library {
                        throw ModuleError.executableAsDependency("\(module.name) cannot have an executable \(name) as a dependency")
                    }
                    return dependency
                }
            }
        }

        /// Check for targets that are not mapped to any modules
        let targetNames = Set(manifest.package.targets.map{ $0.name })
        let moduleNames = Set(modules.map{ $0.name })
        let diff = targetNames.subtracting(moduleNames)
            
        if diff.count > 0 {
            throw ModuleError.modulesNotFound(Array(diff))
        }

        return modules
    }
    
    private func modulify(_ path: String, name: String) throws -> Module {
        let walked = walk(path, recursing: shouldConsiderDirectory).map{ $0 }
        
        let cSources = walked.filter{ isValidSource($0, validExtensions: Sources.validCFamilyExtensions) }
        let swiftSources = walked.filter{ isValidSource($0, validExtensions: Sources.validSwiftExtensions) }
        
        if !cSources.isEmpty {
            guard swiftSources.isEmpty else { throw Module.Error.mixedSources(path) }
            return try ClangModule(name: name, sources: Sources(paths: cSources, root: path))
        }
        
        guard !swiftSources.isEmpty else { throw Module.Error.noSources(path) }
        return try SwiftModule(name: name, sources: Sources(paths: swiftSources, root: path))
    }

    private func isValidSource(_ path: String) -> Bool {
        return isValidSource(path, validExtensions: Sources.validExtensions)
    }
    
    private func isValidSource(_ path: String, validExtensions: Set<String>) -> Bool {
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


extension Package {
    /// Collects the products defined by a package.
    func products(_ allModules: [Module]) throws -> [Product] {
        var products = [Product]()

        let testModules: [TestModule]
        let modules: [Module]
        (testModules, modules) = allModules.partition()

    ////// first auto-determine executables

        for case let module as SwiftModule in modules {
            if module.type == .executable {
                let product = Product(name: module.name, type: .Executable, modules: [module])
                products.append(product)
            }
        }

    ////// auto-determine tests

        if !testModules.isEmpty {
            let modules: [SwiftModule] = testModules.map{$0} // or linux compiler crash (2016-02-03)
            //TODO and then we should prefix all modules with their package probably
            //Suffix 'Tests' to test product so the module name of linux executable don't collide with
            //main package, if present.
            let product = Product(name: "\(self.name)Tests", type: .Test, modules: modules)
            products.append(product)
        }

    ////// add products from the manifest

        for p in manifest.products {
            let modules: [SwiftModule] = p.modules.flatMap{ moduleName in
                guard case let picked as SwiftModule = (modules.pick{ $0.name == moduleName }) else {
                    print("warning: No module \(moduleName) found for product \(p.name)")
                    return nil
                }
                return picked
            }

            guard !modules.isEmpty else {
                throw Product.Error.noModules(p.name)
            }

            let product = Product(name: p.name, type: p.type, modules: modules)
            products.append(product)
        }

        return products
    }
}

extension Package {
    func shouldConsiderDirectory(_ path: String) -> Bool {
        let base = path.basename.lowercased()
        if base == "tests" { return false }
        if base == "include" { return false }
        if base.hasSuffix(".xcodeproj") { return false }
        if base.hasSuffix(".playground") { return false }
        if base.hasPrefix(".") { return false }  // eg .git
        if excludes.contains(path) { return false }
        if path.normpath == packagesDirectory.normpath { return false }
        if !path.isDirectory { return false }
        return true
    }

    private var packagesDirectory: String {
        return Path.join(path, "Packages")
    }

    var excludes: [String] {
        return manifest.package.exclude.map{ Path.join(self.path, $0).normpath }
    }
}

extension Package {
    func testModules() throws -> [TestModule] {
        let testsPath = Path.join(path, "Tests")
        //Don't try to walk Tests if it is in excludes
        if testsPath.isDirectory && excludes.contains(testsPath) { return [] }
        return try walk(testsPath, recursively: false).filter(shouldConsiderDirectory).flatMap { dir in
            let sources = walk(dir, recursing: shouldConsiderDirectory).filter{ isValidSource($0, validExtensions: Sources.validSwiftExtensions) }
            if sources.count > 0 {
                return try TestModule(basename: dir.basename, sources: Sources(paths: sources, root: dir))
            } else {
                print("warning: no sources in test module: \(path)")
                return nil
            }
        }
    }
}
