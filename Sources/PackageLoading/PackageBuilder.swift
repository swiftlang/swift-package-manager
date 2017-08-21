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

    /// Describes a way in which a package layout is invalid.
    public enum InvalidLayoutType {
        case multipleSourceRoots([String])
        case unexpectedSourceFiles([String])
        case modulemapInSources(String)
    }

    /// Indicates two targets with the same name.
    case duplicateModule(String)

    /// One or more referenced targets could not be found.
    case modulesNotFound([String])

    /// Package layout is invalid.
    case invalidLayout(InvalidLayoutType)

    /// The manifest has invalid configuration wrt type of the target.
    case invalidManifestConfig(String, String)

    /// The target dependency declaration has cycle in it.
    case cycleDetected((path: [String], cycle: [String]))

    /// The public headers directory is at an invalid path.
    case invalidPublicHeadersDirectory(String)

    /// The sources of a target are overlapping with another target.
    case overlappingSources(target: String, sources: [AbsolutePath])

    /// We found multiple LinuxMain.swift files.
    case multipleLinuxMainFound(package: String, linuxMainFiles: [AbsolutePath])

    /// The package should support version 3 compiler but doesn't.
    case mustSupportSwift3Compiler(package: String)

    /// The tools version in use is not compatible with target's sources.
    case incompatibleToolsVersions(package: String, required: [Int], current: Int)

    /// The target path is outside the package.
    case targetOutsidePackage(package: String, target: String)
}

extension ModuleError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .duplicateModule(let name):
            return "multiple targets named '\(name)'"
        case .modulesNotFound(let targets):
            let targets = targets.joined(separator: ", ")
            return "could not find target(s): \(targets); use the 'path' property in the Swift 4 manifest to set a custom target path"
        case .invalidLayout(let type):
            return "package has unsupported layout; \(type)"
        case .invalidManifestConfig(let package, let message):
            return "configuration of package '\(package)' is invalid; \(message)"
        case .cycleDetected(let cycle):
            return "cyclic dependency declaration found: " +
                (cycle.path + cycle.cycle).joined(separator: " -> ") +
                " -> " + cycle.cycle[0]
        case .invalidPublicHeadersDirectory(let name):
            return "public headers directory path for '\(name)' is invalid or not contained in the target"
        case .overlappingSources(let target, let sources):
            return "target '\(target)' has sources overlapping sources: \(sources.map({$0.asString}).joined(separator: ", "))"
        case .multipleLinuxMainFound(let package, let linuxMainFiles):
            let files = linuxMainFiles.map({ $0.asString }).sorted().joined(separator: ", ")
            return "package '\(package)' has multiple linux main files: \(files)"
        case .mustSupportSwift3Compiler(let package):
            return "package '\(package)' must support Swift 3 because its minimum tools version is 3"
        case .incompatibleToolsVersions(let package, let required, let current):
            if required.isEmpty {
                return "package '\(package)' supported Swift language versions is empty"
            }
            let required = required.map(String.init).joined(separator: ", ")
            return "package '\(package)' not compatible with current tools version (\(current)); it supports: \(required)"
        case .targetOutsidePackage(let package, let target):
            return "target '\(target)' in package '\(package)' is outside the package root"
        }
    }
}

extension ModuleError.InvalidLayoutType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .multipleSourceRoots(let paths):
            return "multiple source roots found: " + paths.sorted().joined(separator: ", ")
        case .unexpectedSourceFiles(let paths):
            return "found loose source files: " + paths.sorted().joined(separator: ", ")
        case .modulemapInSources(let path):
            return "modulemap '\(path)' should be inside the 'include' directory"
        }
    }
}

extension Target {

    /// An error in the organization or configuration of an individual target.
    enum Error: Swift.Error {

        /// The target's name is invalid.
        case invalidName(path: String, problem: ModuleNameProblem)
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

        /// The manifest contains duplicate targets.
        case duplicateTargets([String])
    }
}

extension Target.Error: CustomStringConvertible {
    var description: String {
        switch self {
        case .invalidName(let path, let problem):
            return "invalid target name at '\(path)'; \(problem)"
        case .mixedSources(let path):
            return "target at '\(path)' contains mixed language source files; feature not supported"
        case .duplicateTargets(let targets):
            return "duplicate targets found: " + targets.joined(separator: ", ")
        }
    }
}

extension Target.Error.ModuleNameProblem: CustomStringConvertible {
    var description: String {
        switch self {
          case .emptyName:
            return "target names can not be empty"
          case .noTestSuffix:
            return "name of test targets must end in 'Tests'"
          case .hasTestSuffix:
            return "name of non-test targets cannot end in 'Tests'"
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

extension Product.Error: CustomStringConvertible {
    var description: String {
        switch self {
        case .noModules(let product):
            return "product '\(product)' doesn't reference any targets"
        case .moduleNotFound(let product, let target):
            return "target '\(target)' referenced in product '\(product)' could not be found"
        }
    }
}

/// Helper for constructing a package following the convention system.
///
/// The 'builder' here refers to the builder pattern and not any build system
/// related function.
public final class PackageBuilder {
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
        // Find the special directory for targets.
        let targetSpecialDirs = findTargetSpecialDirs(targets)

        return Package(
            manifest: manifest,
            path: packagePath,
            targets: targets,
            products: products,
            targetSearchPath: packagePath.appending(component: targetSpecialDirs.targetDir),
            testTargetSearchPath: packagePath.appending(component: targetSpecialDirs.testTargetDir)
        )
    }

    /// Computes the special directory where targets are present or should be placed in future.
    private func findTargetSpecialDirs(_ targets: [Target]) -> (targetDir: String, testTargetDir: String) {
        let predefinedDirs = findPredefinedTargetDirectory()

        // Select the preferred tests directory.
        var testTargetDir = PackageBuilder.predefinedTestDirectories[0]

        // If found predefined test directory is not same as preferred test directory,
        // check if any of the test target is actually inside the predefined test directory.
        if predefinedDirs.testTargetDir != testTargetDir {
            let expectedTestsDir = packagePath.appending(component: predefinedDirs.testTargetDir)
            for target in targets where target.type == .test {
                // If yes, use the predefined test directory as preferred test directory.
                if expectedTestsDir == target.sources.root.parentDirectory {
                    testTargetDir = predefinedDirs.testTargetDir
                    break
                }
            }
        }

        return (predefinedDirs.targetDir, testTargetDir)
    }

    // MARK: Utility Predicates

    private func isValidSource(_ path: AbsolutePath) -> Bool {
        // Ignore files which don't match the expected extensions.
        guard let ext = path.extension, SupportedLanguageExtension.validExtensions.contains(ext) else {
            return false
        }

        let basename = path.basename

        // Ignore dotfiles.
        if basename.hasPrefix(".") { return false }

        // Ignore linux main.
        if basename == SwiftTarget.linuxMainBasename { return false }

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

        // Ensure no dupicate target definitions are found.
        let duplicateTargetNames: [String] = manifest.package.targets.map({ $0.name
        }).findDuplicates()
        
        if !duplicateTargetNames.isEmpty {
            throw Target.Error.duplicateTargets(duplicateTargetNames)
        }

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
                manifest.name, "the 'pkgConfig' property can only be used with a System Module Package")
        }

        guard manifest.package.providers == nil else {
            throw ModuleError.invalidManifestConfig(
                manifest.name, "the 'providers' property can only be used with a System Module Package")
        }

        // Depending on the manifest version, use the correct convention system.
        if isVersion3Manifest {
            return try constructV3Targets()
        }
        return try constructV4Targets()
    }

    /// Predefined source directories, in order of preference.
    static let predefinedSourceDirectories = ["Sources", "Source", "src", "srcs"]

    /// Predefined test directories, in order of preference.
    static let predefinedTestDirectories = ["Tests", "Sources", "Source", "src", "srcs"]

    /// Finds the predefined directories for regular and test targets.
    private func findPredefinedTargetDirectory() -> (targetDir: String, testTargetDir: String) {
        let targetDir = PackageBuilder.predefinedSourceDirectories.first(where: {
            fileSystem.isDirectory(packagePath.appending(component: $0))
        }) ?? PackageBuilder.predefinedSourceDirectories[0]

        let testTargetDir = PackageBuilder.predefinedTestDirectories.first(where: {
            fileSystem.isDirectory(packagePath.appending(component: $0))
        }) ?? PackageBuilder.predefinedTestDirectories[0]

        return (targetDir, testTargetDir)
    }

    /// Construct targets according to PackageDescription 4 conventions.
    fileprivate func constructV4Targets() throws -> [Target] {
        // Select the correct predefined directory list.
        let predefinedDirs = findPredefinedTargetDirectory()

        /// Returns the path of the given target.
        func findPath(for target: PackageDescription4.Target) throws -> AbsolutePath {
            // If there is a custom path defined, use that.
            if let subpath = target.path {
                if subpath == "" || subpath == "." {
                    return packagePath
                }
                let path = packagePath.appending(RelativePath(subpath))
                // Make sure the target is inside the package root.
                guard path.contains(packagePath) else {
                    throw ModuleError.targetOutsidePackage(package: manifest.name, target: target.name)
                }
                if fileSystem.isDirectory(path) {
                    return path
                }
                throw ModuleError.modulesNotFound([target.name])
            }

            // Check if target is present in the predefined directory.
            let predefinedDir = target.isTest ? predefinedDirs.testTargetDir : predefinedDirs.targetDir
            let path = packagePath.appending(components: predefinedDir, target.name)
            if fileSystem.isDirectory(path) {
                return path
            }
            throw ModuleError.modulesNotFound([target.name])
        }

        // Create potential targets.
        let potentialTargets: [PotentialModule]
        potentialTargets = try manifest.package.targets.map({ target in
            let path = try findPath(for: target)
            return PotentialModule(name: target.name, path: path, isTest: target.isTest)
        })
        return try createModules(potentialTargets)
    }

    /// Construct targets according to PackageDescription 3 conventions.
    fileprivate func constructV3Targets() throws -> [Target] {

        // If the package lists swift language versions, ensure that it declares
        // that its sources are compatible with Swift 3 compiler since this
        // manifest is allowed to be picked by Swift 3 tools during resolution.
        if let swiftLanguageVersions = manifest.package.swiftLanguageVersions {
            guard swiftLanguageVersions.contains(ManifestVersion.three.rawValue) else {
                throw ModuleError.mustSupportSwift3Compiler(package: manifest.name)
            }
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

            // Get the target from the manifest.
            let manifestTarget = targetMap[potentialModule.name]

            // Figure out the product dependencies.
            let productDeps: [(String, String?)]
            productDeps = manifestTarget?.dependencies.flatMap({
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
                potentialModule: potentialModule,
                manifestTarget: manifestTarget,
                moduleDependencies: deps, 
                productDeps: productDeps)
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
                problem: .emptyName)
        }
        // We only need to do the below checks for PackageDescription 3.
        if !isVersion3Manifest { return }

        if name.hasSuffix(Target.testModuleNameSuffix) && !isTest {
            throw Target.Error.invalidName(
                path: path.relative(to: packagePath).asString,
                problem: .hasTestSuffix)
        }

        if !name.hasSuffix(Target.testModuleNameSuffix) && isTest {
            throw Target.Error.invalidName(
                path: path.relative(to: packagePath).asString,
                problem: .noTestSuffix)
        }
    }

    /// Private function that constructs a single Target object for the potential target.
    private func createTarget(
        potentialModule: PotentialModule,
        manifestTarget: PackageDescription4.Target?,
        moduleDependencies: [Target],
        productDeps: [(name: String, package: String?)]
    ) throws -> Target? {

        // Compute the path to public headers directory.
        let publicHeaderComponent = manifestTarget?.publicHeadersPath ?? ClangTarget.defaultPublicHeadersComponent
        let publicHeadersPath = potentialModule.path.appending(RelativePath(publicHeaderComponent))
        guard publicHeadersPath.contains(potentialModule.path) else {
            throw ModuleError.invalidPublicHeadersDirectory(potentialModule.name)
        }

        // Compute the excluded paths in the target.
        let targetExcludedPaths: Set<AbsolutePath>
        if let excludedSubPaths = manifestTarget?.exclude {
            let excludedPaths = excludedSubPaths.map({ potentialModule.path.appending(RelativePath($0)) })
            targetExcludedPaths = Set(excludedPaths)
        } else {
            targetExcludedPaths = []
        }

        // Contains the set of sources for this target.
        var walked = Set<AbsolutePath>()

        // Contains the paths we need to recursively iterate.
        var pathsToWalk = [AbsolutePath]()

        // If there are sources defined in the target use that.
        if let definedSources = manifestTarget?.sources {
            for definedSource in definedSources {
                let definedSourcePath = potentialModule.path.appending(RelativePath(definedSource))
                if fileSystem.isDirectory(definedSourcePath) {
                    // If this is a directory, add it to the list of paths to walk.
                    pathsToWalk.append(definedSourcePath)
                } else if fileSystem.isFile(definedSourcePath) {
                    // Otherwise, this is a sourcefile.
                    walked.insert(definedSourcePath)
                } else {
                    // FIXME: Should we emit warning about this declared thing or silently ignore?
                }
            }
        } else {
            // Use the top level target path as the path to be walked.
            pathsToWalk.append(potentialModule.path)
        }

        // Walk each path and form our set of possible source files.
        for pathToWalk in pathsToWalk {
            let contents = try walk(pathToWalk, fileSystem: fileSystem, recursing: { path in
                // Exclude the public header directory.
                if path == publicHeadersPath { return false }

                // Exclude if it in the excluded paths of the target.
                if targetExcludedPaths.contains(path) { return false }

                // Exclude if it in the excluded paths.
                if self.excludedPaths.contains(path) { return false }

                // Exclude the directories that should never be walked.
                let base = path.basename
                if base.hasSuffix(".xcodeproj") || base.hasSuffix(".playground") || base.hasPrefix(".") {
                    return false
                }

                // We have to support these checks for PackageDescription 3.
                if self.isVersion3Manifest {
                    if base.lowercased() == "tests" { return false }
                    if path == self.packagesDirectory { return false }
                }

                return true
            }).map({$0})
            walked.formUnion(contents)
        }

        // Make sure there is no modulemap mixed with the sources.
        if let path = walked.first(where: { $0.basename == moduleMapFilename }) {
            throw ModuleError.invalidLayout(.modulemapInSources(path.asString))
        }
        // Select any source files for the C-based languages and for Swift.
        let sources = walked.filter(isValidSource).filter({ !targetExcludedPaths.contains($0) })
        let cSources = sources.filter({ SupportedLanguageExtension.cFamilyExtensions.contains($0.extension!) })
        let swiftSources = sources.filter({ SupportedLanguageExtension.swiftExtensions.contains($0.extension!) })
        assert(sources.count == cSources.count + swiftSources.count)

        // Create and return the right kind of target depending on what kind of sources we found.
        if cSources.isEmpty {
            guard !swiftSources.isEmpty else { return nil }
            let swiftSources = Array(swiftSources)
            try validateSourcesOverlapping(forTarget: potentialModule.name, sources: swiftSources)
            // No C sources, so we expect to have Swift sources, and we create a Swift target.
            return SwiftTarget(
                name: potentialModule.name,
                isTest: potentialModule.isTest,
                sources: Sources(paths: swiftSources, root: potentialModule.path),
                dependencies: moduleDependencies,
                productDependencies: productDeps,
                swiftVersion: try swiftVersion())
        } else {
            // No Swift sources, so we expect to have C sources, and we create a C target.
            guard swiftSources.isEmpty else { throw Target.Error.mixedSources(potentialModule.path.asString) }
            let cSources = Array(cSources)
            try validateSourcesOverlapping(forTarget: potentialModule.name, sources: cSources)

            let sources = Sources(paths: cSources, root: potentialModule.path)

            // Select the right language standard.
            let isCXX = sources.containsCXXFiles
            let languageStandard = isCXX ? manifest.package.cxxLanguageStandard?.rawValue : manifest.package.cLanguageStandard?.rawValue 

            return ClangTarget(
                name: potentialModule.name,
                isCXX: isCXX,
                languageStandard: languageStandard,
                includeDir: publicHeadersPath,
                isTest: potentialModule.isTest,
                sources: sources,
                dependencies: moduleDependencies,
                productDependencies: productDeps)
        }
    }

    /// Computes the swift version to use for this manifest.
    private func swiftVersion() throws -> Int {
        if let swiftVersion = _swiftVersion {
            return swiftVersion
        }
        let computedSwiftVersion: Int
        // Figure out the swift version from declared list in the manifest.
        if let swiftLanguageVersions = manifest.package.swiftLanguageVersions {
            let majorToolsVersion = ToolsVersion.currentToolsVersion.major
            guard let swiftVersion = swiftLanguageVersions.sorted(by: >).first(where: { $0 <= majorToolsVersion }) else {
                throw ModuleError.incompatibleToolsVersions(
                    package: manifest.name, required: swiftLanguageVersions, current: majorToolsVersion)
            }
            computedSwiftVersion = swiftVersion
        } else if isVersion3Manifest {
            // Otherwise, use the version depending on the manifest version.
            // FIXME: This feels weird, we should store the reference of the tools
            // version inside the manifest so we can return the major version directly.
            computedSwiftVersion = ManifestVersion.three.rawValue
        } else {
            computedSwiftVersion = ManifestVersion.four.rawValue
        }
        _swiftVersion = computedSwiftVersion 
        return computedSwiftVersion
    }
    private var _swiftVersion: Int? = nil

    /// The set of the sources computed so far.
    private var allSources = Set<AbsolutePath>()

    /// Validates that the sources of a target are not already present in another target.
    private func validateSourcesOverlapping(forTarget target: String, sources: [AbsolutePath]) throws {
        // Compute the sources which overlap with already computed targets.
        var overlappingSources = [AbsolutePath]()
        for source in sources {
            if !allSources.insert(source).inserted {
                overlappingSources.append(source)
            }
        }

        // Throw if we found any overlapping sources.
        if !overlappingSources.isEmpty {
            throw ModuleError.overlappingSources(target: target, sources: overlappingSources)
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
        let looseSourceFiles = testsDirContents.filter(isValidSource)
        guard looseSourceFiles.isEmpty else {
            throw ModuleError.invalidLayout(.unexpectedSourceFiles(looseSourceFiles.map({ $0.asString })))
        }

        return testsDirContents
            .filter(shouldConsiderDirectory)
            .map({ PotentialModule(name: $0.basename, path: $0, isTest: true) })
    }

    /// Find the linux main file for the package.
    private func findLinuxMain(in testTargets: [Target]) throws -> AbsolutePath? {
        var linuxMainFiles = Set<AbsolutePath>()
        var pathsSearched = Set<AbsolutePath>()

        // Look for linux main file adjacent to each test target root, iterating upto package root.
        for target in testTargets {
            var searchPath = target.sources.root.parentDirectory
            while true {
                // If we have already searched this path, skip.
                if !pathsSearched.contains(searchPath) {
                    let linuxMain = searchPath.appending(component: SwiftTarget.linuxMainBasename)
                    if fileSystem.isFile(linuxMain) {
                        linuxMainFiles.insert(linuxMain)
                    }
                    pathsSearched.insert(searchPath)
                }
                // Break if we reached all the way to package root.
                if searchPath == packagePath { break }
                // Go one level up.
                searchPath = searchPath.parentDirectory
            }
        }

        // It is an error if there are multiple linux main files.
        if linuxMainFiles.count > 1 {
            throw ModuleError.multipleLinuxMainFound(
                package: manifest.name, linuxMainFiles: linuxMainFiles.map({ $0 }))
        }
        return linuxMainFiles.first
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
            // Otherwise we only need to create one test product for all of the
            // test targets.
            //
            // Add suffix 'PackageTests' to test product name so the target name
            // of linux executable don't collide with main package, if present.
            let productName = manifest.name + "PackageTests"
            let linuxMain = try findLinuxMain(in: testModules)

            let product = Product(
                name: productName, type: .test, targets: testModules, linuxMain: linuxMain)
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

        // Auto creates executable products from executables targets if that
        // target isn't already present in the declaredProductsTargets set.
        func createExecutables(declaredProductsTargets: Set<String> = []) {
            for target in targets where target.type == .executable {
                // If this target already has an executable product, skip
                // generating a product for it.
                if declaredProductsTargets.contains(target.name) {
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
                // Compute the list of targets which are being used in an
                // executable product so we don't create implicit executables
                // for them.
                let executableProductTargets = package.products.flatMap({ product -> [String] in
                    switch product {
                    case let product as PackageDescription4.Product.Executable:
                        return product.targets
                    case is PackageDescription4.Product.Library:
                        return []
                    default:
                        fatalError("Unreachable")
                    }
                })
                createExecutables(declaredProductsTargets: Set(executableProductTargets))
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
        let endIndex = name.index(name.endIndex, offsetBy: -Target.testModuleNameSuffix.count)
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
