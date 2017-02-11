/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel
import Utility

import enum PackageDescription.ProductType

/// An error in the structure or layout of a package.
public enum ModuleError: Swift.Error {

    /// Indicates two modules with the same name.
    case duplicateModule(String)
    
    /// One or more referenced modules could not be found.
    case modulesNotFound([String])
    
    /// Package layout is invalid.
    case invalidLayout(InvalidLayoutType)
    
        /// Describes a way in which a package layout is invalid.
        public enum InvalidLayoutType {
            case multipleSourceRoots([String])
            case unexpectedSourceFiles([String])
            case modulemapInSources(String)
        }
    
    /// The manifest has invalid configuration wrt type of the module.
    case invalidManifestConfig(String, String)

    /// The target dependency declaration has cycle in it.
    case cycleDetected((path: [String], cycle: [String]))
}

extension ModuleError: FixableError {
    public var error: String {
        switch self {
        case .duplicateModule(let name):
            return "multiple modules with the name \(name) found"
        case .modulesNotFound(let modules):
            return "these referenced modules could not be found: " + modules.joined(separator: ", ")
        case .invalidLayout(let type):
            return "the package has an unsupported layout, \(type.error)"
        case .invalidManifestConfig(let package, let message):
            return "invalid configuration in '\(package)': \(message)"
        case .cycleDetected(let cycle):
            return "found cyclic dependency declaration: " +
                (cycle.path + cycle.cycle).joined(separator: " -> ") +
                " -> " + cycle.cycle[0]
        }
    }

    public var fix: String? {
        switch self {
        case .duplicateModule(_):
            return "modules should have a unique name across dependencies"
        case .modulesNotFound(_):
            return "reference only valid modules"
        case .invalidLayout(let type):
            return type.fix
        case .invalidManifestConfig(_):
            return nil
        case .cycleDetected(_):
            return nil
        }
    }
}

extension ModuleError.InvalidLayoutType: FixableError {
    public var error: String {
        switch self {
        case .multipleSourceRoots(let paths):
            return "multiple source roots found: " + paths.sorted().joined(separator: ", ")
        case .unexpectedSourceFiles(let paths):
            return "unexpected source file(s) found: " + paths.sorted().joined(separator: ", ")
        case .modulemapInSources(let path):
            return "modulemap (\(path)) is not allowed to be mixed with sources"
        }
    }

    public var fix: String? {
        switch self {
        case .multipleSourceRoots(_):
            return "remove the extra source roots, or add them to the source root exclude list"
        case .unexpectedSourceFiles(_):
            return "move the file(s) inside a module"
        case .modulemapInSources(_):
            return "move the modulemap inside include directory"
        }
    }
}

extension Module {
    
    /// An error in the organization or configuration of an individual module.
    enum Error: Swift.Error {
        
        /// The module's name is invalid.
        case invalidName(path: String, name: String, problem: ModuleNameProblem)
        enum ModuleNameProblem {
            /// Empty module name.
            case emptyName
            /// Test module doesn't have a "Tests" suffix.
            case noTestSuffix
            /// Non-test module does have a "Tests" suffix.
            case hasTestSuffix
        }
        
        /// The module contains an invalid mix of languages (e.g. both Swift and C).
        case mixedSources(String)
    }
}

extension Module.Error: FixableError {
    var error: String {
        switch self {
          case .invalidName(let path, let name, let problem):
            return "the directory \(path) has an invalid name ('\(name)'): \(problem.error)"
          case .mixedSources(let path):
            return "the module at \(path) contains mixed language source files"
        }
    }

    var fix: String? {
        switch self {
        case .invalidName(let path, _, let problem):
            return "rename the directory '\(path)'\(problem.fix ?? "")"
        case .mixedSources(_):
            return "use only a single language within a module"
        }
    }
}

extension Module.Error.ModuleNameProblem : FixableError {
    var error: String {
        switch self {
          case .emptyName:
            return "the module name is empty"
          case .noTestSuffix:
            return "the name of a test module has no 'Tests' suffix"
          case .hasTestSuffix:
            return "the name of a non-test module has a 'Tests' suffix"
        }
    }
    var fix: String? {
        switch self {
          case .emptyName:
            return " to have a non-empty name"
          case .noTestSuffix:
            return " to have a 'Tests' suffix"
          case .hasTestSuffix:
            return " to not have a 'Tests' suffix"
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
/// FIXME: This is a very confusing name, in light of the fact that SwiftPM has
/// a build system; we should avoid using the word "build" here.
public struct PackageBuilder {
    /// The manifest for the package being constructed.
    private let manifest: Manifest

    /// The path of the package.
    private let packagePath: AbsolutePath

    /// The filesystem package builder will run on.
    private let fileSystem: FileSystem

    /// The stream to which warnings should be published.
    private let warningStream: OutputByteStream

    /// Create a product for all of the package's library targets.
    private let createImplicitProduct: Bool

    /// Create a builder for the given manifest and package `path`.
    ///
    /// - Parameters:
    ///   - manifest: The manifest of this package.
    ///   - path: The root path of the package.
    ///   - fileSystem: The file system on which the builder should be run.
    ///   - warningStream: The stream on which warnings should be emitted.
    ///   - createImplicitProduct: If there should be an implicit product 
    ///         created for all of the package's library targets.
    public init(
        manifest: Manifest,
        path: AbsolutePath,
        fileSystem: FileSystem = localFileSystem,
        warningStream: OutputByteStream = stdoutStream,
        createImplicitProduct: Bool
    ) {
        self.createImplicitProduct = createImplicitProduct
        self.manifest = manifest
        self.packagePath = path
        self.fileSystem = fileSystem
        self.warningStream = warningStream
    }
    
    /// Build a new package following the conventions.
    public func construct() throws -> Package {
        let modules = try constructModules()
        let products = try constructProducts(modules)
        return Package(
            manifest: manifest,
            path: packagePath,
            modules: modules,
            products: products
        )
    }

    // MARK: Utility Predicates
    
    private func isValidSource(_ path: AbsolutePath) -> Bool {
        // Ignore files which don't match the expected extensions.
        guard let ext = path.extension, SupportedLanguageExtension.validExtensions.contains(ext) else {
            return false
        }
        
        // Ignore dotfiles.
        let basename = path.basename
        if basename.hasPrefix(".") { return false }
        
        // Ignore symlinks to non-files.
        if !fileSystem.isFile(path) { return false }
        
        // Ignore excluded files.
        if excludedPaths.contains(path) { return false }

        // Ignore manifest files.
        if path.parentDirectory == packagePath {
            if basename == Manifest.filename { return false }

            // Ignore version-specific manifest files.
            if basename.hasPrefix(Manifest.basename + "@") && basename.hasSuffix(".swift") {
                return false
            }
        }

        // Otherwise, we have a valid source file.
        return true
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
    
    /// Returns path to all the items in a directory.
    /// FIXME: This is generic functionality, and should move to FileSystem.
    func directoryContents(_ path: AbsolutePath) throws -> [AbsolutePath] {
        return try fileSystem.getDirectoryContents(path).map { path.appending(component: $0) }
    }

    /// Returns the path of the source directory, throwing an error in case of an invalid layout (such as the presence of both `Sources` and `src` directories).
    func sourceRoot() throws -> AbsolutePath {
        let viableRoots = try fileSystem.getDirectoryContents(packagePath).filter { basename in
            let entry = packagePath.appending(component: basename)
            if PackageBuilder.isSourceDirectory(pathComponent: basename) {
                return fileSystem.isDirectory(entry) && !excludedPaths.contains(entry)
            }
            return false
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

    /// Returns true if pathComponent indicates a reserved directory.
    public static func isReservedDirectory(pathComponent: String) -> Bool {
        return isPackageDirectory(pathComponent: pathComponent) ||
            isSourceDirectory(pathComponent: pathComponent) ||
            isTestDirectory(pathComponent: pathComponent)
    }

    /// Returns true if pathComponent indicates a package directory.
    public static func isPackageDirectory(pathComponent: String) -> Bool {
        return pathComponent.lowercased() == "packages"
    }

    /// Returns true if pathComponent indicates a source directory.
    public static func isSourceDirectory(pathComponent: String) -> Bool {
        switch pathComponent.lowercased() {
        case "sources", "source", "src", "srcs":
            return true
        default:
            return false
        }
    }

    /// Returns true if pathComponent indicates a test directory.
    public static func isTestDirectory(pathComponent: String) -> Bool {
        return pathComponent.lowercased() == "tests"
    }

    /// Private function that creates and returns a list of non-test Modules defined by a package.
    private func constructModules() throws -> [Module] {
        
        // Check for a modulemap file, which indicates a system module.
        let moduleMapPath = packagePath.appending(component: "module.modulemap")
        if fileSystem.isFile(moduleMapPath) {
            // Package contains a modulemap at the top level, so we assuming it's a system module.
            return [CModule(
                        name: manifest.name,
                        path: packagePath,
                        pkgConfig: manifest.package.pkgConfig,
                        providers: manifest.package.providers)]
        }

        // At this point the module can't be a system module, make sure manifest doesn't contain
        // system module specific configuration.
        guard manifest.package.pkgConfig == nil else {
            throw ModuleError.invalidManifestConfig(manifest.name, "pkgConfig should only be used with a System Module Package")
        }
        guard manifest.package.providers == nil else {
            throw ModuleError.invalidManifestConfig(manifest.name, "providers should only be used with a System Module Package")
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
                throw ModuleError.invalidLayout(.unexpectedSourceFiles(invalidRootFiles.map{ $0.asString }))
            }
        }
        
        // Locate any directories that might be the roots of modules inside the source directory.
        let potentialModulePaths = try directoryContents(srcDir).filter(shouldConsiderDirectory)
        
        // If atleast one module in the source directory, make sure there are no loose source files in the sources directory.
        if let firstPath = potentialModulePaths.first, firstPath != srcDir {
            let invalidModuleFiles = try directoryContents(srcDir).filter(isValidSource)
            guard invalidModuleFiles.isEmpty else {
                throw ModuleError.invalidLayout(.unexpectedSourceFiles(invalidModuleFiles.map{ $0.asString }))
            }
        }
        
        // With preliminary checks done, we can start creating modules.
        let potentialModules: [PotentialModule]
        if potentialModulePaths.isEmpty {
            // There are no directories that look like modules, so try to create a module for the source directory itself (with the name coming from the name in the manifest).
            potentialModules = [PotentialModule(name: manifest.name, path: srcDir, isTest: false)]
        } else {
            potentialModules = potentialModulePaths.map { PotentialModule(name: $0.basename, path: $0, isTest: false) }
        }
        return try createModules(potentialModules + potentialTestModules())
    }

    // Create modules from the provided potential modules.
    private func createModules(_ potentialModules: [PotentialModule]) throws -> [Module] {
        // Find if manifest references a module which isn't present on disk.
        let allReferencedModules = manifest.allReferencedModules()
        let potentialModulesName = Set(potentialModules.map{$0.name})
        let missingModules = allReferencedModules.subtracting(potentialModulesName).intersection(allReferencedModules)
        guard missingModules.isEmpty else {
            throw ModuleError.modulesNotFound(missingModules.map{$0})
        }

        let targetMap = Dictionary(items: manifest.package.targets.map { ($0.name, $0) })
        let potentialModuleMap = Dictionary(items: potentialModules.map { ($0.name, $0) })
        let successors: (PotentialModule) -> [PotentialModule] = {
            // No reference of this module in manifest, i.e. it has no dependencies.
            guard let target = targetMap[$0.name] else { return [] }
            return target.dependencies.map {
                switch $0 {
                case .Target(let name):
                    return potentialModuleMap[name]!
                }
            }
        }
        // Look for any cycle in the dependencies.
        if let cycle = findCycle(potentialModules.sorted{ $0.name < $1.name }, successors: successors) {
            throw ModuleError.cycleDetected((cycle.path.map{$0.name}, cycle.cycle.map{$0.name}))
        }
        // There was no cycle so we sort the modules topologically.
        let potentialModules = try! topologicalSort(potentialModules, successors: successors)

        // The created modules mapped to their name.
        var modules = [String: Module]()
        // If a direcotry is empty, we don't create a module object for them.
        var emptyModules = Set<String>()

        // Start iterating the potential modules.
        for potentialModule in potentialModules.lazy.reversed() {
            // Validate the module name.  This function will throw an error if it detects a problem.
            try validateModuleName(potentialModule.path, potentialModule.name, isTest: potentialModule.isTest)
            // Get the intra-package dependencies of this module.
            var deps: [Module] = targetMap[potentialModule.name].map {
                $0.dependencies.flatMap {
                    switch $0 {
                    case .Target(let name):
                        // If this is a module with no sources, we don't have a module object.
                        if emptyModules.contains(name) { return nil }
                        return modules[name]!
                    }
                }
            } ?? []
            // For test modules, add dependencies to its base module, if it has no explicit dependency.
            if potentialModule.isTest && deps.isEmpty {
                if let baseModule = modules[potentialModule.basename] {
                    deps.append(baseModule)
                }
            }
            // Create the module.
            let module = try createModule(potentialModule: potentialModule, moduleDependencies: deps)
            // Add the created module to the map or print no sources warning.
            if let createdModule = module {
                modules[createdModule.name] = createdModule
            } else {
                emptyModules.insert(potentialModule.name)
                warningStream <<< "warning: module '\(potentialModule.name)' does not contain any sources.\n"
                warningStream.flush()
            }
        }
        return modules.values.map{$0}
    }

    /// Private function that checks whether a module name is valid.  This method doesn't return anything, but rather, if there's a problem, it throws an error describing what the problem is.
    // FIXME: We will eventually be loosening this restriction to allow test-only libraries etc
    private func validateModuleName(_ path: AbsolutePath, _ name: String, isTest: Bool) throws {
        if name.isEmpty {
            throw Module.Error.invalidName(path: path.relative(to: packagePath).asString, name: name, problem: .emptyName)
        }
        if name.hasSuffix(Module.testModuleNameSuffix) && !isTest {
            throw Module.Error.invalidName(path: path.relative(to: packagePath).asString, name: name, problem: .hasTestSuffix)
        }
        if !name.hasSuffix(Module.testModuleNameSuffix) && isTest {
            throw Module.Error.invalidName(path: path.relative(to: packagePath).asString, name: name, problem: .noTestSuffix)
        }
    }
    
    /// Private function that constructs a single Module object for the potential module.
    private func createModule(potentialModule: PotentialModule, moduleDependencies: [Module]) throws -> Module? {
        
        // Find all the files under the module path.
        let walked = try walk(potentialModule.path, fileSystem: fileSystem, recursing: shouldConsiderDirectory).map{ $0 }
        // Make sure there is no modulemap mixed with the sources.
        if let path = walked.first(where: { $0.basename == "module.modulemap"}) {
            throw ModuleError.invalidLayout(.modulemapInSources(path.asString))
        }
        // Select any source files for the C-based languages and for Swift.
        let sources = walked.filter(isValidSource)
        let cSources = sources.filter{ SupportedLanguageExtension.cFamilyExtensions.contains($0.extension!) }
        let swiftSources = sources.filter{ SupportedLanguageExtension.swiftExtensions.contains($0.extension!) }
        assert(sources.count == cSources.count + swiftSources.count)
        
        // Create and return the right kind of module depending on what kind of sources we found.
        if cSources.isEmpty {
            guard !swiftSources.isEmpty else { return nil }
            // No C sources, so we expect to have Swift sources, and we create a Swift module.
            return SwiftModule(
                name: potentialModule.name,
                isTest: potentialModule.isTest,
                sources: Sources(paths: swiftSources, root: potentialModule.path),
                dependencies: moduleDependencies)
        } else {
            // No Swift sources, so we expect to have C sources, and we create a C module.
            guard swiftSources.isEmpty else { throw Module.Error.mixedSources(potentialModule.path.asString) }
            return ClangModule(
                name: potentialModule.name,
                isTest: potentialModule.isTest,
                sources: Sources(paths: cSources, root: potentialModule.path),
                dependencies: moduleDependencies)
        }
    }

    /// Scans tests directory and returns potential modules from it.
    private func potentialTestModules() throws -> [PotentialModule] {
        let testsPath = packagePath.appending(component: "Tests")
        
        // Don't try to walk Tests if it is in excludes or doesn't exists.
        guard fileSystem.isDirectory(testsPath) && !excludedPaths.contains(testsPath) else {
            return []
        }

        // Get the contents of the Tests directory.
        let testsDirContents = try directoryContents(testsPath)
        
        // Check that the Tests directory doesn't contain any loose source files.
        // FIXME: Right now we just check for source files.  We need to decide whether we should check for other kinds of files too.
        // FIXME: We should factor out the checking for the `LinuxMain.swift` source file.  So ugly...
        let looseSourceFiles = testsDirContents.filter(isValidSource).filter({ $0.basename.lowercased() != "linuxmain.swift" })
        guard looseSourceFiles.isEmpty else {
            throw ModuleError.invalidLayout(.unexpectedSourceFiles(looseSourceFiles.map{ $0.asString }))
        }
        
        return testsDirContents.filter(shouldConsiderDirectory).map{ PotentialModule(name: $0.basename, path: $0, isTest: true) }
    }

    /// Collects the products defined by a package.
    private func constructProducts(_ modules: [Module]) throws -> [Product] {
        var products = [Product]()

        // Collect all test modules.
        let testModules = modules.filter{ module in
            guard module.type == .test else { return false }
          #if os(Linux)
            // FIXME: Ignore C language test modules on linux for now.
            if module is ClangModule {
                warningStream <<< "warning: Ignoring \(module.name) as C language in tests is not yet supported on Linux."
                warningStream.flush()
                return false
            }
          #endif
            return true
        }

        // Create a test product if we have any test module.
        if !testModules.isEmpty {
            // Add suffix 'PackageTests' to test product so the module name of linux executable don't collide with
            // main package, if present.
            let product = Product(name: manifest.name + "PackageTests", type: .test, modules: testModules)
            products.append(product)
        }

        // Map containing modules mapped to their names.
        let modulesMap = Dictionary(items: modules.map{ ($0.name, $0) })

        /// Helper method to get modules from target names.
        func modulesFrom(targetNames names: [String], product: String) throws -> [Module] {
            // Ensure the target names are non-empty.
            guard !names.isEmpty else { throw Product.Error.noModules(product) }
            // Get modules from target names.
            let productModules: [Module] = try names.map { target in
                // Ensure we have this target.
                guard let module = modulesMap[target] else {
                    throw Product.Error.moduleNotFound(product: product, module: target)
                }
                return module
            }
            return productModules
        }

        // Create legacy products if any.
        for p in manifest.legacyProducts {
            let modules = try modulesFrom(targetNames: p.modules, product: p.name)
            let product = Product(name: p.name, type: .init(p.type), modules: modules)
            products.append(product)
        }

        // Create executables.
        func createExecutables() {
            for module in modules where module.type == .executable {
                let product = Product(name: module.name, type: .executable, modules: [module])
                products.append(product)
            }
        }

        // Create a product for the entire package.
        switch manifest.package {
        case .v3:
            // Always create all executables in v3.
            createExecutables()

            if createImplicitProduct {
                let libraryModules = modules.filter{ $0.type == .library }
                if !libraryModules.isEmpty {
                    products += [Product(name: manifest.name, type: .library(.automatic), modules: libraryModules)]
                }
            }

        case .v4(let package):

            // Only create implicit executables for root packages in v4.
            if !createImplicitProduct {
                createExecutables()
            }

            for product in package.products {
                switch product {
                case .exe(let p):
                    // FIXME: We should handle/diagnose name collisions between local and vended executables (SR-3562).
                    let modules = try modulesFrom(targetNames: p.targets, product: p.name)
                    products.append(Product(name: p.name, type: .executable, modules: modules))
                case .lib(let p):
                    // Get the library type.
                    let type: PackageModel.ProductType
                    switch p.type {
                    case .static?: type = .library(.static)
                    case .dynamic?: type = .library(.dynamic)
                    case nil: type = .library(.automatic)
                    }
                    let modules = try modulesFrom(targetNames: p.targets, product: p.name)
                    products.append(Product(name: p.name, type: type, modules: modules))
                }
            }
        }

        return products
    }

}

/// We create this structure after scanning the filesystem for potential modules.
private struct PotentialModule: Hashable {

    /// Name of the module.
    let name: String

    /// The path of the module.
    let path: AbsolutePath

    /// If this should be a test module.
    let isTest: Bool

    /// The base prefix for the test module, used to associate with the target it tests.
    public var basename: String {
        guard isTest else {
            fatalError("\(type(of: self)) should be a test module to access basename.")
        }
        precondition(name.hasSuffix(Module.testModuleNameSuffix))
        return name[name.startIndex..<name.index(name.endIndex, offsetBy: -Module.testModuleNameSuffix.characters.count)]
    }

    var hashValue: Int {
        return name.hashValue ^ path.hashValue ^ isTest.hashValue
    }

    static func ==(lhs: PotentialModule, rhs: PotentialModule) -> Bool {
        return lhs.name == rhs.name &&
               lhs.path == rhs.path &&
               lhs.isTest == rhs.isTest
    }
}

private extension Manifest {
    /// Returns the names of all the referenced modules in the manifest.
    func allReferencedModules() -> Set<String> {
        let names = package.targets.flatMap { target in
            [target.name] + target.dependencies.map {
                switch $0 {
                case .Target(let name):
                    return name
                }
            }
        }
        return Set(names)
    }
}

private extension PackageModel.ProductType {

    /// Create instance from package description's product type.
    init(_ type: PackageDescription.ProductType) {
        switch type {
        case .Test:
            self = .test
        case .Executable:
            self = .executable
        case .Library(.Static):
            self = .library(.static)
        case .Library(.Dynamic):
            self = .library(.dynamic)
        }
    }
}
