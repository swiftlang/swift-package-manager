//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Dispatch
import OrderedCollections
import PackageModel

import func TSCBasic.findCycle
import struct TSCBasic.KeyedPair
import func TSCBasic.topologicalSort

/// An error in the structure or layout of a package.
public enum ModuleError: Swift.Error {
    /// Describes a way in which a package layout is invalid.
    public enum InvalidLayoutType {
        case multipleSourceRoots([AbsolutePath])
        case modulemapInSources(AbsolutePath)
        case modulemapMissing(AbsolutePath)
    }

    /// Indicates two targets with the same name and their corresponding packages.
    case duplicateModule(moduleName: String, packages: [PackageIdentity])

    /// The referenced target could not be found.
    case moduleNotFound(String, TargetDescription.TargetKind, shouldSuggestRelaxedSourceDir: Bool)

    /// The artifact for the binary target could not be found.
    case artifactNotFound(moduleName: String, expectedArtifactName: String)

    /// Invalid module alias.
    case invalidModuleAlias(originalName: String, newName: String)

    /// Invalid custom path.
    case invalidCustomPath(moduleName: String, path: String)

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

    /// We found multiple test entry point files.
    case multipleTestEntryPointFilesFound(package: String, files: [AbsolutePath])

    /// The tools version in use is not compatible with target's sources.
    case incompatibleToolsVersions(package: String, required: [SwiftLanguageVersion], current: ToolsVersion)

    /// The target path is outside the package.
    case targetOutsidePackage(package: String, target: String)

    /// Unsupported target path
    case unsupportedTargetPath(String)

    /// Invalid header search path.
    case invalidHeaderSearchPath(String)

    /// Default localization not set in the presence of localized resources.
    case defaultLocalizationNotSet

    /// A plugin target didn't declare a capability.
    case pluginCapabilityNotDeclared(target: String)

    /// A C target has declared an embedded resource
    case embedInCodeNotSupported(target: String)

    /// Indicates several targets with the same name exist in packages
    case duplicateModules(package: PackageIdentity, otherPackage: PackageIdentity, modules: [String])

    /// Indicates several targets with the same name exist in a registry and scm package
    case duplicateModulesScmAndRegistry(
        registryPackage: PackageIdentity.RegistryIdentity,
        scmPackage: PackageIdentity,
        modules: [String]
    )

    /// Indicates that an invalid trait was enabled.
    case invalidTrait(
        package: PackageIdentity,
        trait: String
    )
}

extension ModuleError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .duplicateModule(let target, let packages):
            let packages = packages.map(\.description).sorted().joined(separator: "', '")
            return "multiple packages ('\(packages)') declare targets with a conflicting name: '\(target)’; target names need to be unique across the package graph"
        case .moduleNotFound(let target, let type, let shouldSuggestRelaxedSourceDir):
            let folderName = (type == .test) ? "Tests" : (type == .plugin) ? "Plugins" : "Sources"
            var clauses = ["Source files for target \(target) should be located under '\(folderName)/\(target)'"]
            if shouldSuggestRelaxedSourceDir {
                clauses.append("'\(folderName)'")
            }
            clauses.append("or a custom sources path can be set with the 'path' property in Package.swift")
            return clauses.joined(separator: ", ")
        case .artifactNotFound(let targetName, let expectedArtifactName):
            return "binary target '\(targetName)' could not be mapped to an artifact with expected name '\(expectedArtifactName)'"
        case .invalidModuleAlias(let originalName, let newName):
            return "empty or invalid module alias; ['\(originalName)': '\(newName)']"
        case .invalidLayout(let type):
            return "package has unsupported layout; \(type)"
        case .invalidManifestConfig(let package, let message):
            return "configuration of package '\(package)' is invalid; \(message)"
        case .cycleDetected(let cycle):
            return "cyclic dependency declaration found: " +
                (cycle.path + cycle.cycle).joined(separator: " -> ") +
                " -> " + cycle.cycle[0]
        case .invalidPublicHeadersDirectory(let name):
            return "public headers (\"include\") directory path for '\(name)' is invalid or not contained in the target"
        case .overlappingSources(let target, let sources):
            return "target '\(target)' has overlapping sources: " +
                sources.map(\.description).joined(separator: ", ")
        case .multipleTestEntryPointFilesFound(let package, let files):
            return "package '\(package)' has multiple test entry point files: " +
                files.map(\.description).sorted().joined(separator: ", ")
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
        case .defaultLocalizationNotSet:
            return "manifest property 'defaultLocalization' not set; it is required in the presence of localized resources"
        case .pluginCapabilityNotDeclared(let target):
            return "plugin target '\(target)' doesn't have a 'capability' property"
        case .embedInCodeNotSupported(let target):
            return "embedding resources in code not supported for C-family language target \(target)"
        case .duplicateModules(let package, let otherPackage, let targets):
            var targetsDescription = "'\(targets.sorted().prefix(3).joined(separator: "', '"))'"
            if targets.count > 3 {
                targetsDescription += " and \(targets.count - 3) others"
            }
            return """
            multiple similar targets \(targetsDescription) appear in package '\(package)' and '\(otherPackage)', \
            this may indicate that the two packages are the same and can be de-duplicated by using mirrors. \
            if they are not duplicate consider using the `moduleAliases` parameter in manifest to provide unique names
            """
        case .duplicateModulesScmAndRegistry(let registryPackage, let scmPackage, let targets):
            var targetsDescription = "'\(targets.sorted().prefix(3).joined(separator: "', '"))'"
            if targets.count > 3 {
                targetsDescription += " and \(targets.count - 3) others"
            }
            return """
            multiple similar targets \(targetsDescription) appear in registry package '\(
                registryPackage
            )' and source control package '\(scmPackage)', \
            this may indicate that the two packages are the same and can be de-duplicated \
            by activating the automatic source-control to registry replacement, or by using mirrors. \
            if they are not duplicate consider using the `moduleAliases` parameter in manifest to provide unique names
            """
        case .invalidTrait(let package, let trait):
            return """
            Trait '"\(trait)"' is not declared by package '\(package)'.
            """
        }
    }
}

extension ModuleError.InvalidLayoutType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .multipleSourceRoots(let paths):
            "multiple source roots found: " + paths.map(\.description).sorted().joined(separator: ", ")
        case .modulemapInSources(let path):
            "modulemap '\(path)' should be inside the 'include' directory"
        case .modulemapMissing(let path):
            "missing system target module map at '\(path)'"
        }
    }
}

extension Module {
    /// An error in the organization or configuration of an individual target.
    enum Error: Swift.Error {
        /// The target's name is invalid.
        case invalidName(path: RelativePath, problem: ModuleNameProblem)
        enum ModuleNameProblem {
            /// Empty target name.
            case emptyName
        }

        /// The target contains an invalid mix of languages (e.g. both Swift and C).
        case mixedSources(AbsolutePath)
    }
}

extension Module.Error: CustomStringConvertible {
    var description: String {
        switch self {
        case .invalidName(let path, let problem):
            "invalid target name at '\(path)'; \(problem)"
        case .mixedSources(let path):
            "target at '\(path)' contains mixed language source files; feature not supported"
        }
    }
}

extension Module.Error.ModuleNameProblem: CustomStringConvertible {
    var description: String {
        switch self {
        case .emptyName:
            "target names can not be empty"
        }
    }
}

extension Product {
    /// An error in a product definition.
    enum Error: Swift.Error {
        case emptyName
        case moduleEmpty(product: String, target: String)
    }
}

extension Product.Error: CustomStringConvertible {
    var description: String {
        switch self {
        case .emptyName:
            "product names can not be empty"
        case .moduleEmpty(let product, let target):
            "target '\(target)' referenced in product '\(product)' is empty"
        }
    }
}

/// A structure representing the remote artifact information necessary to construct the package.
public struct BinaryArtifact {
    /// The kind of the artifact.
    public let kind: BinaryModule.Kind

    /// The URL the artifact was downloaded from.
    public let originURL: String?

    /// The path to the  artifact.
    public let path: AbsolutePath

    public init(kind: BinaryModule.Kind, originURL: String?, path: AbsolutePath) {
        self.kind = kind
        self.originURL = originURL
        self.path = path
    }
}

/// Helper for constructing a package following the convention system.
///
/// The 'builder' here refers to the builder pattern and not any build system
/// related function.
public final class PackageBuilder {
    /// Predefined source directories, in order of preference.
    public static let predefinedSourceDirectories = ["Sources", "Source", "src", "srcs"]
    /// Predefined test directories, in order of preference.
    public static let predefinedTestDirectories = ["Tests", "Sources", "Source", "src", "srcs"]
    /// Predefined plugin directories, in order of preference.
    public static let predefinedPluginDirectories = ["Plugins"]

    /// The identity for the package being constructed.
    private let identity: PackageIdentity

    /// The manifest for the package being constructed.
    private let manifest: Manifest

    /// The product filter to apply to the package.
    private let productFilter: ProductFilter

    /// The path of the package.
    private let packagePath: AbsolutePath

    /// Information concerning the different downloaded or local (archived) binary target artifacts.
    private let binaryArtifacts: [String: BinaryArtifact]

    /// Create multiple test products.
    ///
    /// If set to true, one test product will be created for each test target.
    private let shouldCreateMultipleTestProducts: Bool

    /// Path to test entry point file, if specified explicitly.
    private let testEntryPointPath: AbsolutePath?

    /// Temporary parameter controlling whether to warn about implicit executable targets when tools version is 5.4.
    private let warnAboutImplicitExecutableTargets: Bool

    /// Create the special REPL product for this package.
    private let createREPLProduct: Bool

    /// The additional file detection rules.
    private let additionalFileRules: [FileRuleDescription]

    /// ObservabilityScope with which to emit diagnostics
    private let observabilityScope: ObservabilityScope

    /// The filesystem package builder will run on.
    private let fileSystem: FileSystem

    private var platformRegistry: PlatformRegistry {
        PlatformRegistry.default
    }

    // The set of the sources computed so far, used to validate source overlap
    private var allSources = Set<AbsolutePath>()

    // Caches all declared versions for this package.
    private var declaredSwiftVersionsCache: [SwiftLanguageVersion]? = nil

    // Caches the version we chose to build for.
    private var swiftVersionCache: SwiftLanguageVersion? = nil

    /// The enabled traits of this package.
    private let enabledTraits: Set<String>

    /// Create a builder for the given manifest and package `path`.
    ///
    /// - Parameters:
    ///   - identity: The identity of this package.
    ///   - manifest: The manifest of this package.
    ///   - path: The root path of the package.
    ///   - artifactPaths: Paths to the downloaded binary target artifacts.
    ///   - createMultipleTestProducts: If enabled, create one test product for
    ///     each test target.
    ///   - fileSystem: The file system on which the builder should be run.///
    public init(
        identity: PackageIdentity,
        manifest: Manifest,
        productFilter: ProductFilter,
        path: AbsolutePath,
        additionalFileRules: [FileRuleDescription],
        binaryArtifacts: [String: BinaryArtifact],
        shouldCreateMultipleTestProducts: Bool = false,
        testEntryPointPath: AbsolutePath? = nil,
        warnAboutImplicitExecutableTargets: Bool = true,
        createREPLProduct: Bool = false,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        enabledTraits: Set<String>
    ) {
        self.identity = identity
        self.manifest = manifest
        self.productFilter = productFilter
        self.packagePath = path
        self.additionalFileRules = additionalFileRules
        self.binaryArtifacts = binaryArtifacts
        self.shouldCreateMultipleTestProducts = shouldCreateMultipleTestProducts
        self.testEntryPointPath = testEntryPointPath
        self.createREPLProduct = createREPLProduct
        self.warnAboutImplicitExecutableTargets = warnAboutImplicitExecutableTargets
        self.observabilityScope = observabilityScope.makeChildScope(
            description: "PackageBuilder",
            metadata: .packageMetadata(identity: self.identity, kind: self.manifest.packageKind)
        )
        self.fileSystem = fileSystem
        self.enabledTraits = enabledTraits
    }

    /// Build a new package following the conventions.
    public func construct() throws -> Package {
        let targets = try self.constructTargets()
        let products = try self.constructProducts(targets)
        // Find the special directory for targets.
        let targetSpecialDirs = self.findTargetSpecialDirs(targets)

        return Package(
            identity: self.identity,
            manifest: self.manifest,
            path: self.packagePath,
            targets: targets,
            products: products,
            targetSearchPath: self.packagePath.appending(component: targetSpecialDirs.targetDir),
            testTargetSearchPath: self.packagePath.appending(component: targetSpecialDirs.testTargetDir)
        )
    }

    /// Computes the special directory where targets are present or should be placed in future.
    private func findTargetSpecialDirs(_ targets: [Module]) -> (targetDir: String, testTargetDir: String) {
        let predefinedDirs = self.findPredefinedTargetDirectory()

        // Select the preferred tests directory.
        var testTargetDir = PackageBuilder.predefinedTestDirectories[0]

        // If found predefined test directory is not same as preferred test directory,
        // check if any of the test target is actually inside the predefined test directory.
        if predefinedDirs.testTargetDir != testTargetDir {
            let expectedTestsDir = self.packagePath.appending(component: predefinedDirs.testTargetDir)
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
        guard let ext = path.extension,
              SupportedLanguageExtension.validExtensions(toolsVersion: self.manifest.toolsVersion).contains(ext)
        else {
            return false
        }

        let basename = path.basename

        // Ignore dotfiles.
        if basename.hasPrefix(".") { return false }

        // Ignore test entry point files.
        if SwiftModule.testEntryPointNames.contains(basename) { return false }

        // Ignore paths which are not valid files.
        if !self.fileSystem.isFile(path) {
            // Diagnose broken symlinks.
            if self.fileSystem.isSymlink(path) {
                self.observabilityScope.emit(.brokenSymlink(path))
            }

            return false
        }

        // Ignore manifest files.
        if path.parentDirectory == self.packagePath {
            if basename == Manifest.filename { return false }

            // Ignore version-specific manifest files.
            if basename.hasPrefix(Manifest.basename + "@") && basename.hasSuffix(".swift") {
                return false
            }
        }

        // Otherwise, we have a valid source file.
        return true
    }

    /// Returns path to all the items in a directory.
    // FIXME: This is generic functionality, and should move to FileSystem.
    func directoryContents(_ path: AbsolutePath) throws -> [AbsolutePath] {
        try self.fileSystem.getDirectoryContents(path).map { path.appending(component: $0) }
    }

    /// Private function that creates and returns a list of targets defined by a package.
    private func constructTargets() throws -> [Module] {
        // Check for a modulemap file, which indicates a system target.
        let moduleMapPath = self.packagePath.appending(component: moduleMapFilename)
        if self.fileSystem.isFile(moduleMapPath) {
            // Warn about any declared targets.
            if !self.manifest.targets.isEmpty {
                self.observabilityScope.emit(
                    .systemPackageDeclaresTargets(targets: Array(self.manifest.targets.map(\.name)))
                )
            }

            // Emit deprecation notice.
            if self.manifest.toolsVersion >= .v4_2 {
                self.observabilityScope.emit(.systemPackageDeprecation)
            }

            // Package contains a modulemap at the top level, so we assuming
            // it's a system library target.
            return [
                SystemLibraryModule(
                    name: self.manifest.displayName, // FIXME: use identity instead?
                    path: self.packagePath,
                    isImplicit: true,
                    pkgConfig: self.manifest.pkgConfig,
                    providers: self.manifest.providers
                ),
            ]
        }

        // At this point the target can't be a system target, make sure manifest doesn't contain
        // system target specific configuration.
        guard self.manifest.pkgConfig == nil else {
            throw ModuleError.invalidManifestConfig(
                self.identity.description, "the 'pkgConfig' property can only be used with a System Module Package"
            )
        }

        guard self.manifest.providers == nil else {
            throw ModuleError.invalidManifestConfig(
                self.identity.description, "the 'providers' property can only be used with a System Module Package"
            )
        }

        return try self.constructV4Targets()
    }

    /// Finds the predefined directories for regular targets, test targets, and plugin targets.
    private func findPredefinedTargetDirectory()
        -> (targetDir: String, testTargetDir: String, pluginTargetDir: String)
    {
        let targetDir = PackageBuilder.predefinedSourceDirectories.first(where: {
            self.fileSystem.isDirectory(self.packagePath.appending(component: $0))
        }) ?? PackageBuilder.predefinedSourceDirectories[0]

        let testTargetDir = PackageBuilder.predefinedTestDirectories.first(where: {
            self.fileSystem.isDirectory(self.packagePath.appending(component: $0))
        }) ?? PackageBuilder.predefinedTestDirectories[0]

        let pluginTargetDir = PackageBuilder.predefinedPluginDirectories.first(where: {
            self.fileSystem.isDirectory(self.packagePath.appending(component: $0))
        }) ?? PackageBuilder.predefinedPluginDirectories[0]

        return (targetDir, testTargetDir, pluginTargetDir)
    }

    /// Construct targets according to PackageDescription 4 conventions.
    private func constructV4Targets() throws -> [Module] {
        // Select the correct predefined directory list.
        let predefinedDirs = self.findPredefinedTargetDirectory()

        let predefinedTargetDirectory = PredefinedTargetDirectory(
            fs: fileSystem,
            path: packagePath.appending(component: predefinedDirs.targetDir)
        )
        let predefinedTestTargetDirectory = PredefinedTargetDirectory(
            fs: fileSystem,
            path: packagePath.appending(component: predefinedDirs.testTargetDir)
        )
        let predefinedPluginTargetDirectory = PredefinedTargetDirectory(
            fs: fileSystem,
            path: packagePath.appending(component: predefinedDirs.pluginTargetDir)
        )

        /// Returns the path of the given target.
        func findPath(for target: TargetDescription) throws -> AbsolutePath {
            if target.type == .binary {
                guard let artifact = self.binaryArtifacts[target.name] else {
                    throw ModuleError.artifactNotFound(moduleName: target.name, expectedArtifactName: target.name)
                }
                return artifact.path
            } else if let subpath = target.path { // If there is a custom path defined, use that.
                if subpath == "" || subpath == "." {
                    return self.packagePath
                }

                // Make sure target is not referenced by absolute path
                guard let relativeSubPath = try? RelativePath(validating: subpath) else {
                    throw ModuleError.unsupportedTargetPath(subpath)
                }

                let path = self.packagePath.appending(relativeSubPath)
                // Make sure the target is inside the package root.
                guard path.isDescendantOfOrEqual(to: self.packagePath) else {
                    throw ModuleError.targetOutsidePackage(package: self.identity.description, target: target.name)
                }
                if self.fileSystem.isDirectory(path) {
                    return path
                }
                throw ModuleError.invalidCustomPath(moduleName: target.name, path: subpath)
            }

            // Check if target is present in the predefined directory.
            let predefinedDir: PredefinedTargetDirectory = switch target.type {
            case .test:
                predefinedTestTargetDirectory
            case .plugin:
                predefinedPluginTargetDirectory
            default:
                predefinedTargetDirectory
            }
            let path = predefinedDir.path.appending(component: target.name)

            // Return the path if the predefined directory contains it.
            if predefinedDir.contents.contains(target.name) {
                return path
            }

            let commonTargetsOfSimilarType = self.manifest.targetsWithCommonSourceRoot(type: target.type).count
            // If there is only one target defined, it may be allowed to occupy the
            // entire predefined target directory.
            if self.manifest.toolsVersion >= .v5_9 {
                if commonTargetsOfSimilarType == 1 {
                    return predefinedDir.path
                }
            }

            // Otherwise, if the path "exists" then the case in manifest differs from the case on the file system.
            if self.fileSystem.isDirectory(path) {
                self.observabilityScope.emit(.targetNameHasIncorrectCase(target: target.name))
                return path
            }
            throw ModuleError.moduleNotFound(
                target.name,
                target.type,
                shouldSuggestRelaxedSourceDir: self.manifest
                    .shouldSuggestRelaxedSourceDir(type: target.type)
            )
        }

        // Create potential targets.
        let potentialTargets: [PotentialModule]
        potentialTargets = try self.manifest.targetsRequired(for: self.productFilter).map { target in
            let path = try findPath(for: target)
            return PotentialModule(
                name: target.name,
                path: path,
                type: target.type,
                packageAccess: target.packageAccess
            )
        }

        let targets = try createModules(potentialTargets)

        let snippetTargets: [Module]

        if self.manifest.packageKind.isRoot {
            // Snippets: depend on all available library targets in the package.
            // TODO: Do we need to filter out targets that aren't available on the host platform?
            let productTargets = Set(manifest.products.flatMap(\.targets))
            let snippetDependencies = targets
                .filter { $0.type == .library && productTargets.contains($0.name) }
                .map { Module.Dependency.module($0, conditions: []) }
            snippetTargets = try createSnippetModules(dependencies: snippetDependencies)
        } else {
            snippetTargets = []
        }

        return targets + snippetTargets
    }

    // Create targets from the provided potential targets.
    private func createModules(_ potentialModules: [PotentialModule]) throws -> [Module] {
        // Find if manifest references a target which isn't present on disk.
        let allVisibleModuleNames = self.manifest.visibleModuleNames(for: self.productFilter)
        let potentialModulesName = Set(potentialModules.map(\.name))
        let missingModuleNames = allVisibleModuleNames.subtracting(potentialModulesName)
        if let missingModuleName = missingModuleNames.first {
            let type = potentialModules.first(where: { $0.name == missingModuleName })?.type ?? .regular
            throw ModuleError.moduleNotFound(
                missingModuleName,
                type,
                shouldSuggestRelaxedSourceDir: self.manifest.shouldSuggestRelaxedSourceDir(type: type)
            )
        }

        let products = Dictionary(manifest.products.map { ($0.name, $0) }, uniquingKeysWith: { $1 })

        // If there happens to be a plugin product with the right name in the same package, we want to use that
        // automatically.
        func pluginTargetName(for productName: String) -> String? {
            if let product = products[productName], product.type == .plugin {
                product.targets.first
            } else {
                nil
            }
        }

        let potentialModuleMap = Dictionary(potentialModules.map { ($0.name, $0) }, uniquingKeysWith: { $1 })
        let successors: (PotentialModule) -> [PotentialModule] = {
            // No reference of this target in manifest, i.e. it has no dependencies.
            guard let target = self.manifest.targetMap[$0.name] else { return [] }
            // Collect the successors from declared dependencies.
            var successors: [PotentialModule] = target.dependencies.compactMap {
                switch $0 {
                case .target(let name, _):
                    // Since we already checked above that all referenced targets
                    // has to present, we always expect this target to be present in
                    // potentialModules dictionary.
                    potentialModuleMap[name]!
                case .product:
                    nil
                case .byName(let name, _):
                    // By name dependency may or may not be a target dependency.
                    potentialModuleMap[name]
                }
            }
            // If there are plugin usages, consider them to be dependencies too.
            if let pluginUsages = target.pluginUsages {
                successors += pluginUsages.compactMap {
                    switch $0 {
                    case .plugin(_, .some(_)):
                        nil
                    case .plugin(let name, nil):
                        if let potentialModule = potentialModuleMap[name] {
                            potentialModule
                        } else if let targetName = pluginTargetName(for: name),
                                  let potentialModule = potentialModuleMap[targetName]
                        {
                            potentialModule
                        } else {
                            nil
                        }
                    }
                }
            }
            return successors
        }
        // Look for any cycle in the dependencies.
        if let cycle = findCycle(potentialModules.sorted(by: { $0.name < $1.name }), successors: successors) {
            throw ModuleError.cycleDetected((cycle.path.map(\.name), cycle.cycle.map(\.name)))
        }
        // There was no cycle so we sort the targets topologically.
        let potentialModules = try topologicalSort(potentialModules, successors: successors)

        // The created targets mapped to their name.
        var targets = [String: Module]()
        // If a directory is empty, we don't create a target object for them.
        var emptyModules = Set<String>()

        // Start iterating the potential targets.
        for potentialModule in potentialModules.lazy.reversed() {
            // Validate the target name.  This function will throw an error if it detects a problem.
            try validateModuleName(potentialModule.path, potentialModule.name, isTest: potentialModule.isTest)

            // Get the target from the manifest.
            let manifestTarget = manifest.targetMap[potentialModule.name]

            // Get the dependencies of this target.
            let dependencies: [Module.Dependency] = try manifestTarget.map {
                try $0.dependencies.compactMap { dependency -> Module.Dependency? in
                    switch dependency {
                    case .target(let name, let condition):
                        // We don't create an object for targets which have no sources.
                        if emptyModules.contains(name) { return nil }
                        guard let target = targets[name] else { return nil }
                        return .module(target, conditions: buildConditions(from: condition))

                    case .product(let name, let package, let moduleAliases, let condition):
                        try validateModuleAliases(moduleAliases)
                        return .product(
                            .init(name: name, package: package, moduleAliases: moduleAliases),
                            conditions: buildConditions(from: condition)
                        )
                    case .byName(let name, let condition):
                        // We don't create an object for targets which have no sources.
                        if emptyModules.contains(name) { return nil }
                        if let target = targets[name] {
                            return .module(target, conditions: buildConditions(from: condition))
                        } else if potentialModuleMap[name] == nil {
                            return .product(
                                .init(name: name, package: nil),
                                conditions: buildConditions(from: condition)
                            )
                        } else {
                            return nil
                        }
                    }
                }
            } ?? []

            // Get dependencies from the plugin usages of this target.
            let pluginUsages: [Module.PluginUsage] = manifestTarget?.pluginUsages.map {
                $0.compactMap { usage in
                    switch usage {
                    case .plugin(let name, let package):
                        if let package {
                            return .product(Module.ProductReference(name: name, package: package), conditions: [])
                        } else {
                            if let target = targets[name] {
                                return .module(target, conditions: [])
                            } else if let targetName = pluginTargetName(for: name), let target = targets[targetName] {
                                return .module(target, conditions: [])
                            } else {
                                self.observabilityScope.emit(.pluginNotFound(name: name))
                                return nil
                            }
                        }
                    }
                }
            } ?? []

            // Create the target, adding the inferred dependencies from plugin usages to the declared dependencies.
            let target = try createTarget(
                potentialModule: potentialModule,
                manifestTarget: manifestTarget,
                dependencies: dependencies + pluginUsages
            )
            // Add the created target to the map or print no sources warning.
            if let createdTarget = target {
                targets[createdTarget.name] = createdTarget
            } else {
                emptyModules.insert(potentialModule.name)
                self.observabilityScope.emit(.targetHasNoSources(
                    name: potentialModule.name,
                    type: potentialModule.type,
                    shouldSuggestRelaxedSourceDir: manifest
                        .shouldSuggestRelaxedSourceDir(
                            type: potentialModule
                                .type
                        )
                ))
            }
        }

        return targets.values.sorted { $0.name > $1.name }
    }

    /// Private function that checks whether a target name is valid.  This method doesn't return anything, but rather,
    /// if there's a problem, it throws an error describing what the problem is.
    private func validateModuleName(_ path: AbsolutePath, _ name: String, isTest: Bool) throws {
        if name.isEmpty {
            throw Module.Error.invalidName(
                path: path.relative(to: self.packagePath),
                problem: .emptyName
            )
        }
    }

    /// Validates module alias key and value pairs and throws an error if empty or contains invalid characters.
    private func validateModuleAliases(_ aliases: [String: String]?) throws {
        guard let aliases else { return }
        for (aliasKey, aliasValue) in aliases {
            if !aliasKey.isValidIdentifier ||
                !aliasValue.isValidIdentifier ||
                aliasKey == aliasValue
            {
                throw ModuleError.invalidModuleAlias(originalName: aliasKey, newName: aliasValue)
            }
        }
    }

    /// Private function that constructs a single Target object for the potential target.
    private func createTarget(
        potentialModule: PotentialModule,
        manifestTarget: TargetDescription?,
        dependencies: [Module.Dependency]
    ) throws -> Module? {
        guard let manifestTarget else { return nil }

        // Create system library target.
        if potentialModule.type == .system {
            let moduleMapPath = potentialModule.path.appending(component: moduleMapFilename)
            guard self.fileSystem.isFile(moduleMapPath) else {
                throw ModuleError.invalidLayout(.modulemapMissing(moduleMapPath))
            }

            return SystemLibraryModule(
                name: potentialModule.name,
                path: potentialModule.path, isImplicit: false,
                pkgConfig: manifestTarget.pkgConfig,
                providers: manifestTarget.providers
            )
        } else if potentialModule.type == .binary {
            guard let artifact = self.binaryArtifacts[potentialModule.name] else {
                throw InternalError("unknown binary artifact for '\(potentialModule.name)'")
            }
            let artifactOrigin: BinaryModule.Origin = artifact.originURL.flatMap { .remote(url: $0) } ?? .local
            return BinaryModule(
                name: potentialModule.name,
                kind: artifact.kind,
                path: potentialModule.path,
                origin: artifactOrigin
            )
        }

        // Check for duplicate target dependencies
        if self.manifest.disambiguateByProductIDs {
            let dupProductIDs = dependencies.compactMap { $0.product?.identity }.spm_findDuplicates()
            for dupProductID in dupProductIDs {
                let comps = dupProductID.components(separatedBy: "_")
                let pkg = comps.first ?? ""
                let name = comps.dropFirst().joined(separator: "_")
                let dupProductName = name.isEmpty ? dupProductID : name
                self.observabilityScope.emit(.duplicateProduct(name: dupProductName, package: pkg))
            }
            let dupTargetNames = dependencies.compactMap { $0.module?.name }.spm_findDuplicates()
            for dupTargetName in dupTargetNames {
                self.observabilityScope.emit(.duplicateTargetDependency(
                    dependency: dupTargetName,
                    target: potentialModule.name,
                    package: self.identity.description
                ))
            }
        } else {
            dependencies.filter { $0.product?.moduleAliases == nil }.spm_findDuplicateElements(by: \.nameAndType)
                .map(\.[0].name).forEach {
                    self.observabilityScope
                        .emit(.duplicateTargetDependency(
                            dependency: $0,
                            target: potentialModule.name,
                            package: self.identity.description
                        ))
                }
        }

        // Create the build setting assignment table for this target.
        let buildSettings = try self.buildSettings(
            for: manifestTarget,
            targetRoot: potentialModule.path,
            cxxLanguageStandard: self.manifest.cxxLanguageStandard,
            toolsSwiftVersion: self.toolsSwiftVersion()
        )

        // Compute the path to public headers directory.
        let publicHeaderComponent = manifestTarget.publicHeadersPath ?? ClangModule.defaultPublicHeadersComponent
        let publicHeadersPath = try potentialModule.path.appending(RelativePath(validating: publicHeaderComponent))
        guard publicHeadersPath.isDescendantOfOrEqual(to: potentialModule.path) else {
            throw ModuleError.invalidPublicHeadersDirectory(potentialModule.name)
        }

        let sourcesBuilder = TargetSourcesBuilder(
            packageIdentity: self.identity,
            packageKind: self.manifest.packageKind,
            packagePath: self.packagePath,
            target: manifestTarget,
            path: potentialModule.path,
            defaultLocalization: self.manifest.defaultLocalization,
            additionalFileRules: self.additionalFileRules,
            toolsVersion: self.manifest.toolsVersion,
            fileSystem: self.fileSystem,
            observabilityScope: self.observabilityScope
        )
        let (sources, resources, headers, ignored, others) = try sourcesBuilder.run()

        // Make sure defaultLocalization is set if the target has localized resources.
        let hasLocalizedResources = resources.contains(where: { $0.localization != nil })
        if hasLocalizedResources && self.manifest.defaultLocalization == nil {
            throw ModuleError.defaultLocalizationNotSet
        }

        // FIXME: use identity instead?
        // The name of the bundle, if one is being generated.
        let potentialBundleName = self.manifest.displayName + "_" + potentialModule.name

        if sources.relativePaths.isEmpty && resources.isEmpty && headers.isEmpty {
            return nil
        }
        try self.validateSourcesOverlapping(forTarget: potentialModule.name, sources: sources.paths)

        // Deal with package plugin targets.
        if potentialModule.type == .plugin {
            // Check that the target has a declared capability; we should not have come this far if not.
            guard let declaredCapability = manifestTarget.pluginCapability else {
                throw ModuleError.pluginCapabilityNotDeclared(target: manifestTarget.name)
            }

            // Create and return an PluginTarget configured with the information from the manifest.
            return PluginModule(
                name: potentialModule.name,
                sources: sources,
                apiVersion: self.manifest.toolsVersion,
                pluginCapability: PluginCapability(from: declaredCapability),
                dependencies: dependencies,
                packageAccess: potentialModule.packageAccess
            )
        }

        /// Determine the module's kind, or leave nil to check the source directory.
        let moduleKind: Module.Kind
        switch potentialModule.type {
        case .test:
            moduleKind = .test
        case .executable:
            moduleKind = .executable
        case .macro:
            moduleKind = .macro
        default:
            moduleKind = sources.computeModuleKind()
            if moduleKind == .executable && self.manifest.toolsVersion >= .v5_4 && self
                .warnAboutImplicitExecutableTargets
            {
                self.observabilityScope
                    .emit(
                        warning: "'\(potentialModule.name)' was identified as an executable target given the presence of a 'main' file. Starting with tools version \(ToolsVersion.v5_4) executable targets should be declared as 'executableTarget()'"
                    )
            }
        }

        // Create and return the right kind of target depending on what kind of sources we found.
        if sources.hasSwiftSources {
            return try SwiftModule(
                name: potentialModule.name,
                potentialBundleName: potentialBundleName,
                type: moduleKind,
                path: potentialModule.path,
                sources: sources,
                resources: resources,
                ignored: ignored,
                others: others,
                dependencies: dependencies,
                packageAccess: potentialModule.packageAccess,
                declaredSwiftVersions: self.declaredSwiftVersions(),
                buildSettings: buildSettings,
                buildSettingsDescription: manifestTarget.settings,
                usesUnsafeFlags: manifestTarget.usesUnsafeFlags
            )
        } else {
            // It's not a Swift target, so it's a Clang target (those are the only two types of source target currently
            // supported).

            // First determine the type of module map that will be appropriate for the target based on its header
            // layout.
            let moduleMapType: ModuleMapType

            if self.fileSystem.exists(publicHeadersPath) {
                let moduleMapGenerator = ModuleMapGenerator(
                    targetName: potentialModule.name,
                    moduleName: potentialModule.name.spm_mangledToC99ExtendedIdentifier(),
                    publicHeadersDir: publicHeadersPath,
                    fileSystem: self.fileSystem
                )
                moduleMapType = moduleMapGenerator.determineModuleMapType(observabilityScope: self.observabilityScope)
            } else if moduleKind == .library, self.manifest.toolsVersion >= .v5_5 {
                // If this clang target is a library, it must contain "include" directory.
                throw ModuleError.invalidPublicHeadersDirectory(potentialModule.name)
            } else {
                moduleMapType = .none
            }

            if resources.contains(where: { $0.rule == .embedInCode }) {
                throw ModuleError.embedInCodeNotSupported(target: potentialModule.name)
            }

            return try ClangModule(
                name: potentialModule.name,
                potentialBundleName: potentialBundleName,
                cLanguageStandard: self.manifest.cLanguageStandard,
                cxxLanguageStandard: self.manifest.cxxLanguageStandard,
                includeDir: publicHeadersPath,
                moduleMapType: moduleMapType,
                headers: headers,
                type: moduleKind,
                path: potentialModule.path,
                sources: sources,
                resources: resources,
                ignored: ignored,
                dependencies: dependencies,
                buildSettings: buildSettings,
                buildSettingsDescription: manifestTarget.settings,
                usesUnsafeFlags: manifestTarget.usesUnsafeFlags
            )
        }
    }

    /// Creates build setting assignment table for the given target.
    func buildSettings(
        for target: TargetDescription?,
        targetRoot: AbsolutePath,
        cxxLanguageStandard: String? = nil,
        toolsSwiftVersion: SwiftLanguageVersion
    ) throws -> BuildSettings.AssignmentTable {
        var table = BuildSettings.AssignmentTable()
        guard let target else { return table }

        // First let's add a default assignments for tools swift version.
        var versionAssignment = BuildSettings.Assignment(default: true)
        versionAssignment.values = [toolsSwiftVersion.rawValue]

        table.add(versionAssignment, for: .SWIFT_VERSION)

        // Process each setting.
        for setting in target.settings {
            if let traits = setting.condition?.traits, traits.intersection(self.enabledTraits).isEmpty {
                // The setting is currently not enabled so we should skip it
                continue
            }
        
            let decl: BuildSettings.Declaration
            let values: [String]

            // Compute appropriate declaration for the setting.
            switch setting.kind {
            case .headerSearchPath(let value):
                values = [value]

                switch setting.tool {
                case .c, .cxx:
                    decl = .HEADER_SEARCH_PATHS
                case .swift, .linker:
                    throw InternalError("unexpected tool for setting type \(setting)")
                }

                // Ensure that the search path is contained within the package.
                _ = try RelativePath(validating: value)
                let path = try AbsolutePath(validating: value, relativeTo: targetRoot)
                guard path.isDescendantOfOrEqual(to: self.packagePath) else {
                    throw ModuleError.invalidHeaderSearchPath(value)
                }

            case .define(let value):
                values = [value]

                switch setting.tool {
                case .c, .cxx:
                    decl = .GCC_PREPROCESSOR_DEFINITIONS
                case .swift:
                    decl = .SWIFT_ACTIVE_COMPILATION_CONDITIONS
                case .linker:
                    throw InternalError("unexpected tool for setting type \(setting)")
                }

            case .linkedLibrary(let value):
                values = [value]

                switch setting.tool {
                case .c, .cxx, .swift:
                    throw InternalError("unexpected tool for setting type \(setting)")
                case .linker:
                    decl = .LINK_LIBRARIES
                }

            case .linkedFramework(let value):
                values = [value]

                switch setting.tool {
                case .c, .cxx, .swift:
                    throw InternalError("unexpected tool for setting type \(setting)")
                case .linker:
                    decl = .LINK_FRAMEWORKS
                }

            case .interoperabilityMode(let lang):
                switch setting.tool {
                case .c, .cxx, .linker:
                    throw InternalError("only Swift supports interoperability")

                case .swift:
                    decl = .OTHER_SWIFT_FLAGS
                }

                if lang == .Cxx {
                    values = ["-cxx-interoperability-mode=default"] +
                        (cxxLanguageStandard.flatMap { ["-Xcc", "-std=\($0)"] } ?? [])
                } else {
                    values = []
                }

            case .unsafeFlags(let _values):
                values = _values

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

            case .enableUpcomingFeature(let value):
                switch setting.tool {
                case .c, .cxx, .linker:
                    throw InternalError("only Swift supports upcoming features")

                case .swift:
                    decl = .OTHER_SWIFT_FLAGS
                }

                values = ["-enable-upcoming-feature", value]

            case .enableExperimentalFeature(let value):
                switch setting.tool {
                case .c, .cxx, .linker:
                    throw InternalError(
                        "only Swift supports experimental features"
                    )

                case .swift:
                    decl = .OTHER_SWIFT_FLAGS
                }

                values = ["-enable-experimental-feature", value]

            case .swiftLanguageMode(let version):
                switch setting.tool {
                case .c, .cxx, .linker:
                    throw InternalError("only Swift supports swift language version")

                case .swift:
                    decl = .SWIFT_VERSION
                }

                values = [version.rawValue]
            }

            // Create an assignment for this setting.
            var assignment = BuildSettings.Assignment()
            assignment.values = values
            assignment.conditions = self.buildConditions(from: setting.condition)

            // Finally, add the assignment to the assignment table.
            table.add(assignment, for: decl)
        }

        // For each trait we are now generating an additional define
        for trait in self.enabledTraits {
            var assignment = BuildSettings.Assignment()
            assignment.values = ["\(trait)"]
            assignment.conditions = []
            table.add(assignment, for: .SWIFT_ACTIVE_COMPILATION_CONDITIONS)
        }

        return table
    }

    func buildConditions(from condition: PackageConditionDescription?) -> [PackageCondition] {
        var conditions: [PackageCondition] = []

        if let config = condition?.config.flatMap({ BuildConfiguration(rawValue: $0) }) {
            conditions.append(.init(configuration: config))
        }

        if let platforms = condition?.platformNames.map({
            if let platform = platformRegistry.platformByName[$0] {
                platform
            } else {
                PackageModel.Platform.custom(name: $0, oldestSupportedVersion: .unknown)
            }
        }), !platforms.isEmpty {
            conditions.append(.init(platforms: platforms))
        }

        if let traits = condition?.traits {
            conditions.append(.traits(.init(traits: traits)))
        }

        return conditions
    }

    private func declaredSwiftVersions() throws -> [SwiftLanguageVersion] {
        if let versions = self.declaredSwiftVersionsCache {
            return versions
        }

        let versions: [SwiftLanguageVersion]
        if let swiftLanguageVersions = manifest.swiftLanguageVersions {
            versions = swiftLanguageVersions.sorted(by: >).filter { $0 <= ToolsVersion.current }

            if versions.isEmpty {
                throw ModuleError.incompatibleToolsVersions(
                    package: self.identity.description, required: swiftLanguageVersions, current: .current
                )
            }
        } else {
            versions = []
        }

        self.declaredSwiftVersionsCache = versions
        return versions
    }

    /// Computes the swift version to use for this manifest.
    private func toolsSwiftVersion() throws -> SwiftLanguageVersion {
        if let swiftVersion = self.swiftVersionCache {
            return swiftVersion
        }

        // Figure out the swift version from declared list in the manifest.
        let declaredSwiftVersions = try declaredSwiftVersions()
        let computedSwiftVersion: SwiftLanguageVersion = if let declaredSwiftVersion = declaredSwiftVersions.first {
            declaredSwiftVersion
        } else {
            // Otherwise, use the version depending on the manifest version.
            self.manifest.toolsVersion.swiftLanguageVersion
        }
        self.swiftVersionCache = computedSwiftVersion
        return computedSwiftVersion
    }

    /// Validates that the sources of a target are not already present in another target.
    private func validateSourcesOverlapping(forTarget target: String, sources: [AbsolutePath]) throws {
        // Compute the sources which overlap with already computed targets.
        var overlappingSources: Set<AbsolutePath> = []
        for source in sources {
            if !self.allSources.insert(source).inserted {
                overlappingSources.insert(source)
            }
        }

        // Throw if we found any overlapping sources.
        if !overlappingSources.isEmpty {
            throw ModuleError.overlappingSources(target: target, sources: Array(overlappingSources))
        }
    }

    /// Find the test entry point file for the package.
    private func findTestEntryPoint(in testTargets: [Module]) throws -> AbsolutePath? {
        if let testEntryPointPath {
            return testEntryPointPath
        }

        var testEntryPointFiles = Set<AbsolutePath>()
        var pathsSearched = Set<AbsolutePath>()

        // Look for entry point file adjacent to each test target root, iterating upto package root.
        for target in testTargets {
            // Form the initial search path.
            //
            // If the target root's parent directory is inside the package, start
            // search there. Otherwise, we start search from the target root.
            var searchPath = target.sources.root.parentDirectory
            if !searchPath.isDescendantOfOrEqual(to: self.packagePath) {
                searchPath = target.sources.root
            }

            while true {
                guard searchPath.isDescendantOfOrEqual(to: self.packagePath) else {
                    throw InternalError("search path \(searchPath) is outside the package \(self.packagePath)")
                }
                // If we have already searched this path, skip.
                if !pathsSearched.contains(searchPath) {
                    for name in SwiftModule.testEntryPointNames {
                        let path = searchPath.appending(component: name)
                        if self.fileSystem.isFile(path) {
                            testEntryPointFiles.insert(path)
                        }
                    }
                    pathsSearched.insert(searchPath)
                }
                // Break if we reached all the way to package root.
                if searchPath == self.packagePath { break }
                // Go one level up.
                searchPath = searchPath.parentDirectory
            }
        }

        // It is an error if there are multiple linux main files.
        if testEntryPointFiles.count > 1 {
            throw ModuleError.multipleTestEntryPointFilesFound(
                package: self.identity.description, files: testEntryPointFiles.map { $0 }
            )
        }
        return testEntryPointFiles.first
    }

    /// Collects the products defined by a package.
    private func constructProducts(_ modules: [Module]) throws -> [Product] {
        var products = OrderedCollections.OrderedSet<KeyedPair<Product, String>>()

        /// Helper method to append to products array.
        func append(_ product: Product) {
            let inserted = products.append(KeyedPair(product, key: product.name)).inserted
            if !inserted {
                self.observabilityScope.emit(.duplicateProduct(product: product))
            }
        }

        // Collect all test modules.
        let testModules = modules.filter { module in
            guard module.type == .test else { return false }
            #if os(Linux)
            // FIXME: Ignore C language test targets on linux for now.
            if module is ClangModule {
                self.observabilityScope
                    .emit(.unsupportedCTestTarget(package: self.identity.description, target: module.name))
                return false
            }
            #endif
            return true
        }

        // If enabled, create one test product for each test module.
        if self.shouldCreateMultipleTestProducts {
            for testModule in testModules {
                let product = try Product(
                    package: self.identity,
                    name: testModule.name,
                    type: .test,
                    modules: [testModule]
                )
                append(product)
            }
        } else if !testModules.isEmpty {
            // Otherwise we only need to create one test product for all of the
            // test targets.
            //
            // Add suffix 'PackageTests' to test product name so the target name
            // of linux executable don't collide with main package, if present.
            // FIXME: use identity instead
            let productName = self.manifest.displayName + "PackageTests"
            let testEntryPointPath = try self.findTestEntryPoint(in: testModules)

            let product = try Product(
                package: self.identity,
                name: productName,
                type: .test,
                modules: testModules,
                testEntryPointPath: testEntryPointPath
            )
            append(product)
        }

        // Map containing modules mapped to their names.
        let modulesMap = Dictionary(modules.map { ($0.name, $0) }, uniquingKeysWith: { $1 })

        /// Helper method to get targets from target names.
        func modulesFrom(moduleNames names: [String], product: String) throws -> [Module] {
            // Get targets from target names.
            try names.map { targetName in
                // Ensure we have this target.
                guard let target = modulesMap[targetName] else {
                    throw Product.Error.moduleEmpty(product: product, target: targetName)
                }
                return target
            }
        }

        // First add explicit products.

        let filteredProducts: [ProductDescription] = switch self.productFilter {
        case .everything:
            self.manifest.products
        case .specific(let set):
            self.manifest.products.filter { set.contains($0.name) }
        }
        for product in filteredProducts {
            if product.name.isEmpty {
                throw Product.Error.emptyName
            }

            let modules = try modulesFrom(moduleNames: product.targets, product: product.name)
            // Perform special validations if this product is exporting
            // a system library target.
            if modules.contains(where: { $0 is SystemLibraryModule }) {
                if product.type != .library(.automatic) || modules.count != 1 {
                    self.observabilityScope.emit(.systemPackageProductValidation(product: product.name))
                    continue
                }
            }

            // Do some validation based on the product type.
            switch product.type {
            case .library:
                guard self.validateLibraryProduct(product, with: modules) else {
                    continue
                }
            case .test, .macro:
                break
            case .executable, .snippet:
                guard self.validateExecutableProduct(product, with: modules) else {
                    continue
                }
            case .plugin:
                guard self.validatePluginProduct(product, with: modules) else {
                    continue
                }
            }

            try append(Product(package: self.identity, name: product.name, type: product.type, modules: modules))
        }

        // Add implicit executables - for root packages and for dependency plugins.

        // Compute the list of targets which are being used in an
        // executable product so we don't create implicit executables
        // for them.
        let explicitProductsModules = Set(self.manifest.products.flatMap { product -> [String] in
            switch product.type {
            case .library, .plugin, .test, .macro:
                return []
            case .executable, .snippet:
                return product.targets
            }
        })

        let productMap = products.reduce(into: [String: Product]()) { partial, iterator in
            partial[iterator.key] = iterator.item
        }

        let implicitPlugInExecutables = Set(
            modules.lazy
                .filter { $0.type == .plugin }
                .flatMap(\.dependencies)
                .map(\.name)
        )

        for module in modules where module.type == .executable {
            if self.manifest.packageKind.isRoot && explicitProductsModules.contains(module.name) {
                // If there is already an executable module with this name, skip generating a product for it
                // (This shortcut only works for the root manifest, because for dependencies,
                // products that correspond to plug‐ins may have been culled during resolution.)
                continue
            } else if let product = productMap[module.name] {
                // If there is already a product with this name skip generating a product for it,
                // but warn if that product is not executable
                if product.type != .executable {
                    self.observabilityScope
                        .emit(
                            warning: "The target named '\(module.name)' was identified as an executable target but a non-executable product with this name already exists."
                        )
                }
                continue
            } else {
                if self.manifest.packageKind.isRoot || implicitPlugInExecutables.contains(module.name) {
                    // Generate an implicit product for the executable target
                    let product = try Product(
                        package: self.identity,
                        name: module.name,
                        type: .executable,
                        modules: [module]
                    )
                    append(product)
                }
            }
        }

        // Create a special REPL product that contains all the library targets.

        if self.createREPLProduct {
            let libraryTargets = modules.filter { $0.type == .library }
            if libraryTargets.isEmpty {
                self.observabilityScope.emit(.noLibraryTargetsForREPL)
            } else {
                let replProduct = try Product(
                    package: self.identity,
                    name: self.identity.description + Product.replProductSuffix,
                    type: .library(.dynamic),
                    modules: libraryTargets
                )
                append(replProduct)
            }
        }

        // Create implicit snippet products
        try modules
            .filter { $0.type == .snippet }
            .map { try Product(package: self.identity, name: $0.name, type: .snippet, modules: [$0]) }
            .forEach(append)

        // Create implicit macro products
        try modules
            .filter { $0.type == .macro }
            .map { try Product(package: self.identity, name: $0.name, type: .macro, modules: [$0]) }
            .forEach(append)

        return products.map(\.item)
    }

    private func validateLibraryProduct(_ product: ProductDescription, with targets: [Module]) -> Bool {
        let pluginTargets = targets.filter { $0.type == .plugin }
        guard pluginTargets.isEmpty else {
            self.observabilityScope.emit(.nonPluginProductWithPluginTargets(
                product: product.name,
                type: product.type,
                pluginTargets: pluginTargets.map(\.name)
            ))
            return false
        }
        if self.manifest.toolsVersion >= .v5_7 {
            let executableTargets = targets.filter { $0.type == .executable }
            guard executableTargets.isEmpty else {
                self.observabilityScope
                    .emit(.libraryProductWithExecutableTarget(
                        product: product.name,
                        executableTargets: executableTargets.map(\.name)
                    ))
                return false
            }
        }
        return true
    }

    private func validateExecutableProduct(_ product: ProductDescription, with targets: [Module]) -> Bool {
        let executableTargetCount = targets.executables.count
        guard executableTargetCount == 1 else {
            if executableTargetCount == 0 {
                if let target = targets.spm_only {
                    self.observabilityScope
                        .emit(.executableProductTargetNotExecutable(product: product.name, target: target.name))
                } else {
                    self.observabilityScope.emit(.executableProductWithoutExecutableTarget(product: product.name))
                }
            } else {
                self.observabilityScope.emit(.executableProductWithMoreThanOneExecutableTarget(product: product.name))
            }
            return false
        }
        let pluginTargets = targets.filter { $0.type == .plugin }
        guard pluginTargets.isEmpty else {
            self.observabilityScope.emit(.nonPluginProductWithPluginTargets(
                product: product.name,
                type: product.type,
                pluginTargets: pluginTargets.map(\.name)
            ))
            return false
        }
        return true
    }

    private func validatePluginProduct(_ product: ProductDescription, with targets: [Module]) -> Bool {
        let nonPluginTargets = targets.filter { $0.type != .plugin }
        guard nonPluginTargets.isEmpty else {
            self.observabilityScope
                .emit(.pluginProductWithNonPluginTargets(
                    product: product.name,
                    otherTargets: nonPluginTargets.map(\.name)
                ))
            return false
        }
        guard !targets.isEmpty else {
            self.observabilityScope.emit(.pluginProductWithNoTargets(product: product.name))
            return false
        }
        return true
    }

    /// Returns the first suggested predefined source directory for a given target type.
    public static func suggestedPredefinedSourceDirectory(type: TargetDescription.TargetKind) -> String {
        // These are static constants, safe to access by index; the first choice is preferred.
        switch type {
        case .test:
            self.predefinedTestDirectories[0]
        case .plugin:
            self.predefinedPluginDirectories[0]
        default:
            self.predefinedSourceDirectories[0]
        }
    }
}

extension PackageBuilder {
    struct PredefinedTargetDirectory {
        let path: AbsolutePath
        let contents: [String]

        init(fs: FileSystem, path: AbsolutePath) {
            self.path = path
            self.contents = (try? fs.getDirectoryContents(path)) ?? []
        }
    }
}

/// We create this structure after scanning the filesystem for potential modules.
private struct PotentialModule: Hashable {
    /// Name of the module.
    let name: String

    /// The path of the module.
    let path: AbsolutePath

    /// If this should be a test module.
    var isTest: Bool {
        self.type == .test
    }

    /// The module type.
    let type: TargetDescription.TargetKind

    /// If true, access to package declarations from other modules is allowed.
    let packageAccess: Bool
}

extension Manifest {
    /// Returns the names of all the visible modules in the manifest.
    fileprivate func visibleModuleNames(for productFilter: ProductFilter) -> Set<String> {
        let names = targetsRequired(for: productFilter).flatMap { target in
            [target.name] + target.dependencies.compactMap {
                switch $0 {
                case .target(let name, _):
                    name
                case .byName, .product:
                    nil
                }
            }
        }
        return Set(names)
    }
}

extension Sources {
    var hasSwiftSources: Bool {
        paths.contains { path in
            guard let ext = path.extension else { return false }

            return FileRuleDescription.swift.fileTypes.contains(ext)
        }
    }

    var hasClangSources: Bool {
        let supportedClangFileExtensions = FileRuleDescription.clang.fileTypes.union(FileRuleDescription.asm.fileTypes)

        return paths.contains { path in
            guard let ext = path.extension else { return false }

            return supportedClangFileExtensions.contains(ext)
        }
    }

    var containsMixedLanguage: Bool {
        self.hasSwiftSources && self.hasClangSources
    }

    /// Determine module type based on the sources.
    fileprivate func computeModuleKind() -> Module.Kind {
        let isLibrary = !relativePaths.contains { path in
            let file = path.basename.lowercased()
            // Look for a main.xxx file avoiding cases like main.xxx.xxx
            return file.hasPrefix("main.") && String(file.filter { $0 == "." }).count == 1
        }
        return isLibrary ? .library : .executable
    }
}

extension Module.Dependency {
    fileprivate var nameAndType: String {
        switch self {
        case .module:
            "target-\(name)"
        case .product:
            "product-\(name)"
        }
    }
}

// MARK: - Snippets

extension PackageBuilder {
    private func createSnippetModules(dependencies: [Module.Dependency]) throws -> [Module] {
        let snippetsDirectory = self.packagePath.appending("Snippets")
        guard self.fileSystem.isDirectory(snippetsDirectory) else {
            return []
        }

        return try walk(snippetsDirectory, fileSystem: self.fileSystem)
            .filter { self.fileSystem.isFile($0) && $0.extension == "swift" }
            .map { sourceFile in
                let name = sourceFile.basenameWithoutExt
                let sources = Sources(paths: [sourceFile], root: sourceFile.parentDirectory)
                let buildSettings: BuildSettings.AssignmentTable

                let targetDescription = try TargetDescription(
                    name: name,
                    dependencies: dependencies
                        .map {
                            TargetDescription.Dependency.target(name: $0.name)
                        },
                    path: sourceFile.parentDirectory.pathString,
                    sources: [sourceFile.pathString],
                    type: .executable,
                    packageAccess: false
                )
                buildSettings = try self.buildSettings(
                    for: targetDescription,
                    targetRoot: sourceFile.parentDirectory,
                    toolsSwiftVersion: self.toolsSwiftVersion()
                )

                return SwiftModule(
                    name: name,
                    type: .snippet,
                    path: .root,
                    sources: sources,
                    dependencies: dependencies,
                    packageAccess: false,
                    buildSettings: buildSettings,
                    buildSettingsDescription: targetDescription.settings,
                    usesUnsafeFlags: false
                )
            }
    }
}

extension Sequence {
    /// Construct a new array where each of the elements in the \c self
    /// sequence is preceded by the \c prefixElement.
    ///
    /// For example:
    /// ```
    /// ["Alice", "Bob", "Charlie"].precedeElements(with: "Hi")
    /// ```
    ///
    /// produces `["Hi", "Alice", "Hi", "Bob", "Hi", "Charlie"]`.
    private func precedeElements(with prefixElement: Element) -> [Element] {
        var results: [Element] = []
        for element in self {
            results.append(prefixElement)
            results.append(element)
        }
        return results
    }
}

extension TargetDescription {
    fileprivate var usesUnsafeFlags: Bool {
        settings.filter(\.kind.isUnsafeFlags).isEmpty == false
    }
}
