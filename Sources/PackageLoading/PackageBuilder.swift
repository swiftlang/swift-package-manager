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
import class PackageDescription4.Product
import class PackageDescription4.Target

fileprivate typealias Product = PackageModel.Product
fileprivate typealias Target = PackageModel.Target

/// An error in the structure or layout of a package.
public enum ModuleError: Swift.Error {

    /// Indicates two targets with the same name.
    case duplicateModule(String)

    /// One or more referenced targets could not be found.
    case modulesNotFound([String])

    /// Package layout is invalid.
    case invalidLayout(InvalidLayoutType)

        /// Describes a way in which a package layout is invalid.
        public enum InvalidLayoutType {
            case multipleSourceRoots([String])
            case unexpectedSourceFiles([String])
            case modulemapInSources(String)
        }

    /// The manifest has invalid configuration wrt type of the target.
    case invalidManifestConfig(String, String)

    /// The target dependency declaration has cycle in it.
    case cycleDetected((path: [String], cycle: [String]))
}

extension ModuleError: FixableError {
    public var error: String {
        switch self {
        case .duplicateModule(let name):
            return "multiple targets with the name \(name) found"
        case .modulesNotFound(let targets):
            return "these referenced targets could not be found: " + targets.joined(separator: ", ")
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
        case .duplicateModule:
            return "targets should have a unique name across dependencies"
        case .modulesNotFound:
            return "reference only valid targets"
        case .invalidLayout(let type):
            return type.fix
        case .invalidManifestConfig:
            return nil
        case .cycleDetected:
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
            return "move the file(s) inside a target"
        case .modulemapInSources(_):
            return "move the modulemap inside include directory"
        }
    }
}

extension Target {

    /// An error in the organization or configuration of an individual target.
    enum Error: Swift.Error {

        /// The target's name is invalid.
        case invalidName(path: String, name: String, problem: ModuleNameProblem)
        enum ModuleNameProblem {
            /// Empty target name.
            case emptyName
            /// Test target doesn't have a "Tests" suffix.
            case noTestSuffix
            /// Non-test target does have a "Tests" suffix.
            case hasTestSuffix
        }

        /// The target contains an invalid mix of languages (e.g. both Swift and C).
        case mixedSources(String)
    }
}

extension Target.Error: FixableError {
    var error: String {
        switch self {
          case .invalidName(let path, let name, let problem):
            return "the directory \(path) has an invalid name ('\(name)'): \(problem.error)"
          case .mixedSources(let path):
            return "the target at \(path) contains mixed language source files"
        }
    }

    var fix: String? {
        switch self {
        case .invalidName(let path, _, let problem):
            return "rename the directory '\(path)'\(problem.fix ?? "")"
        case .mixedSources(_):
            return "use only a single language within a target"
        }
    }
}

extension Target.Error.ModuleNameProblem : FixableError {
    var error: String {
        switch self {
          case .emptyName:
            return "the target name is empty"
          case .noTestSuffix:
            return "the name of a test target has no 'Tests' suffix"
          case .hasTestSuffix:
            return "the name of a non-test target has a 'Tests' suffix"
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
        case moduleNotFound(product: String, target: String)
    }
}

extension Product.Error: FixableError {
    var error: String {
        switch self {
        case .noModules(let product):
            return "the product named \(product) doesn't reference any targets"
        case .moduleNotFound(let product, let target):
            return "the product named \(product) references a target that could not be found: \(target)"
        }
    }

    var fix: String? {
        switch self {
        case .noModules(_):
            return "reference one or more targets from the product"
        case .moduleNotFound(_):
            return "reference only valid targets from the product"
        }
    }
}

/// Helper for constructing a package following the convention system.
///
/// The 'builder' here refers to the builder pattern and not any build system
/// related function.
public struct PackageBuilder {
    /// The manifest for the package being constructed.
    private let manifest: Manifest

    /// The path of the package.
    private let packagePath: AbsolutePath

    /// The filesystem package builder will run on.
    private let fileSystem: FileSystem

    /// The diagnostics engine.
    private let diagnostics: DiagnosticsEngine

    /// True if this is the root package.
    private let isRootPackage: Bool

    /// Create multiple test products.
    ///
    /// If set to true, one test product will be created for each test target.
    private let shouldCreateMultipleTestProducts: Bool

    /// Returns true if the loaded manifest version is v3.
    private var isVersion3Manifest: Bool {
        switch manifest.package {
        case .v3: return true
        case .v4: return false
        }
    }

    /// Create a builder for the given manifest and package `path`.
    ///
    /// - Parameters:
    ///   - manifest: The manifest of this package.
    ///   - path: The root path of the package.
    ///   - fileSystem: The file system on which the builder should be run.
    ///   - diagnostics: The diagnostics engine.
    ///   - isRootPackage: If this is a root package.
    ///   - createMultipleTestProducts: If enabled, create one test product for
    ///     each test target.
    public init(
        manifest: Manifest,
        path: AbsolutePath,
        fileSystem: FileSystem = localFileSystem,
        diagnostics: DiagnosticsEngine,
        isRootPackage: Bool,
        shouldCreateMultipleTestProducts: Bool = false
    ) {
        self.isRootPackage = isRootPackage
        self.manifest = manifest
        self.packagePath = path
        self.fileSystem = fileSystem
        self.diagnostics = diagnostics
        self.shouldCreateMultipleTestProducts = shouldCreateMultipleTestProducts
    }

    /// Build a new package following the conventions.
    public func construct() throws -> Package {
        let targets = try constructTargets()
        let products = try constructProducts(targets)
        return Package(
            manifest: manifest,
            path: packagePath,
            targets: targets,
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
        return manifest.package.exclude.map({ packagePath.appending(RelativePath($0)) })
    }

    /// Returns path to all the items in a directory.
    /// FIXME: This is generic functionality, and should move to FileSystem.
    func directoryContents(_ path: AbsolutePath) throws -> [AbsolutePath] {
        return try fileSystem.getDirectoryContents(path).map({ path.appending(component: $0) })
    }

    /// Returns the path of the source directory, throwing an error in case of an invalid layout (such as the presence
    /// of both `Sources` and `src` directories).
    func sourceRoot() throws -> AbsolutePath {
        let viableRoots = try fileSystem.getDirectoryContents(packagePath).filter({ basename in
            let entry = packagePath.appending(component: basename)
            if PackageBuilder.isSourceDirectory(pathComponent: basename) {
                return fileSystem.isDirectory(entry) && !excludedPaths.contains(entry)
            }
            return false
        })

        switch viableRoots.count {
        case 0:
            return packagePath
        case 1:
            return packagePath.appending(component: viableRoots[0])
        default:
            // eg. there is a `Sources' AND a `src'
            throw ModuleError.invalidLayout(.multipleSourceRoots(
                viableRoots.map({ packagePath.appending(component: $0).asString })))
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

    /// Private function that creates and returns a list of targets defined by a package.
    private func constructTargets() throws -> [Target] {

        // Check for a modulemap file, which indicates a system target.
        let moduleMapPath = packagePath.appending(component: moduleMapFilename)
        if fileSystem.isFile(moduleMapPath) {
            // Package contains a modulemap at the top level, so we assuming it's a system target.
            return [
                CTarget(
                    name: manifest.name,
                    path: packagePath,
                    pkgConfig: manifest.package.pkgConfig,
                    providers: manifest.package.providers)
            ]
        }

        // At this point the target can't be a system target, make sure manifest doesn't contain
        // system target specific configuration.
        guard manifest.package.pkgConfig == nil else {
            throw ModuleError.invalidManifestConfig(
                manifest.name, "pkgConfig should only be used with a System Module Package")
        }

        guard manifest.package.providers == nil else {
            throw ModuleError.invalidManifestConfig(
                manifest.name, "providers should only be used with a System Module Package")
        }

        // Depending on the manifest version, use the correct convention system.
        if isVersion3Manifest {
            return try constructV3Targets()
        }
        return try constructV4Targets()
    }

    /// Predefined source directories.
    private let predefinedSourceDirectories = ["Sources", "Source", "src", "srcs"]

    /// Predefined test directories.
    private let predefinedTestDirectories = ["Tests", "Sources", "Source", "src", "srcs"]

    /// Construct targets according to PackageDescription 4 conventions.
    fileprivate func constructV4Targets() throws -> [Target] {
        /// Returns the path of the given target.
        func findPath(for target: PackageDescription4.Target) throws -> AbsolutePath {
            let predefinedDirectories = predefinedSourceDirectories
            for directory in predefinedDirectories {
                let path = packagePath.appending(components: directory, target.name)
                if fileSystem.isDirectory(path) {
                    return path
                }
            }
            throw ModuleError.modulesNotFound([target.name])
        }

        // Create potential targets.
        let potentialTargets: [PotentialModule]
        potentialTargets = try manifest.package.targets.map({ target in
            let path = try findPath(for: target)
            return PotentialModule(name: target.name, path: path, isTest: false)
        })
        return try createModules(potentialTargets)
    }

    /// Construct targets according to PackageDescription 3 conventions.
    fileprivate func constructV3Targets() throws -> [Target] {

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
                throw ModuleError.invalidLayout(.unexpectedSourceFiles(invalidRootFiles.map({ $0.asString })))
            }
        }

        // Locate any directories that might be the roots of targets inside the source directory.
        let potentialModulePaths = try directoryContents(srcDir).filter(shouldConsiderDirectory)

        // If atleast one target in the source directory, make sure there are no loose source files in the sources
        // directory.
        if let firstPath = potentialModulePaths.first, firstPath != srcDir {
            let invalidModuleFiles = try directoryContents(srcDir).filter(isValidSource)
            guard invalidModuleFiles.isEmpty else {
                throw ModuleError.invalidLayout(.unexpectedSourceFiles(invalidModuleFiles.map({ $0.asString })))
            }
        }

        // With preliminary checks done, we can start creating targets.
        let potentialModules: [PotentialModule]
        if potentialModulePaths.isEmpty {
            // There are no directories that look like targets, so try to create a target for the source directory
            // itself (with the name coming from the name in the manifest).
            potentialModules = [PotentialModule(name: manifest.name, path: srcDir, isTest: false)]
        } else {
            potentialModules = potentialModulePaths.map({ PotentialModule(name: $0.basename, path: $0, isTest: false) })
        }
        return try createModules(potentialModules + potentialTestModules())
    }

    // Create targets from the provided potential targets.
    private func createModules(_ potentialModules: [PotentialModule]) throws -> [Target] {
        // Find if manifest references a target which isn't present on disk.
        let allReferencedModules = manifest.allReferencedModules()
        let potentialModulesName = Set(potentialModules.map({ $0.name }))
        let missingModules = allReferencedModules.subtracting(potentialModulesName).intersection(allReferencedModules)
        guard missingModules.isEmpty else {
            throw ModuleError.modulesNotFound(missingModules.map({ $0 }))
        }

        let targetItems = manifest.package.targets.map({ ($0.name, $0 as PackageDescription4.Target) })
        let targetMap = Dictionary(items: targetItems)
        let potentialModuleMap = Dictionary(items: potentialModules.map({ ($0.name, $0) }))
        let successors: (PotentialModule) -> [PotentialModule] = {
            // No reference of this target in manifest, i.e. it has no dependencies.
            guard let target = targetMap[$0.name] else { return [] }
            return target.dependencies.flatMap({
                switch $0 {
                case .targetItem(let name):
                    // Since we already checked above that all referenced targets
                    // has to present, we always expect this target to be present in 
                    // potentialModules dictionary.
                    return potentialModuleMap[name]!
                case .productItem:
                    return nil
                case .byNameItem(let name):
                    // By name dependency may or may not be a target dependency.
                    return potentialModuleMap[name]
                }
            })
        }
        // Look for any cycle in the dependencies.
        if let cycle = findCycle(potentialModules.sorted(by: { $0.name < $1.name }), successors: successors) {
            throw ModuleError.cycleDetected((cycle.path.map({ $0.name }), cycle.cycle.map({ $0.name })))
        }
        // There was no cycle so we sort the targets topologically.
        let potentialModules = try! topologicalSort(potentialModules, successors: successors)

        // The created targets mapped to their name.
        var targets = [String: Target]()
        // If a direcotry is empty, we don't create a target object for them.
        var emptyModules = Set<String>()

        // Start iterating the potential targets.
        for potentialModule in potentialModules.lazy.reversed() {
            // Validate the target name.  This function will throw an error if it detects a problem.
            try validateModuleName(potentialModule.path, potentialModule.name, isTest: potentialModule.isTest)
            // Get the intra-package dependencies of this target.
            var deps: [Target] = targetMap[potentialModule.name].map({
                $0.dependencies.flatMap({
                    switch $0 {
                    case .targetItem(let name):
                        // We don't create an object for targets which have no sources.
                        if emptyModules.contains(name) { return nil }
                        return targets[name]!

                    case .byNameItem(let name):
                        // We don't create an object for targets which have no sources.
                        if emptyModules.contains(name) { return nil }
                        return targets[name]

                    case .productItem: return nil
                    }
                })
            }) ?? []

            // For test targets, add dependencies to its base target, if it has
            // no explicit dependency. We only do this for v3 manifests to
            // maintain compatibility.
            if isVersion3Manifest && potentialModule.isTest && deps.isEmpty {
                if let baseModule = targets[potentialModule.basename] {
                    deps.append(baseModule)
                }
            }

            // Figure out the product dependencies.
            let productDeps: [(String, String?)]
            productDeps = targetMap[potentialModule.name]?.dependencies.flatMap({
                switch $0 {
                case .targetItem:
                    return nil
                case .byNameItem(let name):
                    // If this dependency was not found locally, it is a product dependency.
                    return potentialModuleMap[name] == nil ? (name, nil) : nil
                case .productItem(let name, let package):
                    return (name, package)
                }
            }) ?? []

            // Create the target.
            let target = try createTarget(
                potentialModule: potentialModule, moduleDependencies: deps, productDeps: productDeps)
            // Add the created target to the map or print no sources warning.
            if let createdTarget = target {
                targets[createdTarget.name] = createdTarget
            } else {
                emptyModules.insert(potentialModule.name)
                diagnostics.emit(data: PackageBuilderDiagnostics.NoSources(package: manifest.name, target: potentialModule.name))
            }
        }
        return targets.values.map({ $0 })
    }

    /// Private function that checks whether a target name is valid.  This method doesn't return anything, but rather,
    /// if there's a problem, it throws an error describing what the problem is.
    private func validateModuleName(_ path: AbsolutePath, _ name: String, isTest: Bool) throws {
        if name.isEmpty {
            throw Target.Error.invalidName(
                path: path.relative(to: packagePath).asString,
                name: name,
                problem: .emptyName)
        }

        if name.hasSuffix(Target.testModuleNameSuffix) && !isTest {
            throw Target.Error.invalidName(
                path: path.relative(to: packagePath).asString,
                name: name,
                problem: .hasTestSuffix)
        }

        if !name.hasSuffix(Target.testModuleNameSuffix) && isTest {
            throw Target.Error.invalidName(
                path: path.relative(to: packagePath).asString,
                name: name,
                problem: .noTestSuffix)
        }
    }

    /// Private function that constructs a single Target object for the potential target.
    private func createTarget(
        potentialModule: PotentialModule,
        moduleDependencies: [Target],
        productDeps: [(name: String, package: String?)]
    ) throws -> Target? {

        // Find all the files under the target path.
        let walked = try walk(
            potentialModule.path,
            fileSystem: fileSystem,
            recursing: shouldConsiderDirectory).map({ $0 })
        // Make sure there is no modulemap mixed with the sources.
        if let path = walked.first(where: { $0.basename == moduleMapFilename }) {
            throw ModuleError.invalidLayout(.modulemapInSources(path.asString))
        }
        // Select any source files for the C-based languages and for Swift.
        let sources = walked.filter(isValidSource)
        let cSources = sources.filter({ SupportedLanguageExtension.cFamilyExtensions.contains($0.extension!) })
        let swiftSources = sources.filter({ SupportedLanguageExtension.swiftExtensions.contains($0.extension!) })
        assert(sources.count == cSources.count + swiftSources.count)

        // Create and return the right kind of target depending on what kind of sources we found.
        if cSources.isEmpty {
            guard !swiftSources.isEmpty else { return nil }
            // No C sources, so we expect to have Swift sources, and we create a Swift target.
            return SwiftTarget(
                name: potentialModule.name,
                isTest: potentialModule.isTest,
                sources: Sources(paths: swiftSources, root: potentialModule.path),
                dependencies: moduleDependencies,
                productDependencies: productDeps,
                swiftLanguageVersions: manifest.package.swiftLanguageVersions)
        } else {
            // No Swift sources, so we expect to have C sources, and we create a C target.
            guard swiftSources.isEmpty else { throw Target.Error.mixedSources(potentialModule.path.asString) }
            return ClangTarget(
                name: potentialModule.name,
                isTest: potentialModule.isTest,
                sources: Sources(paths: cSources, root: potentialModule.path),
                dependencies: moduleDependencies,
                productDependencies: productDeps)
        }
    }

    /// Scans tests directory and returns potential targets from it.
    private func potentialTestModules() throws -> [PotentialModule] {
        let testsPath = packagePath.appending(component: "Tests")

        // Don't try to walk Tests if it is in excludes or doesn't exists.
        guard fileSystem.isDirectory(testsPath) && !excludedPaths.contains(testsPath) else {
            return []
        }

        // Get the contents of the Tests directory.
        let testsDirContents = try directoryContents(testsPath)

        // Check that the Tests directory doesn't contain any loose source files.
        // FIXME: Right now we just check for source files.  We need to decide whether we should check for other kinds
        // of files too.
        // FIXME: We should factor out the checking for the `LinuxMain.swift` source file.  So ugly...
        let looseSourceFiles = testsDirContents
            .filter(isValidSource)
            .filter({ $0.basename.lowercased() != "linuxmain.swift" })
        guard looseSourceFiles.isEmpty else {
            throw ModuleError.invalidLayout(.unexpectedSourceFiles(looseSourceFiles.map({ $0.asString })))
        }

        return testsDirContents
            .filter(shouldConsiderDirectory)
            .map({ PotentialModule(name: $0.basename, path: $0, isTest: true) })
    }

    /// Collects the products defined by a package.
    private func constructProducts(_ targets: [Target]) throws -> [Product] {
        var products = [Product]()

        // Collect all test targets.
        let testModules = targets.filter({ target in
            guard target.type == .test else { return false }
          #if os(Linux)
            // FIXME: Ignore C language test targets on linux for now.
            if target is ClangTarget {
                diagnostics.emit(data: PackageBuilderDiagnostics.UnsupportedCTarget(
                    package: manifest.name, target: target.name))
                return false
            }
          #endif
            return true
        })

        // If enabled, create one test product for each test target.
        if shouldCreateMultipleTestProducts {
            for testTarget in testModules {
                let product = Product(name: testTarget.name, type: .test, targets: [testTarget])
                products.append(product)
            }
        } else if !testModules.isEmpty {
            // Otherwise we only need to create one test product for all of the test targets.
            //
            // Add suffix 'PackageTests' to test product so the target name of linux executable don't collide with
            // main package, if present.
            let product = Product(name: manifest.name + "PackageTests", type: .test, targets: testModules)
            products.append(product)
        }

        // Map containing targets mapped to their names.
        let modulesMap = Dictionary(items: targets.map({ ($0.name, $0) }))

        /// Helper method to get targets from target names.
        func modulesFrom(targetNames names: [String], product: String) throws -> [Target] {
            // Ensure the target names are non-empty.
            guard !names.isEmpty else { throw Product.Error.noModules(product) }
            // Get targets from target names.
            let productModules: [Target] = try names.map({ targetName in
                // Ensure we have this target.
                guard let target = modulesMap[targetName] else {
                    throw Product.Error.moduleNotFound(product: product, target: targetName)
                }
                return target
            })
            return productModules
        }

        // Create legacy products if any.
        for p in manifest.legacyProducts {
            let targets = try modulesFrom(targetNames: p.modules, product: p.name)
            let product = Product(name: p.name, type: .init(p.type), targets: targets)
            products.append(product)
        }

        // Auto creates executable products from executables targets if there
        // isn't already a product with same name.
        func createExecutables(declaredProducts: Set<String> = []) {
            for target in targets where target.type == .executable {
                // If this target already has a product, skip generating a
                // product for it.
                if declaredProducts.contains(target.name) {
                    // FIXME: We should probably check and warn in case this is
                    // not an executable product.
                    continue
                }
                let product = Product(name: target.name, type: .executable, targets: [target])
                products.append(product)
            }
        }

        // Create a product for the entire package.
        switch manifest.package {
        case .v3:
            // Always create all executables in v3.
            createExecutables()

            // Create one product containing all of the package's library targets.
            if !isRootPackage {
                let libraryModules = targets.filter({ $0.type == .library })
                if !libraryModules.isEmpty {
                    products += [Product(name: manifest.name, type: .library(.automatic), targets: libraryModules)]
                }
            }

        case .v4(let package):
            // Only create implicit executables for root packages in v4.
            if isRootPackage {
                createExecutables(declaredProducts: Set(package.products.map({ $0.name })))
            }

            for product in package.products {
                switch product {
                case let p as PackageDescription4.Product.Executable:
                    let targets = try modulesFrom(targetNames: p.targets, product: p.name)
                    products.append(Product(name: p.name, type: .executable, targets: targets))
                case let p as PackageDescription4.Product.Library:
                    // Get the library type.
                    let type: PackageModel.ProductType
                    switch p.type {
                    case .static?: type = .library(.static)
                    case .dynamic?: type = .library(.dynamic)
                    case nil: type = .library(.automatic)
                    }
                    let targets = try modulesFrom(targetNames: p.targets, product: p.name)
                    products.append(Product(name: p.name, type: type, targets: targets))
                default:
                    fatalError("Unreachable")
                }
            }
        }

        return products
    }

}

/// We create this structure after scanning the filesystem for potential targets.
private struct PotentialModule: Hashable {

    /// Name of the target.
    let name: String

    /// The path of the target.
    let path: AbsolutePath

    /// If this should be a test target.
    let isTest: Bool

    /// The base prefix for the test target, used to associate with the target it tests.
    public var basename: String {
        guard isTest else {
            fatalError("\(type(of: self)) should be a test target to access basename.")
        }
        precondition(name.hasSuffix(Target.testModuleNameSuffix))
        let endIndex = name.index(name.endIndex, offsetBy: -Target.testModuleNameSuffix.characters.count)
        return String(name[name.startIndex..<endIndex])
    }

    var hashValue: Int {
        return name.hashValue ^ path.hashValue ^ isTest.hashValue
    }

    static func == (lhs: PotentialModule, rhs: PotentialModule) -> Bool {
        return lhs.name == rhs.name &&
               lhs.path == rhs.path &&
               lhs.isTest == rhs.isTest
    }
}

private extension Manifest {
    /// Returns the names of all the referenced targets in the manifest.
    func allReferencedModules() -> Set<String> {
        let names = package.targets.flatMap({ target in
            [target.name] + target.dependencies.flatMap({
                switch $0 {
                case .targetItem(let name):
                    return name
                case .byNameItem, .productItem:
                    return nil
                }
            })
        })
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
