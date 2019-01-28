/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel
import SPMUtility

/// An error in the structure or layout of a package.
public enum ModuleError: Swift.Error {

    /// Describes a way in which a package layout is invalid.
    public enum InvalidLayoutType {
        case multipleSourceRoots([String])
        case modulemapInSources(String)
    }

    /// Indicates two targets with the same name and their corresponding packages.
    case duplicateModule(String, [String])

    /// One or more referenced targets could not be found.
    case modulesNotFound([String])

    /// Invalid custom path.
    case invalidCustomPath(target: String, path: String)

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

    /// The tools version in use is not compatible with target's sources.
    case incompatibleToolsVersions(package: String, required: [SwiftLanguageVersion], current: ToolsVersion)

    /// The target path is outside the package.
    case targetOutsidePackage(package: String, target: String)

    /// Unsupported target path
    case unsupportedTargetPath(String)

    /// Invalid header search path.
    case invalidHeaderSearchPath(String)
}

extension ModuleError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .duplicateModule(let name, let packages):
            let packages = packages.joined(separator: ", ")
            return "multiple targets named '\(name)' in: \(packages)"
        case .modulesNotFound(let targets):
            let targets = targets.joined(separator: ", ")
            return "could not find source files for target(s): \(targets); use the 'path' property in the Swift 4 manifest to set a custom target path"
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
            return "target '\(target)' has sources overlapping sources: " +
                sources.map({ $0.pathString }).joined(separator: ", ")
        case .multipleLinuxMainFound(let package, let linuxMainFiles):
            return "package '\(package)' has multiple linux main files: " +
                linuxMainFiles.map({ $0.pathString }).sorted().joined(separator: ", ")
        case .incompatibleToolsVersions(let package, let required, let current):
            if required.isEmpty {
                return "package '\(package)' supported Swift language versions is empty"
            }
            return "package '\(package)' requires minimum Swift language version \(required[0]) which is not supported by the current tools version (\(current))"
        case .targetOutsidePackage(let package, let target):
            return "target '\(target)' in package '\(package)' is outside the package root"
        case .unsupportedTargetPath(let targetPath):
            return "target path '\(targetPath)' is not supported; it should be relative to package root"
        case .invalidCustomPath(let target, let path):
            return "invalid custom path '\(path)' for target '\(target)'"
        case .invalidHeaderSearchPath(let path):
            return "invalid header search path '\(path)'; header search path should not be outside the package root"
        }
    }
}

extension ModuleError.InvalidLayoutType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .multipleSourceRoots(let paths):
            return "multiple source roots found: " + paths.sorted().joined(separator: ", ")
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

    /// Create the special REPL product for this package.
    private let createREPLProduct: Bool

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
        shouldCreateMultipleTestProducts: Bool = false,
        createREPLProduct: Bool = false
    ) {
        self.isRootPackage = isRootPackage
        self.manifest = manifest
        self.packagePath = path
        self.fileSystem = fileSystem
        self.diagnostics = diagnostics
        self.shouldCreateMultipleTestProducts = shouldCreateMultipleTestProducts
        self.createREPLProduct = createREPLProduct
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

    private func diagnosticLocation() -> DiagnosticLocation {
        return PackageLocation.Local(name: manifest.name, packagePath: packagePath)
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
        guard let ext = path.extension, SupportedLanguageExtension.validExtensions(manifestVersion: self.manifest.manifestVersion).contains(ext) else {
            return false
        }

        let basename = path.basename

        // Ignore dotfiles.
        if basename.hasPrefix(".") { return false }

        // Ignore linux main.
        if basename == SwiftTarget.linuxMainBasename { return false }

        // Ignore paths which are not valid files.
        if !fileSystem.isFile(path) {

            // Diagnose broken symlinks.
            if fileSystem.isSymlink(path) {
                diagnostics.emit(
                    data: PackageBuilderDiagnostics.BorkenSymlinkDiagnostic(path: path.pathString),
                    location: diagnosticLocation()
                )
            }

            return false
        }

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
        if path == packagesDirectory { return false }
        if !fileSystem.isDirectory(path) { return false }
        return true
    }

    private var packagesDirectory: AbsolutePath {
        return packagePath.appending(component: "Packages")
    }

    /// Returns path to all the items in a directory.
    // FIXME: This is generic functionality, and should move to FileSystem.
    func directoryContents(_ path: AbsolutePath) throws -> [AbsolutePath] {
        return try fileSystem.getDirectoryContents(path).map({ path.appending(component: $0) })
    }

    /// Private function that creates and returns a list of targets defined by a package.
    private func constructTargets() throws -> [Target] {

        // Ensure no dupicate target definitions are found.
        let duplicateTargetNames: [String] = manifest.targets.map({ $0.name
        }).spm_findDuplicates()

        if !duplicateTargetNames.isEmpty {
            throw Target.Error.duplicateTargets(duplicateTargetNames)
        }

        // Check for a modulemap file, which indicates a system target.
        let moduleMapPath = packagePath.appending(component: moduleMapFilename)
        if fileSystem.isFile(moduleMapPath) {

            // Warn about any declared targets.
            let targets = manifest.targets
            if !targets.isEmpty {
                diagnostics.emit(
                    data: PackageBuilderDiagnostics.SystemPackageDeclaresTargetsDiagnostic(targets: targets.map({ $0.name })),
                    location: diagnosticLocation()
                )
            }

            // Emit deprecation notice.
            switch manifest.manifestVersion {
            case .v4: break
            case .v4_2, .v5:
                diagnostics.emit(
                    data: PackageBuilderDiagnostics.SystemPackageDeprecatedDiagnostic(),
                    location: diagnosticLocation()
                )
            }

            // Package contains a modulemap at the top level, so we assuming
            // it's a system library target.
            return [
                SystemLibraryTarget(
                    name: manifest.name,
                    platforms: self.platforms(),
                    path: packagePath, isImplicit: true,
                    pkgConfig: manifest.pkgConfig,
                    providers: manifest.providers)
            ]
        }

        // At this point the target can't be a system target, make sure manifest doesn't contain
        // system target specific configuration.
        guard manifest.pkgConfig == nil else {
            throw ModuleError.invalidManifestConfig(
                manifest.name, "the 'pkgConfig' property can only be used with a System Module Package")
        }

        guard manifest.providers == nil else {
            throw ModuleError.invalidManifestConfig(
                manifest.name, "the 'providers' property can only be used with a System Module Package")
        }

        return try constructV4Targets()
    }

    /// Predefined source directories, in order of preference.
    public static let predefinedSourceDirectories = ["Sources", "Source", "src", "srcs"]

    /// Predefined test directories, in order of preference.
    public static let predefinedTestDirectories = ["Tests", "Sources", "Source", "src", "srcs"]

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
        func findPath(for target: TargetDescription) throws -> AbsolutePath {
            // If there is a custom path defined, use that.
            if let subpath = target.path {
                if subpath == "" || subpath == "." {
                    return packagePath
                }

                // Make sure target is not refenced by absolute path
                guard let relativeSubPath = try? RelativePath(validating: subpath) else {
                    throw ModuleError.unsupportedTargetPath(subpath)
                }

                let path = packagePath.appending(relativeSubPath)
                // Make sure the target is inside the package root.
                guard path.contains(packagePath) else {
                    throw ModuleError.targetOutsidePackage(package: manifest.name, target: target.name)
                }
                if fileSystem.isDirectory(path) {
                    return path
                }
                throw ModuleError.invalidCustomPath(target: target.name, path: subpath)
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
        potentialTargets = try manifest.targets.map({ target in
            let path = try findPath(for: target)
            return PotentialModule(name: target.name, path: path, type: target.type)
        })
        return try createModules(potentialTargets)
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

        let targetItems = manifest.targets.map({ ($0.name, $0 as TargetDescription) })
        let targetMap = Dictionary(items: targetItems)
        let potentialModuleMap = Dictionary(items: potentialModules.map({ ($0.name, $0) }))
        let successors: (PotentialModule) -> [PotentialModule] = {
            // No reference of this target in manifest, i.e. it has no dependencies.
            guard let target = targetMap[$0.name] else { return [] }
            return target.dependencies.compactMap({
                switch $0 {
                case .target(let name):
                    // Since we already checked above that all referenced targets
                    // has to present, we always expect this target to be present in
                    // potentialModules dictionary.
                    return potentialModuleMap[name]!
                case .product:
                    return nil
                case .byName(let name):
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
            let deps: [Target] = targetMap[potentialModule.name].map({
                $0.dependencies.compactMap({
                    switch $0 {
                    case .target(let name):
                        // We don't create an object for targets which have no sources.
                        if emptyModules.contains(name) { return nil }
                        return targets[name]!

                    case .byName(let name):
                        // We don't create an object for targets which have no sources.
                        if emptyModules.contains(name) { return nil }
                        return targets[name]

                    case .product: return nil
                    }
                })
            }) ?? []

            // Get the target from the manifest.
            let manifestTarget = targetMap[potentialModule.name]

            // Figure out the product dependencies.
            let productDeps: [(String, String?)]
            productDeps = manifestTarget?.dependencies.compactMap({
                switch $0 {
                case .target:
                    return nil
                case .byName(let name):
                    // If this dependency was not found locally, it is a product dependency.
                    return potentialModuleMap[name] == nil ? (name, nil) : nil
                case .product(let name, let package):
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
                path: path.relative(to: packagePath).pathString,
                problem: .emptyName)
        }
    }

    /// Private function that constructs a single Target object for the potential target.
    private func createTarget(
        potentialModule: PotentialModule,
        manifestTarget: TargetDescription?,
        moduleDependencies: [Target],
        productDeps: [(name: String, package: String?)]
    ) throws -> Target? {

        // Create system library target.
        if potentialModule.type == .system {
            let moduleMapPath = potentialModule.path.appending(component: moduleMapFilename)
            guard fileSystem.isFile(moduleMapPath) else {
                return nil
            }

            return SystemLibraryTarget(
                name: potentialModule.name,
                platforms: self.platforms(),
                path: potentialModule.path, isImplicit: false,
                pkgConfig: manifestTarget?.pkgConfig,
                providers: manifestTarget?.providers
            )
        }

        // Check for duplicate target dependencies by name
        let combinedDependencyNames = moduleDependencies.map { $0.name } + productDeps.map { $0.0 }
        combinedDependencyNames.spm_findDuplicates().forEach {
            diagnostics.emit(data: PackageBuilderDiagnostics.DuplicateTargetDependencyDiagnostic(dependency: $0, target: potentialModule.name))
        }

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

                // Exclude the directories that should never be walked.
                let base = path.basename
                if base.hasSuffix(".xcodeproj") || base.hasSuffix(".playground") || base.hasPrefix(".") {
                    return false
                }

                return true
            }).map({$0})
            walked.formUnion(contents)
        }

        // Make sure there is no modulemap mixed with the sources.
        if let path = walked.first(where: { $0.basename == moduleMapFilename }) {
            throw ModuleError.invalidLayout(.modulemapInSources(path.pathString))
        }
        // Select any source files for the C-based languages and for Swift.
        let sources = walked.filter(isValidSource).filter({ !targetExcludedPaths.contains($0) })
        let clangSources = sources.filter({ SupportedLanguageExtension.clangTargetExtensions(manifestVersion: self.manifest.manifestVersion).contains($0.extension!)})
        let swiftSources = sources.filter({ SupportedLanguageExtension.swiftExtensions.contains($0.extension!) })
        assert(sources.count == clangSources.count + swiftSources.count)

        // Create the build setting assignment table for this target.
        let buildSettings = try self.buildSettings(for: manifestTarget, targetRoot: potentialModule.path)

        // Create and return the right kind of target depending on what kind of sources we found.
        if clangSources.isEmpty {
            guard !swiftSources.isEmpty else { return nil }
            let swiftSources = Array(swiftSources)
            try validateSourcesOverlapping(forTarget: potentialModule.name, sources: swiftSources)
            // No C sources, so we expect to have Swift sources, and we create a Swift target.
            return SwiftTarget(
                name: potentialModule.name,
                platforms: self.platforms(),
                isTest: potentialModule.isTest,
                sources: Sources(paths: swiftSources, root: potentialModule.path),
                dependencies: moduleDependencies,
                productDependencies: productDeps,
                swiftVersion: try swiftVersion(),
                buildSettings: buildSettings
            )
        } else {
            // No Swift sources, so we expect to have C sources, and we create a C target.
            guard swiftSources.isEmpty else { throw Target.Error.mixedSources(potentialModule.path.pathString) }
            let cSources = Array(clangSources)
            try validateSourcesOverlapping(forTarget: potentialModule.name, sources: cSources)

            let sources = Sources(paths: cSources, root: potentialModule.path)

            return ClangTarget(
                name: potentialModule.name,
                platforms: self.platforms(),
                cLanguageStandard: manifest.cLanguageStandard,
                cxxLanguageStandard: manifest.cxxLanguageStandard,
                includeDir: publicHeadersPath,
                isTest: potentialModule.isTest,
                sources: sources,
                dependencies: moduleDependencies,
                productDependencies: productDeps,
                buildSettings: buildSettings
            )
        }
    }

    /// Creates build setting assignment table for the given target.
    func buildSettings(for target: TargetDescription?, targetRoot: AbsolutePath) throws -> BuildSettings.AssignmentTable {
        var table = BuildSettings.AssignmentTable()
        guard let target = target else { return table }

        // Process each setting.
        for setting in target.settings {
            let decl: BuildSettings.Declaration

            // Compute appropriate declaration for the setting.
            switch setting.name {
            case .headerSearchPath:

                switch setting.tool {
                case .c, .cxx:
                    decl = .HEADER_SEARCH_PATHS
                case .swift, .linker:
                    fatalError("unexpected tool for setting type \(setting)")
                }

                // Ensure that the search path is contained within the package.
                let subpath = try RelativePath(validating: setting.value[0])
                guard targetRoot.appending(subpath).contains(packagePath) else {
                    throw ModuleError.invalidHeaderSearchPath(subpath.pathString)
                }

            case .define:
                switch setting.tool {
                case .c, .cxx:
                    decl = .GCC_PREPROCESSOR_DEFINITIONS
                case .swift:
                    decl = .SWIFT_ACTIVE_COMPILATION_CONDITIONS
                case .linker:
                    fatalError("unexpected tool for setting type \(setting)")
                }

            case .linkedLibrary:
                switch setting.tool {
                case .c, .cxx, .swift:
                    fatalError("unexpected tool for setting type \(setting)")
                case .linker:
                    decl = .LINK_LIBRARIES
                }

            case .linkedFramework:
                switch setting.tool {
                case .c, .cxx, .swift:
                    fatalError("unexpected tool for setting type \(setting)")
                case .linker:
                    decl = .LINK_FRAMEWORKS
                }

            case .unsafeFlags:
                switch setting.tool {
                case .c:
                    decl = .OTHER_CFLAGS
                case .cxx:
                    decl = .OTHER_CPLUSPLUSFLAGS
                case .swift:
                    decl = .OTHER_SWIFT_FLAGS
                case .linker:
                    decl = .OTHER_LDFLAGS
                }
            }

            // Create an assignment for this setting.
            var assignment = BuildSettings.Assignment()
            assignment.value = setting.value

            if let config = setting.condition?.config.map({ BuildConfiguration(rawValue: $0)! }) {
                let condition = BuildSettings.ConfigurationCondition(config)
                assignment.conditions.append(condition)
            }

            if let platforms = setting.condition?.platformNames.map({ platformRegistry.platformByName[$0]! }), !platforms.isEmpty {
                var condition = BuildSettings.PlatformsCondition()
                condition.platforms = platforms
                assignment.conditions.append(condition)
            }

            // Finally, add the assignment to the assignment table.
            table.add(assignment, for: decl)
        }

        return table
    }

    /// Returns the list of platforms supported by the manifest.
    func platforms() -> [SupportedPlatform] {
        if let platforms = _platforms {
            return platforms
        }

        var supportedPlatforms: [SupportedPlatform] = []

        /// Add each declared platform to the supported platforms list.
        for platform in manifest.platforms {

            let supportedPlatform = SupportedPlatform(
                platform: platformRegistry.platformByName[platform.platformName]!,
                version: PlatformVersion(platform.version)
            )

            supportedPlatforms.append(supportedPlatform)
        }

        // Find the undeclared platforms.
        let remainingPlatforms = Set(platformRegistry.platformByName.keys).subtracting(supportedPlatforms.map({ $0.platform.name }))

        /// Start synthesizing for each undeclared platform.
        for platformName in remainingPlatforms {
            let platform = platformRegistry.platformByName[platformName]!

            let supportedPlatform = SupportedPlatform(
                platform: platform,
                version: platform.oldestSupportedVersion
            )

            supportedPlatforms.append(supportedPlatform)
        }

        _platforms = supportedPlatforms
        return _platforms!
    }
    private var _platforms: [SupportedPlatform]? = nil

    /// The platform registry instance.
    private var platformRegistry: PlatformRegistry {
        return PlatformRegistry.default
    }

    /// Computes the swift version to use for this manifest.
    private func swiftVersion() throws -> SwiftLanguageVersion {
        if let swiftVersion = _swiftVersion {
            return swiftVersion
        }

        let computedSwiftVersion: SwiftLanguageVersion

        // Figure out the swift version from declared list in the manifest.
        if let swiftLanguageVersions = manifest.swiftLanguageVersions {
            guard let swiftVersion = swiftLanguageVersions.sorted(by: >).first(where: { $0 <= ToolsVersion.currentToolsVersion }) else {
                throw ModuleError.incompatibleToolsVersions(
                    package: manifest.name, required: swiftLanguageVersions, current: .currentToolsVersion)
            }
            computedSwiftVersion = swiftVersion
        } else {
            // Otherwise, use the version depending on the manifest version.
            computedSwiftVersion = manifest.manifestVersion.swiftLanguageVersion
        }
        _swiftVersion = computedSwiftVersion
        return computedSwiftVersion
    }
    private var _swiftVersion: SwiftLanguageVersion? = nil

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

    /// Find the linux main file for the package.
    private func findLinuxMain(in testTargets: [Target]) throws -> AbsolutePath? {
        var linuxMainFiles = Set<AbsolutePath>()
        var pathsSearched = Set<AbsolutePath>()

        // Look for linux main file adjacent to each test target root, iterating upto package root.
        for target in testTargets {

            // Form the initial search path.
            //
            // If the target root's parent directory is inside the package, start
            // search there. Otherwise, we start search from the target root.
            var searchPath = target.sources.root.parentDirectory
            if !searchPath.contains(packagePath) {
                searchPath = target.sources.root
            }

            while true {
                assert(searchPath.contains(packagePath), "search path \(searchPath) is outside the package \(packagePath)")
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
        var products = OrderedSet<KeyedPair<Product, String>>()

        /// Helper method to append to products array.
        func append(_ product: Product) {
            let inserted = products.append(KeyedPair(product, key: product.name))
            if !inserted {
                diagnostics.emit(
                    data: PackageBuilderDiagnostics.DuplicateProduct(product: product),
                    location: diagnosticLocation()
                )
            }
        }

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
                append(product)
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
            append(product)
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

        // Only create implicit executables for root packages.
        if isRootPackage {
            // Compute the list of targets which are being used in an
            // executable product so we don't create implicit executables
            // for them.
            let executableProductTargets = manifest.products.flatMap({ product -> [String] in
                switch product.type {
                case .library, .test:
                    return []
                case .executable:
                    return product.targets
                }
            })

            let declaredProductsTargets = Set(executableProductTargets)
            for target in targets where target.type == .executable {
                // If this target already has an executable product, skip
                // generating a product for it.
                if declaredProductsTargets.contains(target.name) {
                    continue
                }
                let product = Product(name: target.name, type: .executable, targets: [target])
                append(product)
            }
        }

        for product in manifest.products {
            let targets = try modulesFrom(targetNames: product.targets, product: product.name)
            // Peform special validations if this product is exporting
            // a system library target.
            if targets.contains(where: { $0 is SystemLibraryTarget }) {
                if product.type != .library(.automatic) || targets.count != 1 {
                    diagnostics.emit(
                        data: PackageBuilderDiagnostics.SystemPackageProductValidationDiagnostic(product: product.name),
                        location: diagnosticLocation()
                    )
                    continue
                }
            }

            // Do some validation for executable products.
            switch product.type {
            case .library, .test:
                break
            case .executable:
                let executableTargets = targets.filter({ $0.type == .executable })
                if executableTargets.count != 1 {
                    diagnostics.emit(
                        data: PackageBuilderDiagnostics.InvalidExecutableProductDecl(product: product.name),
                        location: diagnosticLocation()
                    )
                    continue
                }
            }

            append(Product(name: product.name, type: product.type, targets: targets))
        }

        // Create a special REPL product that contains all the library targets.
        if createREPLProduct {
            let libraryTargets = targets.filter({ $0.type == .library })
            if libraryTargets.isEmpty {
                diagnostics.emit(
                    data: PackageBuilderDiagnostics.ZeroLibraryProducts(),
                    location: diagnosticLocation()
                )
            } else {
                let replProduct = Product(
                    name: manifest.name + Product.replProductSuffix,
                    type: .library(.dynamic),
                    targets: libraryTargets
                )
                append(replProduct)
            }
        }

        return products.map({ $0.item })
    }

}

/// We create this structure after scanning the filesystem for potential targets.
private struct PotentialModule: Hashable {

    /// Name of the target.
    let name: String

    /// The path of the target.
    let path: AbsolutePath

    /// If this should be a test target.
    var isTest: Bool {
        return type == .test
    }

    /// The target type.
    let type: TargetDescription.TargetType

    /// The base prefix for the test target, used to associate with the target it tests.
    public var basename: String {
        guard isTest else {
            fatalError("\(Swift.type(of: self)) should be a test target to access basename.")
        }
        precondition(name.hasSuffix(Target.testModuleNameSuffix))
        let endIndex = name.index(name.endIndex, offsetBy: -Target.testModuleNameSuffix.count)
        return String(name[name.startIndex..<endIndex])
    }
}

private extension Manifest {
    /// Returns the names of all the referenced targets in the manifest.
    func allReferencedModules() -> Set<String> {
        let names = targets.flatMap({ target in
            [target.name] + target.dependencies.compactMap({
                switch $0 {
                case .target(let name):
                    return name
                case .byName, .product:
                    return nil
                }
            })
        })
        return Set(names)
    }
}
