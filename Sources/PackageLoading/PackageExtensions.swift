/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel
import Utility

import class PackageDescription.Target

public enum ModuleError: Swift.Error {
    case noModules(Package)
    case modulesNotFound([String])
    case invalidLayout(InvalidLayoutType)
    case executableAsDependency(module: String, dependency: String)
}

public enum InvalidLayoutType {
    case multipleSourceRoots([String])
    case invalidLayout([String])
}

extension ModuleError: FixableError {
    public var error: String {
        switch self {
        case .noModules(let package):
            return "the package \(package) contains no modules"
        case .modulesNotFound(let modules):
            return "these referenced modules could not be found: " + modules.joined(separator: ", ")
        case .invalidLayout(let type):
            return "the package has an unsupported layout, \(type.error)"
        case .executableAsDependency(let module, let dependency):
            return "the target \(module) cannot have the executable \(dependency) as a dependency"
        }
    }

    public var fix: String? {
        switch self {
        case .noModules(_):
            return "create at least one module"
        case .modulesNotFound(_):
            return "reference only valid modules"
        case .invalidLayout(let type):
            return type.fix
        case .executableAsDependency(_):
            return "move the shared logic inside a library, which can be referenced from both the target and the executable"
        }
    }
}

extension InvalidLayoutType: FixableError {
    public var error: String {
        switch self {
        case .multipleSourceRoots(let paths):
            return "multiple source roots found: " + paths.joined(separator: ", ")
        case .invalidLayout(let paths):
            return "unexpected source file(s) found: " + paths.joined(separator: ", ")
        }
    }

    public var fix: String? {
        switch self {
        case .multipleSourceRoots(_):
            return "remove the extra source roots, or add them to the source root exclude list"
        case .invalidLayout(_):
            return "move the file(s) inside a module"
        }
    }
}

extension Module {
    /// An error in the organization of an individual module.
    enum Error: Swift.Error {
        case noSources(String)
        case mixedSources(String)
        case duplicateModule(String)
    }
}

extension Module.Error: FixableError {
    var error: String {
        switch self {
        case .noSources(let path):
            return "the module at \(path) does not contain any source files"
        case .mixedSources(let path):
            return "the module at \(path) contains mixed language source files"
        case .duplicateModule(let name):
            return "multiple modules with the name \(name) found"
        }
    }

    var fix: String? {
        switch self {
        case .noSources(_):
            return "either remove the module folder, or add a source file to the module"
        case .mixedSources(_):
            return "use only a single language within a module"
        case .duplicateModule(_):
            return "modules should have a unique name across dependencies"
        }
    }
}

extension Product {
    /// An error in a product definition.
    enum Error: Swift.Error {
        case noModules(String)
        case moduleNotFound(product: String, module: String)
    }
}

extension Product.Error: FixableError {
    var error: String {
        switch self {
        case .noModules(let product):
            return "the product named \(product) doesn't reference any modules"
        case .moduleNotFound(let product, let module):
            return "the product named \(product) references a module that could not be found: \(module)"
        }
    }

    var fix: String? {
        switch self {
        case .noModules(_):
            return "reference one or more modules from the product"
        case .moduleNotFound(_):
            return "reference only valid modules from the product"
        }
    }
}

extension Package {
    private func sourceRoot() throws -> AbsolutePath {
        let viableRoots = walk(path, recursively: false).filter { entry in
            switch entry.basename.lowercased() {
            case "sources", "source", "src", "srcs":
                return entry.asString.isDirectory && !excludedPaths.contains(entry)
            default:
                return false
            }
        }

        switch viableRoots.count {
        case 0:
            return path
        case 1:
            return viableRoots[0]
        default:
            // eg. there is a `Sources' AND a `src'
            throw ModuleError.invalidLayout(.multipleSourceRoots(viableRoots.map{ $0.asString }))
        }
    }

    /// Collects the modules which are defined by a package.
    func modules() throws -> [Module] {
        let moduleMapPath = path.appending("module.modulemap")
        if moduleMapPath.asString.isFile {
            let sources = Sources(paths: [moduleMapPath], root: path)
            return [try CModule(name: name, sources: sources, path: path, pkgConfig: pkgConfigPath, providers: manifest.package.providers)]
        }

        if manifest.package.exclude.contains(".") {
            return []
        }

        let srcroot = try sourceRoot()

        if srcroot != path {
            let invalidRootFiles = walk(path, recursively: false).filter(isValidSource)
            guard invalidRootFiles.isEmpty else {
                throw ModuleError.invalidLayout(.invalidLayout(invalidRootFiles.map{ $0.asString }))
            }
        }

        let maybeModules = walk(srcroot, recursively: false).filter(shouldConsiderDirectory)

        if maybeModules.count == 1 && maybeModules[0] != srcroot {
            let invalidModuleFiles = walk(srcroot, recursively: false).filter(isValidSource)
            guard invalidModuleFiles.isEmpty else {
                throw ModuleError.invalidLayout(.invalidLayout(invalidModuleFiles.map{ $0.asString }))
            }
        }

        let modules: [Module]
        if maybeModules.isEmpty {
            do {
                modules = [try modulify(srcroot, name: self.name, isTest: false)]
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
                return try modulify(path, name: name, isTest: false)
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
                    if dependency.type != .library {
                        throw ModuleError.executableAsDependency(module: module.name, dependency: name)
                    }
                    return dependency
                }
            }
        }

        /// Check for targets that are not mapped to any modules.
        let targetNames = Set(manifest.package.targets.map{ $0.name })
        let moduleNames = Set(modules.map{ $0.name })
        let diff = targetNames.subtracting(moduleNames)
            
        guard diff.isEmpty else {
            throw ModuleError.modulesNotFound(Array(diff))
        }

        return modules
    }
    
    fileprivate func modulify(_ path: AbsolutePath, name: String, isTest: Bool) throws -> Module {
        let walked = walk(path, recursing: shouldConsiderDirectory).map{ $0 }
        
        let cSources = walked.filter{ isValidSource($0, validExtensions: SupportedLanguageExtension.cFamilyExtensions) }
        let swiftSources = walked.filter{ isValidSource($0, validExtensions: SupportedLanguageExtension.swiftExtensions) }
        
        if !cSources.isEmpty {
            guard swiftSources.isEmpty else { throw Module.Error.mixedSources(path.asString) }
            return try ClangModule(name: name, isTest: isTest, sources: Sources(paths: cSources, root: path))
        }
        
        guard !swiftSources.isEmpty else { throw Module.Error.noSources(path.asString) }
        return try SwiftModule(name: name, isTest: isTest, sources: Sources(paths: swiftSources, root: path))
    }

    private func isValidSource(_ path: AbsolutePath) -> Bool {
        return isValidSource(path, validExtensions: SupportedLanguageExtension.validExtensions)
    }
    
    private func isValidSource(_ path: AbsolutePath, validExtensions: Set<String>) -> Bool {
        if path.basename.hasPrefix(".") { return false }
        if path == manifest.path { return false }
        if excludedPaths.contains(path) { return false }
        if !path.asString.isFile { return false }
        guard let ext = path.asString.fileExt else { return false }
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

        let testModules: [Module]
        let modules: [Module]
        (testModules, modules) = allModules.partition { $0.isTest }

    ////// first auto-determine executables

        for case let module as SwiftModule in modules {
            if module.type == .executable {
                let product = Product(name: module.name, type: .Executable, modules: [module])
                products.append(product)
            }
        }

    ////// Implict products for ClangModules.

        for case let module as ClangModule in modules {
            let type: ProductType
            switch module.type {
            case .executable:
                type = .Executable
            case .library:
                type = .Library(.Dynamic)
            case .systemModule:
                fatalError("unexpected module type")
            }
            let product = Product(name: module.name, type: type, modules: [module])
            products.append(product)
        }

    ////// auto-determine tests

        if !testModules.isEmpty {
            //TODO and then we should prefix all modules with their package probably
            //Suffix 'Tests' to test product so the module name of linux executable don't collide with
            //main package, if present.
            // FIXME: Ignore C language test modules on linux for now.
          #if os(Linux)
            let testModules = testModules.filter { module in
                if module is ClangModule {
                    print("warning: Ignoring \(module.name) as C language in tests is not yet supported on Linux.")
                    return false
                }
                return true
            }
          #endif
            let product = Product(name: "\(self.name)Tests", type: .Test, modules: testModules)
            products.append(product)
        }

    ////// add products from the manifest

        for p in manifest.products {
            let modules: [Module] = try p.modules.flatMap{ moduleName in
                guard let picked = (modules.pick{ $0.name == moduleName }) else {
                    throw Product.Error.moduleNotFound(product: p.name, module: moduleName)
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
    func shouldConsiderDirectory(_ path: AbsolutePath) -> Bool {
        let base = path.basename.lowercased()
        if base == "tests" { return false }
        if base == "include" { return false }
        if base.hasSuffix(".xcodeproj") { return false }
        if base.hasSuffix(".playground") { return false }
        if base.hasPrefix(".") { return false }  // eg .git
        if excludedPaths.contains(path) { return false }
        if path == packagesDirectory { return false }
        if !path.asString.isDirectory { return false }
        return true
    }

    private var packagesDirectory: AbsolutePath {
        return path.appending("Packages")
    }

    var excludedPaths: [AbsolutePath] {
        return manifest.package.exclude.map { self.path.appending(RelativePath($0)) }
    }
    
    private var pkgConfigPath: RelativePath? {
        guard let pkgConfig = manifest.package.pkgConfig else { return nil }
        return RelativePath(pkgConfig)
    }
}

extension Package {
    func testModules(modules: [Module]) throws -> [Module] {
        let testsPath = self.path.appending("Tests")
        
        // Don't try to walk Tests if it is in excludes.
        if testsPath.asString.isDirectory && self.excludedPaths.contains(testsPath) { return [] }

        // Create the test modules
        let testModules = try walk(testsPath, recursively: false).filter(shouldConsiderDirectory).flatMap { dir in
            return [try modulify(dir, name: dir.basename, isTest: true)]
        }

        // Populate the test module dependencies.
        for case let testModule as SwiftModule in testModules {
            // FIXME: This is very inefficient, we want a map on the modules.
            if testModule.basename == "Basic" {
                // FIXME: The Basic tests currently have a layering
                // violation and a dependency on Utility for infrastructure.
                testModule.dependencies = modules.filter{
                    switch $0.name {
                    case "Basic", "Utility":
                        return true
                    default:
                        return false
                    }
                }
            } else if testModule.basename == "Functional" {
                // FIXME: swiftpm's own Functional tests module does not
                //        follow the normal rules--there is no corresponding
                //        'Sources/Functional' module to depend upon. For the
                //        time being, assume test modules named 'Functional'
                //        depend upon 'Utility', and hope that no users define
                //        test modules named 'Functional'.
                testModule.dependencies = modules.filter{
                    switch $0.name {
                    case "Basic", "Utility", "PackageModel":
                        return true
                    default:
                        return false
                    }
                }
            } else if testModule.basename == "PackageLoading" {
                // FIXME: Turns out PackageLoadingTests violate encapsulation :(
                testModule.dependencies = modules.filter{
                    switch $0.name {
                    case "Get", "PackageLoading":
                        return true
                    default:
                        return false
                    }
                }
            } else {
                // Normally, test modules are only dependent upon modules with
                // the same basename. For example, a test module in
                // 'Root/Tests/Foo' is dependent upon 'Root/Sources/Foo'.
                testModule.dependencies = modules.filter{ $0.name == testModule.basename }
            }
        }

        return testModules
    }
}
