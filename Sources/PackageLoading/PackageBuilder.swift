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

/// An error in the structure or layout of a package.
public enum ModuleError: Swift.Error {
    
    /// One or more referenced modules could not be found.
    case modulesNotFound([String])
    
    /// Package layout is invalid.
    case invalidLayout(InvalidLayoutType)
    
        /// Describes a way in which a package layout is invalid.
        public enum InvalidLayoutType {
            case multipleSourceRoots([String])
            case invalidLayout([String])
        }
    
    /// A module was marked as being dependent on an executable.
    case executableAsDependency(module: String, dependency: String)
}

extension ModuleError: FixableError {
    public var error: String {
        switch self {
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
        case .modulesNotFound(_):
            return "reference only valid modules"
        case .invalidLayout(let type):
            return type.fix
        case .executableAsDependency(_):
            return "move the shared logic inside a library, which can be referenced from both the target and the executable"
        }
    }
}

extension ModuleError.InvalidLayoutType: FixableError {
    public var error: String {
        switch self {
        case .multipleSourceRoots(let paths):
            return "multiple source roots found: " + paths.sorted().joined(separator: ", ")
        case .invalidLayout(let paths):
            return "unexpected source file(s) found: " + paths.sorted().joined(separator: ", ")
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
    }
}

extension Module.Error: FixableError {
    var error: String {
        switch self {
        case .noSources(let path):
            return "the module at \(path) does not contain any source files"
        case .mixedSources(let path):
            return "the module at \(path) contains mixed language source files"
        }
    }

    var fix: String? {
        switch self {
        case .noSources(_):
            return "either remove the module folder, or add a source file to the module"
        case .mixedSources(_):
            return "use only a single language within a module"
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

/// Helper for constructing a package following the convention system.
public struct PackageBuilder {
    /// The manifest for the package being constructed.
    private let manifest: Manifest

    /// The path of the package.
    private let packagePath: AbsolutePath

    /// The filesystem package builder will run on.
    private let fileSystem: FileSystem

    /// The stream to which warnings should be published.
    private let warningStream: OutputByteStream

    /// Create a builder for the given manifest and package `path`.
    ///
    /// - Parameters:
    ///   - path: The root path of the package.
    public init(manifest: Manifest, path: AbsolutePath, fileSystem: FileSystem = localFileSystem, warningStream: OutputByteStream = stdoutStream) {
        self.manifest = manifest
        self.packagePath = path
        self.fileSystem = fileSystem
        self.warningStream = warningStream
    }
    
    /// Build a new package following the conventions.
    ///
    /// - Parameters:
    ///   - includingTestModules: Whether the package's test modules should be loaded.
    public func construct(includingTestModules: Bool) throws -> Package {
        let modules = try constructModules()
        let testModules: [Module]
        if includingTestModules {
            testModules = try constructTestModules(modules: modules)
        } else {
            testModules = []
        }
        let products = try constructProducts(modules, testModules: testModules)
        return Package(manifest: manifest, path: packagePath, modules: modules, testModules: testModules, products: products)
    }

    // MARK: Utility Predicates
    
    private func isValidSource(_ path: AbsolutePath) -> Bool {
        return isValidSource(path, validExtensions: SupportedLanguageExtension.validExtensions)
    }
    
    private func isValidSource(_ path: AbsolutePath, validExtensions: Set<String>) -> Bool {
        if path.basename.hasPrefix(".") { return false }
        if path == manifest.path { return false }
        if excludedPaths.contains(path) { return false }
        if !fileSystem.isFile(path) { return false }
        guard let ext = path.extension else { return false }
        return validExtensions.contains(ext)
    }
    
    private func shouldConsiderDirectory(_ path: AbsolutePath) -> Bool {
        let base = path.basename.lowercased()
        if base == "tests" { return false }
        if base == "include" { return false }
        if base.hasSuffix(".xcodeproj") { return false }
        if base.hasSuffix(".playground") { return false }
        if base.hasPrefix(".") { return false }  // eg .git
        if excludedPaths.contains(path) { return false }
        if path == packagesDirectory { return false }
        if !fileSystem.isDirectory(path) { return false }
        return true
    }

    private var packagesDirectory: AbsolutePath {
        return packagePath.appending(component: "Packages")
    }

    private var excludedPaths: [AbsolutePath] {
        return manifest.package.exclude.map { packagePath.appending(RelativePath($0)) }
    }
    
    private var pkgConfigPath: RelativePath? {
        guard let pkgConfig = manifest.package.pkgConfig else { return nil }
        return RelativePath(pkgConfig)
    }

    /// Returns path to all the items in a directory.
    /// FIXME: This is generic functionality, and should move to FileSystem.
    func directoryContents(_ path: AbsolutePath) throws -> [AbsolutePath] {
        return try fileSystem.getDirectoryContents(path).map { path.appending(component: $0) }
    }

    /// Returns the path of the source directory, throwing an error in case of an invalid layout (such as the presence of both `Sources` and `src` directories).
    func sourceRoot() throws -> AbsolutePath {
        let viableRoots = try fileSystem.getDirectoryContents(packagePath).filter { basename in
            let entry = packagePath.appending(component: basename)
            switch basename.lowercased() {
            case "sources", "source", "src", "srcs":
                return fileSystem.isDirectory(entry) && !excludedPaths.contains(entry)
            default:
                return false
            }
        }

        switch viableRoots.count {
        case 0:
            return packagePath
        case 1:
            return packagePath.appending(component: viableRoots[0])
        default:
            // eg. there is a `Sources' AND a `src'
            throw ModuleError.invalidLayout(.multipleSourceRoots(viableRoots.map{ packagePath.appending(component: $0).asString }))
        }
    }

    /// Private function that creates and returns a list of non-test Modules defined by a package.
    private func constructModules() throws -> [Module] {
        
        // Check for a modulemap file, which indicates a system module.
        let moduleMapPath = packagePath.appending(component: "module.modulemap")
        if fileSystem.isFile(moduleMapPath) {
            // Package contains a modulemap at the top level, so we assuming it's a system module.
            let sources = Sources(paths: [moduleMapPath], root: packagePath)
            return [try CModule(name: manifest.name, sources: sources, path: packagePath, pkgConfig: pkgConfigPath, providers: manifest.package.providers)]
        }

        // If everything is excluded, just return an empty array.
        if manifest.package.exclude.contains(".") {
            return []
        }
        
        // Locate the source directory inside the package.
        let srcDir = try sourceRoot()
        
        // If there is a source directory, we expect all source files to be located in it.
        if srcDir != packagePath {
            let invalidRootFiles = try directoryContents(packagePath).filter(isValidSource)
            guard invalidRootFiles.isEmpty else {
                throw ModuleError.invalidLayout(.invalidLayout(invalidRootFiles.map{ $0.asString }))
            }
        }
        
        // Locate any directories that might be the roots of modules inside the source directory.
        let potentialModulePaths = try directoryContents(srcDir).filter(shouldConsiderDirectory)
        
        // If there's a single module inside the source directory, make sure there are no loose source files in the sources directory.
        if potentialModulePaths.count == 1 && potentialModulePaths[0] != srcDir {
            let invalidModuleFiles = try directoryContents(srcDir).filter(isValidSource)
            guard invalidModuleFiles.isEmpty else {
                throw ModuleError.invalidLayout(.invalidLayout(invalidModuleFiles.map{ $0.asString }))
            }
        }
        
        // With preliminary checks done, we can start creating modules.
        let modules: [Module]
        if potentialModulePaths.isEmpty {
            // There are no directories that look like modules, so try to create a module for the source directory itself (with the name coming from the name in the manifest).
            do {
                modules = [try createModule(srcDir, name: manifest.name, isTest: false)]
            }
            catch Module.Error.noSources {
                // Completely empty packages are allowed as a special case.
                modules = []
            }
        } else {
            // We have at least one directory that looks like a module, so we try to create a module for each one.
            modules = try potentialModulePaths.map { path in
                try createModule(path, name: path.basename, isTest: false)
            }
        }

        // Create a map of modules indexed by name.
        var modulesByName = [String: Module]()
        for module in modules {
            modulesByName[module.name] = module
        }

        // Collect the declared module dependencies from the manifest.
        //
        // The remaining modules are left with their (empty) dependencies.
        var missingModuleNames = [String]()
        for target in manifest.package.targets {
            // Find the matching module.
            guard let module = modulesByName[target.name] else {
                // The manifest referenced an undefined module.
                missingModuleNames.append(target.name)
                continue
            }

            // Collect the dependencies.
            module.dependencies = try target.dependencies.map {
                switch $0 {
                case .Target(let name):
                    guard let dependency = modulesByName[name] else {
                        throw ModuleError.modulesNotFound([name])
                    }
                    if dependency.type != .library {
                        throw ModuleError.executableAsDependency(module: module.name, dependency: name)
                    }
                    return dependency
                }
            }
        }

        // Check for targets that are not mapped to any modules.
        guard missingModuleNames.isEmpty else {
            throw ModuleError.modulesNotFound(missingModuleNames)
        }

        return modules
    }
    
    /// Private function that constructs a single Module object for the moduel at `path`, having the name `name`.  If `isTest` is true, the module is constructed as a test module; if false, it is a regular module.
    private func createModule(_ path: AbsolutePath, name: String, isTest: Bool) throws -> Module {
        // Find all the files under the module path.
        let walked = try walk(path, fileSystem: fileSystem, recursing: shouldConsiderDirectory).map{ $0 }
        
        // Select any source files for the C-based languages and for Swift.
        let cSources = walked.filter{ isValidSource($0, validExtensions: SupportedLanguageExtension.cFamilyExtensions) }
        let swiftSources = walked.filter{ isValidSource($0, validExtensions: SupportedLanguageExtension.swiftExtensions) }
        
        // Create and return the right kind of module depending on what kind of sources we found.
        if cSources.isEmpty {
            // No C sources, so we expect to have Swift sources, and we create a Swift module.
            guard !swiftSources.isEmpty else { throw Module.Error.noSources(path.asString) }
            return try SwiftModule(name: name, isTest: isTest, sources: Sources(paths: swiftSources, root: path))
        } else {
            // No Swift sources, so we expect to have C sources, and we create a C module.
            guard swiftSources.isEmpty else { throw Module.Error.mixedSources(path.asString) }
            return try ClangModule(name: name, isTest: isTest, sources: Sources(paths: cSources, root: path))
        }
    }

    /// Collects the products defined by a package.
    private func constructProducts(_ modules: [Module], testModules: [Module]) throws -> [Product] {
        var products = [Product]()

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

        // FIXME: Ignore C language test modules on linux for now.
      #if os(Linux)
        let testModules = testModules.filter { module in
            if module is ClangModule {
                warningStream <<< "warning: Ignoring \(module.name) as C language in tests is not yet supported on Linux."
                warningStream.flush()
                return false
            }
            return true
        }
      #endif
        if !testModules.isEmpty {
            //TODO and then we should prefix all modules with their package probably
            //Suffix 'Tests' to test product so the module name of linux executable don't collide with
            //main package, if present.
            let product = Product(name: manifest.name + "Tests", type: .Test, modules: testModules)
            products.append(product)
        }

    ////// add products from the manifest

        for p in manifest.products {
            let modules: [Module] = try p.modules.map{ moduleName in
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

    private func constructTestModules(modules: [Module]) throws -> [Module] {
        let testsPath = packagePath.appending(component: "Tests")
        
        // Don't try to walk Tests if it is in excludes or doesn't exists.
        guard fileSystem.isDirectory(testsPath) && !excludedPaths.contains(testsPath) else {
            return []
        }

        // Create the test modules
        let testModules = try directoryContents(testsPath).filter(shouldConsiderDirectory).flatMap { dir in
            return [try createModule(dir, name: dir.basename, isTest: true)]
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
