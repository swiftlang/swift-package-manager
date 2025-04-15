//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

import struct TSCUtility.Version

import struct Basics.AbsolutePath
import struct Basics.Diagnostic
import let Basics.localFileSystem
import struct Basics.ObservabilityMetadata
import class Basics.ObservabilityScope
import class Basics.ObservabilitySystem
import struct Basics.RelativePath
import struct Basics.SourceControlURL
import class Basics.ThreadSafeArrayStore

import enum PackageModel.BuildConfiguration
import enum PackageModel.BuildSettings
import class PackageModel.ClangModule
import struct PackageModel.ConfigurationCondition
import class PackageModel.Manifest
import class PackageModel.Module
import enum PackageModel.ModuleMapType
import class PackageModel.Package
import enum PackageModel.PackageCondition
import struct PackageModel.PackageIdentity
import struct PackageModel.Platform
import struct PackageModel.PlatformDescription
import struct PackageModel.PlatformRegistry
import struct PackageModel.PlatformsCondition
import class PackageModel.PluginModule
import class PackageModel.Product
import enum PackageModel.ProductType
import struct PackageModel.Resource
import struct PackageModel.SupportedPlatform
import struct PackageModel.SwiftLanguageVersion
import class PackageModel.SwiftModule
import class PackageModel.SystemLibraryModule
import struct PackageModel.ToolsVersion
import struct PackageModel.TraitCondition

import struct PackageGraph.ResolvedModule
import struct PackageGraph.ResolvedPackage
import struct PackageGraph.ResolvedProduct

import func PackageLoading.pkgConfigArgs

// TODO: Move this back to `PackagePIFBuilder` once we get rid of `#if canImport(SwiftBuild)`.
func targetName(forProductName name: String, suffix: String? = nil) -> String {
    let suffix = suffix ?? ""
    return "\(name)\(suffix)-product"
}

#if canImport(SwiftBuild)

import enum SwiftBuild.ProjectModel

// MARK: - PIF GUID Helpers

enum TargetSuffix: String {
    case testable, dynamic
    
    func hasSuffix(id: GUID) -> Bool {
        id.value.hasSuffix("-\(self.rawValue)")
    }
}

extension TargetSuffix? {
    func description(forName name: String) -> String {
        switch self {
        case .some(let suffix):
            "-\(String(name.hash, radix: 16, uppercase: true))-\(suffix.rawValue)"
        case .none:
            ""
        }
    }
}

extension GUID {
    func hasSuffix(_ suffix: TargetSuffix) -> Bool {
        self.value.hasSuffix("-\(suffix.rawValue)")
    }
}

extension PackageModel.Module {
    var pifTargetGUID: GUID { pifTargetGUID(suffix: nil) }

    func pifTargetGUID(suffix: TargetSuffix?) -> GUID {
        PackagePIFBuilder.targetGUID(forModuleName: self.name, suffix: suffix)
    }
}

extension PackageGraph.ResolvedModule {
    var pifTargetGUID: GUID { pifTargetGUID(suffix: nil) }

    func pifTargetGUID(suffix: TargetSuffix?) -> GUID {
        self.underlying.pifTargetGUID(suffix: suffix)
    }
}

extension PackageModel.Product {
    var pifTargetGUID: GUID { pifTargetGUID(suffix: nil) }

    func pifTargetGUID(suffix: TargetSuffix?) -> GUID {
        PackagePIFBuilder.targetGUID(forProductName: self.name, suffix: suffix)
    }
}

extension PackageGraph.ResolvedProduct {
    var pifTargetGUID: GUID { pifTargetGUID(suffix: nil) }

    func pifTargetGUID(suffix: TargetSuffix?) -> GUID {
        self.underlying.pifTargetGUID(suffix: suffix)
    }

    func targetName(suffix: TargetSuffix? = nil) -> String {
        PackagePIFBuilder.targetName(forProductName: self.name, suffix: suffix)
    }
}

extension PackagePIFBuilder {
    /// Helper function to consistently generate a PIF target identifier string for a module in a package.
    ///
    /// This format helps make sure that there is no collision with any other PIF targets,
    /// and in particular that a PIF target and a PIF product can have the same name (as they often do).
    static func targetGUID(forModuleName name: String, suffix: TargetSuffix? = nil) -> GUID {
        let suffixDescription = suffix.description(forName: name)
        return "PACKAGE-TARGET:\(name)\(suffixDescription)"
    }

    /// Helper function to consistently generate a PIF target identifier string for a product in a package.
    ///
    /// This format helps make sure that there is no collision with any other PIF targets,
    /// and in particular that a PIF target and a PIF product can have the same name (as they often do).
    static func targetGUID(forProductName name: String, suffix: TargetSuffix? = nil) -> GUID {
        let suffixDescription = suffix.description(forName: name)
        return "PACKAGE-PRODUCT:\(name)\(suffixDescription)"
    }
    
    /// Helper function to consistently generate a target name string for a product in a package.
    /// This format helps make sure that targets and products with the same name (as they often have) have different
    /// target names in the PIF.
    static func targetName(forProductName name: String, suffix: TargetSuffix? = nil) -> String {
        return SwiftBuildSupport.targetName(forProductName: name, suffix: suffix?.rawValue)
    }
}

// MARK: - SwiftPM PackageModel Helpers

extension PackageModel.PackageIdentity {
    var c99name: String {
        self.description.spm_mangledToC99ExtendedIdentifier()
    }
}

extension PackageModel.Package {
    /// Package name as defined in the manifest.
    var name: String {
        self.manifest.displayName
    }

    var packageBaseBuildSettings: ProjectModel.BuildSettings {
        var settings = BuildSettings()
        settings[.SDKROOT] = "auto"
        settings[.SDK_VARIANT] = "auto"

        if self.manifest.toolsVersion >= ToolsVersion.v6_0 {
            if let version = manifest.version, !version.isPrerelease && !version.hasBuildMetadata {
                settings[.SWIFT_USER_MODULE_VERSION] = version.stringRepresentation
            }
        }
        return settings
    }
}

extension PackageModel.Module {
    var isExecutable: Bool {
        switch self.type {
        case .executable, .snippet:
            true
        case .library, .test, .macro, .systemModule, .plugin, .binary:
            false
        }
    }

    var isBinary: Bool {
        switch self.type {
        case .binary:
            true
        case .library, .executable, .snippet, .test, .plugin, .macro, .systemModule:
            false
        }
    }

    /// Is this a source module? i.e., one that's compiled into a module from source code.
    var isSourceModule: Bool {
        switch self.type {
        case .library, .executable, .snippet, .test, .macro:
            true
        case .systemModule, .plugin, .binary:
            false
        }
    }
}

extension PackageModel.ProductType {
    var targetType: Module.Kind {
        switch self {
        case .executable: .executable
        case .snippet: .snippet
        case .test: .test
        case .library: .library
        case .plugin: .plugin
        case .macro: .macro
        }
    }
}

extension PackageModel.Platform {
    static var knownPlatforms: Set<PackageModel.Platform> {
        Set(PlatformRegistry.default.knownPlatforms)
    }
}

extension Sequence<PackageModel.PackageCondition> {
    func toPlatformFilter(toolsVersion: ToolsVersion) -> Set<ProjectModel.PlatformFilter> {
        let pifPlatforms = self.flatMap { packageCondition -> [ProjectModel.BuildSettings.Platform] in
            guard let platforms = packageCondition.platformsCondition?.platforms else {
                return []
            }

            var pifPlatformsForCondition: [ProjectModel.BuildSettings.Platform] = platforms
                .map { ProjectModel.BuildSettings.Platform(from: $0) }

            // Treat catalyst like macOS for backwards compatibility with older tools versions.
            if pifPlatformsForCondition.contains(.macOS), toolsVersion < ToolsVersion.v5_5 {
                pifPlatformsForCondition.append(.macCatalyst)
            }
            return pifPlatformsForCondition
        }
        return Set(pifPlatforms.flatMap { $0.toPlatformFilter() })
    }

    var splitIntoConcreteConditions: (
        [PackageModel.Platform?],
        [PackageModel.BuildConfiguration],
        [PackageModel.TraitCondition]
    ) {
        var platformConditions: [PackageModel.PlatformsCondition] = []
        var configurationConditions: [PackageModel.ConfigurationCondition] = []
        var traitConditions: [PackageModel.TraitCondition] = []

        for packageCondition in self {
            switch packageCondition {
            case .platforms(let condition): platformConditions.append(condition)
            case .configuration(let condition): configurationConditions.append(condition)
            case .traits(let condition): traitConditions.append(condition)
            }
        }

        // Determine the *platform* conditions, if any.
        // An empty set means that there are no platform restrictions.
        let platforms: [PackageModel.Platform?] = if platformConditions.isEmpty {
            [nil]
        } else {
            platformConditions.flatMap(\.platforms)
        }

        // Determine the *configuration* conditions, if any.
        // If there are none, we apply the setting to both debug and release builds (ie, `allCases`).
        let configurations: [BuildConfiguration] = if configurationConditions.isEmpty {
            BuildConfiguration.allCases
        } else {
            configurationConditions.map(\.configuration)
        }

        return (platforms, configurations, traitConditions)
    }
}

extension PackageModel.BuildSettings.Declaration {
    var allowsMultipleValues: Bool {
        switch self {
        // Swift.
        case .SWIFT_ACTIVE_COMPILATION_CONDITIONS, .OTHER_SWIFT_FLAGS:
            true

        case .SWIFT_VERSION:
            false

        // C family.
        case .GCC_PREPROCESSOR_DEFINITIONS, .HEADER_SEARCH_PATHS, .OTHER_CFLAGS, .OTHER_CPLUSPLUSFLAGS:
            true

        // Linker.
        case .OTHER_LDFLAGS, .LINK_LIBRARIES, .LINK_FRAMEWORKS:
            true

        default:
            true
        }
    }
}

// MARK: - SwiftPM PackageGraph Helpers

extension PackageGraph.ResolvedPackage {
    var name: String {
        self.underlying.name
    }

    /// The options declared per platform.
    func sdkOptions(delegate: PackagePIFBuilder.BuildDelegate) -> [PackageModel.Platform: [String]] {
        let platformDescriptionsByName: [String: PlatformDescription] = Dictionary(
            uniqueKeysWithValues: self.manifest.platforms.map { platformDescription in
                let key = platformDescription.platformName.lowercased()
                let value = platformDescription
                return (key, value)
            }
        )

        var sdkOptions: [PackageModel.Platform: [String]] = [:]
        for platform in Platform.knownPlatforms {
            sdkOptions[platform] = platformDescriptionsByName[platform.name.lowercased()]?.options

            let customSDKOptions = delegate.customSDKOptions(forPlatform: platform)
            if customSDKOptions.hasContent {
                sdkOptions[platform, default: []].append(contentsOf: customSDKOptions)
            }
        }
        return sdkOptions
    }
}

extension PackageGraph.ResolvedPackage {
    public var packageBaseBuildSettings: ProjectModel.BuildSettings {
        self.underlying.packageBaseBuildSettings
    }
}

extension PackageGraph.ResolvedModule {
    var isExecutable: Bool { self.underlying.isExecutable }
    var isBinary: Bool { self.underlying.isBinary }
    var isSourceModule: Bool { self.underlying.isSourceModule }

    /// The path of the module.
    var path: AbsolutePath { self.underlying.path }

    /// The stable sorted list of resources in the module
    var resources: [PackageModel.Resource] {
        self.underlying.resources.sorted(on: \.path)
    }

    /// The name of the group this module belongs to; by default, the package identity.
    var packageName: String? {
        self.packageAccess ? packageIdentity.c99name : nil
    }

    /// Minimum deployment targets for particular platforms, as declared in the manifest.
    func deploymentTargets(using delegate: PackagePIFBuilder.BuildDelegate) -> [PackageModel.Platform: String] {
        let isUsingXCTest = (self.type == .test)
        let derivedSupportedPlatforms: [SupportedPlatform] = Platform.knownPlatforms.map {
            self.getSupportedPlatform(for: $0, usingXCTest: isUsingXCTest)
        }

        var deploymentTargets: [PackageModel.Platform: String] = [:]
        for derivedSupportedPlatform in derivedSupportedPlatforms {
            deploymentTargets[derivedSupportedPlatform.platform] = derivedSupportedPlatform.version.versionString

            // If the version for this platform wasn't actually declared explicitly in the manifest,
            // try to derive an aligned version from the iOS declaration, if there was one.
            let targetPlatform = derivedSupportedPlatform.platform
            let isPlatformMissing = !self.supportedPlatforms.map(\.platform).contains(targetPlatform)
            guard isPlatformMissing else { continue }

            let iOSDeploymentTarget = self.getSupportedPlatform(for: .iOS, usingXCTest: isUsingXCTest).version
            let mappedVersion = delegate.suggestAlignedPlatformVersionGiveniOSVersion(
                platform: targetPlatform,
                iOSVersion: iOSDeploymentTarget
            )

            if let mappedVersion {
                deploymentTargets[targetPlatform] = mappedVersion
            }
        }
        return deploymentTargets
    }

    /// Platforms explicitly declared in the manifest for the purpose of customizing deployment targets.
    ///
    /// This does not include any custom platforms the user may have defined.
    /// A package is still considered to be runnable for *all* platforms.
    var declaredPlatforms: [PackageModel.Platform] {
        let knownPlatforms = Platform.knownPlatforms

        let declaredPlatforms: [PackageModel.Platform] = self.supportedPlatforms.compactMap {
            guard knownPlatforms.contains($0.platform) else { return nil }
            return $0.platform
        }
        return declaredPlatforms
    }

    /// Relative paths of each of the source files (relative to `target.sources.root`).
    var sourceFileRelativePaths: [RelativePath] {
        self.sources.relativePaths.map { try! RelativePath(validating: $0.pathString) }
    }

    /// Absolute path of the top-level directory of the sources.
    var sourceDirAbsolutePath: AbsolutePath {
        try! AbsolutePath(validating: self.sources.root.pathString)
    }

    /// Absolute paths to each of the header files  (*only* applies to C-language modules).
    var headerFileAbsolutePaths: [AbsolutePath] {
        guard let clangTarget = self.underlying as? ClangModule else { return [] }
        return clangTarget.headers
    }

    /// Relative path of the `include` directory (*only* applies to C-language modules).
    var includeDirRelativePath: RelativePath? {
        guard let clangModule = self.underlying as? ClangModule else { return nil }
        let relativePath = clangModule.includeDir.relative(to: self.sources.root).pathString
        return try! RelativePath(validating: relativePath)
    }

    /// Include directory as an *absolute* path.
    var includeDirAbsolutePath: AbsolutePath? {
        guard let includeDirRelativePath = self.includeDirRelativePath else { return nil }
        return self.sourceDirAbsolutePath.appending(includeDirRelativePath)
    }

    /// Relative path of the module-map file, if any (*only* applies to C-language modules).
    var moduleMapFileRelativePath: RelativePath? {
        guard let clangModule = self.underlying as? ClangModule else { return nil }
        let moduleMapFileAbsolutePath = clangModule.moduleMapPath

        // Check whether there is actually a modulemap at the specified path.
        // FIXME: Feels wrong to do file system access at this level —— instead, libSwiftPM's TargetBuilder should do that?
        guard localFileSystem.isFile(moduleMapFileAbsolutePath) else { return nil }

        let moduleMapFileRelativePath = moduleMapFileAbsolutePath.relative(to: clangModule.sources.root)
        return try! RelativePath(validating: moduleMapFileRelativePath.pathString)
    }

    /// Module map type (*only* applies to C-language modules).
    var moduleMapType: ModuleMapType? {
        guard let clangModule = self.underlying as? ClangModule else { return nil }
        return clangModule.moduleMapType
    }

    /// The C language standard for which the module is configured (*only* applies to C-language modules).
    var cLanguageStandard: String? {
        guard let clangModule = self.underlying as? ClangModule else { return nil }
        return clangModule.cLanguageStandard
    }

    /// The C++ language standard for which the module is configured (*only* applies to C-language modules).
    var cxxLanguageStandard: String? {
        guard let clangTarget = self.underlying as? ClangModule else { return nil }
        return clangTarget.cxxLanguageStandard
    }

    /// Whether or not this module contains C++ sources (*only* applies to C-language modules).
    var isCxx: Bool {
        guard let clangTarget = self.underlying as? ClangModule else { return false }
        return clangTarget.isCXX
    }

    /// The list of swift versions declared by the manifest.
    var declaredSwiftVersions: [SwiftLanguageVersion]? {
        guard let swiftTarget = self.underlying as? SwiftModule else { return nil }
        return swiftTarget.declaredSwiftVersions
    }

    /// Is this a Swift module?
    var usesSwift: Bool {
        self.declaredSwiftVersions != nil
    }

    /// Swift language version for which the module is configured.
    func packageSwiftLanguageVersion(manifest: PackageModel.Manifest) -> String? {
        guard let declaredSwiftVersions else { return nil }

        // Probably wrong at this point since we have *per* target versioning,
        // but at the time the original code was written, the version aligned everywhere.
        // See: rdar://147618136 (SwiftPM PIFBuilder — review how we compute the Swift version for a given target).
        let packageSwiftLanguageVersion = declaredSwiftVersions.first ?? manifest.toolsVersion.swiftLanguageVersion
        return packageSwiftLanguageVersion.rawValue
    }

    var pluginsAppliedToModule: [PackageGraph.ResolvedModule] {
        var pluginModules: [PackageGraph.ResolvedModule] = []

        for dependency in self.dependencies {
            switch dependency {
            case .module(let moduleDependency, _):
                if moduleDependency.type == .plugin {
                    pluginModules.append(moduleDependency)
                }
            case .product(let productDependency, _):
                let productPlugins = productDependency.modules.filter { $0.type == .plugin }
                pluginModules.append(contentsOf: productPlugins)
            }
        }
        return pluginModules
    }

    func productRepresentingDependencyOfBuildPlugin(in mainModuleProducts: [ResolvedProduct]) -> ResolvedProduct? {
        mainModuleProducts.only { (mainModuleProduct: ResolvedProduct) -> Bool in
            // NOTE: We can't use the 'id' here as we need to explicitly ignore the build triple because our build
            // triple will be '.tools' while the target we want to depend on will have a build triple of '.destination'.
            // See for more details:
            // https://github.com/swiftlang/swift-package-manager/commit/b22168ec41061ddfa3438f314a08ac7a776bef7a.
            return mainModuleProduct.mainModule!.packageIdentity == self.packageIdentity &&
                mainModuleProduct.mainModule!.name == self.name
            // Intentionally ignore the build triple!
        }
    }

    struct AllBuildSettings {
        typealias BuildSettingsByPlatform =
            [ProjectModel.BuildSettings.Platform?: [BuildSettings.Declaration: [String]]]

        /// Target-specific build settings declared in the manifest and that apply to the target itself.
        var targetSettings: [BuildConfiguration: BuildSettingsByPlatform] = [:]

        /// Target-specific build settings that should be imparted to client targets (packages and projects).
        var impartedSettings: BuildSettingsByPlatform = [:]
    }

    /// Target-specific build settings declared in the manifest and that apply to the target itself.
    ///
    /// Collect the build settings defined in the package manifest.
    /// Some of them apply *only* to the target itself, while others are also imparted to clients.
    /// Note that the platform is *optional*; unconditional settings have no platform condition.
    var allBuildSettings: AllBuildSettings {
        var allSettings = AllBuildSettings()

        for (declaration, settingsAssigments) in self.underlying.buildSettings.assignments {
            for settingAssignment in settingsAssigments {
                // Create a build setting value; in some cases there
                // isn't a direct mapping to Swift Build build settings.
                let pifDeclaration: BuildSettings.Declaration
                let values: [String]
                switch declaration {
                case .LINK_FRAMEWORKS:
                    pifDeclaration = .OTHER_LDFLAGS
                    values = settingAssignment.values.flatMap { ["-framework", $0] }
                case .LINK_LIBRARIES:
                    pifDeclaration = .OTHER_LDFLAGS
                    values = settingAssignment.values.map { "-l\($0)" }
                case .HEADER_SEARCH_PATHS:
                    pifDeclaration = .HEADER_SEARCH_PATHS
                    values = settingAssignment.values.map { self.sourceDirAbsolutePath.pathString + "/" + $0 }
                default:
                    pifDeclaration = ProjectModel.BuildSettings.Declaration(from: declaration)
                    values = settingAssignment.values
                }

                // TODO: We are currently ignoring package traits (see rdar://138149810).
                let (platforms, configurations, _) = settingAssignment.conditions.splitIntoConcreteConditions

                for platform in platforms {
                    let pifPlatform = platform.map { ProjectModel.BuildSettings.Platform(from: $0) }

                    if pifDeclaration == .OTHER_LDFLAGS {
                        var settingsByDeclaration: [ProjectModel.BuildSettings.Declaration: [String]]

                        settingsByDeclaration = allSettings.impartedSettings[pifPlatform] ?? [:]
                        settingsByDeclaration[pifDeclaration, default: []].append(contentsOf: values)

                        allSettings.impartedSettings[pifPlatform] = settingsByDeclaration
                    }

                    for configuration in configurations {
                        var settingsByDeclaration: [ProjectModel.BuildSettings.Declaration: [String]]
                        settingsByDeclaration = allSettings.targetSettings[configuration]?[pifPlatform] ?? [:]

                        if declaration.allowsMultipleValues {
                            settingsByDeclaration[pifDeclaration, default: []].append(contentsOf: values)
                        } else {
                            settingsByDeclaration[pifDeclaration] = values.only.flatMap { [$0] } ?? []
                        }

                        allSettings.targetSettings[configuration, default: [:]][pifPlatform] = settingsByDeclaration
                    }
                }
            }
        }
        return allSettings
    }
}

/// Specialization of `Module` for "system module" targets,
/// i.e. those that just provide information about a library already on the system.
extension SystemLibraryModule {
    /// Absolute path of the *module-map* file.
    var modulemapFileAbsolutePath: String {
        self.moduleMapPath.pathString
    }

    /// Returns pkgConfig result for a system library target.
    func pkgConfig(
        package: PackageGraph.ResolvedPackage,
        observabilityScope: ObservabilityScope
    ) throws -> (cFlags: [String], libs: [String]) {
        let diagnostics = ThreadSafeArrayStore<Basics.Diagnostic>()
        defer {
            for diagnostic in diagnostics.get() {
                observabilityScope.emit(diagnostic)
            }
        }

        let pkgConfigParsingScope = ObservabilitySystem { _, diagnostic in
            diagnostics.append(diagnostic)
        }.topScope.makeChildScope(description: "PkgConfig") {
            var packageMetadata = ObservabilityMetadata.packageMetadata(
                identity: package.identity,
                kind: package.manifest.packageKind
            )
            packageMetadata.moduleName = self.name
            return packageMetadata
        }

        let brewPath = if FileManager.default.fileExists(atPath: "/opt/brew") {
            "/opt/brew" // Legacy path for Homebrew.
        } else if FileManager.default.fileExists(atPath: "/opt/homebrew") {
            "/opt/homebrew" // Default path for Homebrew on Apple Silicon.
        } else {
            "/usr/local" // Fallback to default path for Homebrew.
        }

        let emptyPkgConfig: (cFlags: [String], libs: [String]) = ([], [])

        let brewPrefix = try? AbsolutePath(
            validating: UserDefaults.standard.string(forKey: "IDEHomebrewPrefixPath") ?? brewPath
        )
        guard let brewPrefix else { return emptyPkgConfig }

        let pkgConfigResult = try? pkgConfigArgs(
            for: self,
            pkgConfigDirectories: [],
            brewPrefix: brewPrefix,
            fileSystem: localFileSystem,
            observabilityScope: pkgConfigParsingScope
        )
        guard let pkgConfigResult else { return emptyPkgConfig }

        let pkgConfig = (
            cFlags: pkgConfigResult.flatMap(\.cFlags),
            libs: pkgConfigResult.flatMap(\.libs)
        )
        return pkgConfig
    }
}

// MARK: - SwiftPM PackageGraph.ResolvedProduct Helpers

extension PackageGraph.ResolvedProduct {
    /// Returns the main module (aka, target) of this product, if any.
    var mainModule: PackageGraph.ResolvedModule? {
        self.modules.only { $0.type == self.type.targetType }
    }

    /// Returns the other modules of this product.
    var otherModules: [PackageGraph.ResolvedModule] {
        modules.filter { $0.isSourceModule && $0.type != self.type.targetType }
    }

    /// These are the kinds of products for whom one module is special
    /// (e.g., executables have one executable module, test bundles have one test module, etc).
    var isMainModuleProduct: Bool {
        switch self.type {
        case .executable, .snippet, .test:
            true
        case .library, .macro, .plugin:
            false
        }
    }

    /// Is this a *system library* product?
    var isSystemLibraryProduct: Bool {
        if self.modules.only?.type == .systemModule {
            true
        } else {
            false
        }
    }

    var isExecutable: Bool {
        switch self.type {
        case .executable, .snippet:
            true
        case .library, .test, .plugin, .macro:
            false
        }
    }

    var isBinaryOnlyExecutableProduct: Bool {
        self.isExecutable && !self.hasSourceTargets
    }

    var hasSourceTargets: Bool {
        self.modules.anySatisfy { !$0.isBinary }
    }

    /// Returns the corresponding *system library* module, if this is a system library product.
    var systemModule: SystemLibraryModule? {
        guard self.isSystemLibraryProduct else { return nil }
        return (self.modules.only?.underlying as! SystemLibraryModule)
    }

    /// Returns the corresponding *plugin* module, if this is a plugin product.
    var pluginModules: [PackageModel.PluginModule]? {
        guard self.type == .plugin else { return nil }
        return self.modules.compactMap { $0.underlying as? PackageModel.PluginModule }
    }

    var c99name: String {
        self.name.spm_mangledToC99ExtendedIdentifier()
    }

    var libraryType: ProductType.LibraryType? {
        switch self.type {
        case .library(let libraryType):
            libraryType
        default:
            nil
        }
    }

    /// Shoud we link this product dependency?
    var isLinkable: Bool {
        switch self.type {
        case .library, .executable, .snippet, .test, .macro:
            true
        case .plugin:
            false
        }
    }

    /// Is this product dependency automatic?
    var isAutomatic: Bool {
        self.type == .library(.automatic)
    }

    var usesUnsafeFlags: Bool {
        get throws {
            try self.recursiveModuleDependencies().contains { $0.underlying.usesUnsafeFlags }
        }
    }
}

extension PackageGraph.ResolvedModule {
    func recursivelyTraverseDependencies(with block: (ResolvedModule.Dependency) -> Void) {
        [self].recursivelyTraverseDependencies(with: block)
    }
}

extension Collection<PackageGraph.ResolvedModule> {
    /// Recursively applies a block to each of the *dependencies* of the given module, in topological sort order.
    /// Each module or product dependency is visited only once.
    func recursivelyTraverseDependencies(with block: (ResolvedModule.Dependency) -> Void) {
        var moduleNamesSeen: Set<String> = []
        var productNamesSeen: Set<String> = []

        func visitDependency(_ dependency: ResolvedModule.Dependency) {
            switch dependency {
            case .module(let moduleDependency, _):
                let (unseenModule, _) = moduleNamesSeen.insert(moduleDependency.name)
                guard unseenModule else { return }

                if moduleDependency.underlying.type != .macro {
                    for dependency in moduleDependency.dependencies {
                        visitDependency(dependency)
                    }
                }
                block(dependency)

            case .product(let productDependency, let conditions):
                let (unseenProduct, _) = productNamesSeen.insert(productDependency.name)
                guard unseenProduct && !productDependency.isBinaryOnlyExecutableProduct else { return }
                block(dependency)

                // We need to visit any binary modules to be able to add direct references to them to any client
                // targets.
                // This is needed so that XCFramework processing always happens *prior* to building any client targets.
                for moduleDependency in productDependency.modules where moduleDependency.isBinary {
                    if moduleNamesSeen.contains(moduleDependency.name) { continue }
                    block(.module(moduleDependency, conditions: conditions))
                }
            }
        }

        for dependency in self.flatMap(\.dependencies) {
            visitDependency(dependency)
        }
    }
}

// MARK: - SwiftPM TSCUtility Helpers

extension TSCUtility.Version {
    var isPrerelease: Bool {
        !self.prereleaseIdentifiers.isEmpty
    }

    var hasBuildMetadata: Bool {
        !self.buildMetadataIdentifiers.isEmpty
    }

    var stringRepresentation: String {
        self.description
    }
}

// MARK: - Swift Build ProjectModel Helpers

/// Helpful for logging.
extension ProjectModel.GUID: @retroactive CustomStringConvertible  {
    public var description: String {
        value
    }
}

extension ProjectModel.BuildSettings {
    subscript(_ setting: MultipleValueSetting, default defaultValue: [String]) -> [String] {
        get { self[setting] ?? defaultValue }
        set { self[setting] = newValue }
    }
}

/// Helpers for building custom PIF targets by `PackagePIFBuilder` clients.
extension ProjectModel.Project {
    @discardableResult
    public mutating func addTarget(
        packageProductName: String,
        productType: ProjectModel.Target.ProductType
    ) throws -> WritableKeyPath<ProjectModel.Project, ProjectModel.Target> {
        let targetKeyPath = try self.addTarget { _ in
            ProjectModel.Target(
                id: PackagePIFBuilder.targetGUID(forProductName: packageProductName),
                productType: productType,
                name: packageProductName,
                productName: packageProductName
            )
        }
        return targetKeyPath
    }

    @discardableResult
    public mutating func addTarget(
        packageModuleName: String,
        productType: ProjectModel.Target.ProductType
    ) throws -> WritableKeyPath<ProjectModel.Project, ProjectModel.Target> {
        let targetKeyPath = try self.addTarget { _ in
            ProjectModel.Target(
                id: PackagePIFBuilder.targetGUID(forModuleName: packageModuleName),
                productType: productType,
                name: packageModuleName,
                productName: packageModuleName
            )
        }
        return targetKeyPath
    }
}

extension ProjectModel.BuildSettings {
    /// Internal helper function that appends list of string values to a declaration.
    /// If a platform is specified, then the values are appended to the `platformSpecificSettings`,
    /// otherwise they are appended to the platform-neutral settings.
    ///
    /// Note that this restricts the settings that can be set by this function to those that can have platform-specific
    /// values, i.e. those in `ProjectModel.BuildSettings.Declaration`. If a platform is specified,
    /// it must be one of the known platforms in `ProjectModel.BuildSettings.Platform`.
    mutating func append(values: [String], to setting: Declaration, platform: Platform? = nil) {
        // This dichotomy is quite unfortunate but that's currently the underlying model in ProjectModel.BuildSettings.
        if let platform {
            switch setting {
            case .FRAMEWORK_SEARCH_PATHS,
                 .GCC_PREPROCESSOR_DEFINITIONS,
                 .HEADER_SEARCH_PATHS,
                 .OTHER_CFLAGS,
                 .OTHER_CPLUSPLUSFLAGS,
                 .OTHER_LDFLAGS,
                 .OTHER_SWIFT_FLAGS,
                 .SWIFT_ACTIVE_COMPILATION_CONDITIONS:
                // Appending implies the setting is resilient to having ["$(inherited)"]
                self.platformSpecificSettings[platform]![setting]!.append(contentsOf: values)

            case .SWIFT_VERSION:
                self.platformSpecificSettings[platform]![setting] = values // We are not resilient to $(inherited).

            case .ARCHS, .IPHONEOS_DEPLOYMENT_TARGET, .SPECIALIZATION_SDK_OPTIONS:
                fatalError("Unexpected BuildSettings.Declaration: \(setting)")
            }
        } else {
            switch setting {
            case .FRAMEWORK_SEARCH_PATHS,
                 .GCC_PREPROCESSOR_DEFINITIONS,
                 .HEADER_SEARCH_PATHS,
                 .OTHER_CFLAGS,
                 .OTHER_CPLUSPLUSFLAGS,
                 .OTHER_LDFLAGS,
                 .OTHER_SWIFT_FLAGS,
                 .SWIFT_ACTIVE_COMPILATION_CONDITIONS:
                let multipleSetting = MultipleValueSetting(from: setting)!
                self[multipleSetting, default: ["$(inherited)"]].append(contentsOf: values)

            case .SWIFT_VERSION:
                self[.SWIFT_VERSION] = values.only.unwrap(orAssert: "Invalid values for 'SWIFT_VERSION': \(values)")

            case .ARCHS, .IPHONEOS_DEPLOYMENT_TARGET, .SPECIALIZATION_SDK_OPTIONS:
                fatalError("Unexpected BuildSettings.Declaration: \(setting)")
            }
        }
    }
}

extension ProjectModel.BuildSettings.MultipleValueSetting {
    init?(from declaration: ProjectModel.BuildSettings.Declaration) {
        switch declaration {
        case .GCC_PREPROCESSOR_DEFINITIONS:
            self = .GCC_PREPROCESSOR_DEFINITIONS
        case .FRAMEWORK_SEARCH_PATHS:
            self = .FRAMEWORK_SEARCH_PATHS
        case .HEADER_SEARCH_PATHS:
            self = .HEADER_SEARCH_PATHS
        case .OTHER_CFLAGS:
            self = .OTHER_CFLAGS
        case .OTHER_CPLUSPLUSFLAGS:
            self = .OTHER_CPLUSPLUSFLAGS
        case .OTHER_LDFLAGS:
            self = .OTHER_LDFLAGS
        case .OTHER_SWIFT_FLAGS:
            self = .OTHER_SWIFT_FLAGS
        case .SPECIALIZATION_SDK_OPTIONS:
            self = .SPECIALIZATION_SDK_OPTIONS
        case .SWIFT_ACTIVE_COMPILATION_CONDITIONS:
            self = .SWIFT_ACTIVE_COMPILATION_CONDITIONS
        case .ARCHS, .IPHONEOS_DEPLOYMENT_TARGET, .SWIFT_VERSION:
            return nil
        }
    }
}

extension ProjectModel.BuildSettings.Platform {
    init(from platform: PackageModel.Platform) {
        self = switch platform {
        case .macOS: .macOS
        case .macCatalyst: .macCatalyst
        case .iOS: .iOS
        case .tvOS: .tvOS
        case .watchOS: .watchOS
        case .visionOS: .xrOS
        case .driverKit: .driverKit
        case .linux: .linux
        case .android: .android
        case .windows: .windows
        case .wasi: .wasi
        case .openbsd: .openbsd
        case .freebsd: .freebsd
        default: preconditionFailure("Unexpected platform: \(platform.name)")
        }
    }
}

extension ProjectModel.BuildSettings {
    /// Configure necessary settings for a dynamic library/framework.
    mutating func configureDynamicSettings(
        productName: String,
        targetName: String,
        executableName: String,
        packageIdentity: PackageIdentity,
        packageName: String?,
        createDylibForDynamicProducts: Bool,
        installPath: String,
        delegate: PackagePIFBuilder.BuildDelegate
    ) {
        self[.TARGET_NAME] = targetName
        self[.PRODUCT_NAME] = createDylibForDynamicProducts ? productName : executableName
        self[.PRODUCT_MODULE_NAME] = productName
        self[.PRODUCT_BUNDLE_IDENTIFIER] = "\(packageIdentity).\(productName)".spm_mangledToBundleIdentifier()
        self[.EXECUTABLE_NAME] = executableName
        self[.CLANG_ENABLE_MODULES] = "YES"
        self[.SWIFT_PACKAGE_NAME] = packageName ?? nil

        if !createDylibForDynamicProducts {
            self[.GENERATE_INFOPLIST_FILE] = "YES"
            // If the built framework is named same as one of the target in the package,
            // it can be picked up automatically during indexing since the build system always adds a -F flag
            // to the built products dir.
            // To avoid this problem, we build all package frameworks in a subdirectory.
            self[.TARGET_BUILD_DIR] = "$(TARGET_BUILD_DIR)/PackageFrameworks"

            // Set the project and marketing version for the framework because the app store requires these to be
            // present.
            // The AppStore requires bumping the project version when ingesting new builds but that's for top-level apps
            // and not frameworks embedded inside it.
            self[.MARKETING_VERSION] = "1.0" // Version
            self[.CURRENT_PROJECT_VERSION] = "1" // Build
        }

        // Might set install path depending on build delegate.
        if delegate.shouldSetInstallPathForDynamicLib(productName: productName) {
            self[.SKIP_INSTALL] = "NO"
            self[.INSTALL_PATH] = installPath
        }
    }
}

extension ProjectModel.BuildSettings.Declaration {
    init(from declaration: PackageModel.BuildSettings.Declaration) {
        self = switch declaration {
        // Swift.
        case .SWIFT_ACTIVE_COMPILATION_CONDITIONS:
            .SWIFT_ACTIVE_COMPILATION_CONDITIONS
        case .OTHER_SWIFT_FLAGS:
            .OTHER_SWIFT_FLAGS
        case .SWIFT_VERSION:
            .SWIFT_VERSION
        // C family.
        case .GCC_PREPROCESSOR_DEFINITIONS:
            .GCC_PREPROCESSOR_DEFINITIONS
        case .HEADER_SEARCH_PATHS:
            .HEADER_SEARCH_PATHS
        case .OTHER_CFLAGS:
            .OTHER_CFLAGS
        case .OTHER_CPLUSPLUSFLAGS:
            .OTHER_CPLUSPLUSFLAGS
        // Linker.
        case .OTHER_LDFLAGS:
            .OTHER_LDFLAGS
        case .LINK_LIBRARIES, .LINK_FRAMEWORKS:
            preconditionFailure("Should not be reached")
        default:
            preconditionFailure("Unexpected BuildSettings.Declaration: \(declaration.name)")
        }
    }
}

// MARK: - ObservabilityScope Helpers

extension ObservabilityScope {
    /// Logs an informational PIF message (intended for developers, not end users).
    func logPIF(
        _ severity: Diagnostic.Severity = .debug,
        indent: UInt = 0,
        _ message: String,
        sourceFile: StaticString = #fileID,
        sourceLine: UInt = #line
    ) {
        var metadata = ObservabilityMetadata()
        metadata.sourceLocation = SourceLocation(sourceFile, sourceLine)

        let indentation = String(repeating: "  ", count: Int(indent))
        let message = "PIF: \(indentation)\(message)"
        
        let diagnostic = Diagnostic(severity: severity, message: message, metadata: metadata)
        self.emit(diagnostic)
    }
}

extension ObservabilityMetadata {
    public var sourceLocation: SourceLocation? {
        get {
            self[SourceLocationKey.self]
        }
        set {
            self[SourceLocationKey.self] = newValue
        }
    }

    private enum SourceLocationKey: Key {
        typealias Value = SourceLocation
    }
}

public struct SourceLocation: Sendable {
    public let file: StaticString
    public let line: UInt

    public init(_ file: StaticString, _ line: UInt) {
        precondition(file.description.hasContent)
        
        self.file = file
        self.line = line
    }
}

// MARK: - General Helpers

extension SourceControlURL {
    init(fileURLWithPath path: AbsolutePath) {
        let fileURL = Foundation.URL(fileURLWithPath: path.pathString)
        self.init(fileURL.description)
    }
}

extension String {
    /// Returns the path extension from a `String`.
    var pathExtension: String {
        (self as NSString).pathExtension
    }
}

extension Optional {
    func unwrap(
        orAssert message: @autoclosure () -> String,
        file: StaticString = #file,
        line: UInt = #line
    ) -> Wrapped {
        if let unwrapped = self {
            unwrapped
        } else {
            fatalError(message(), file: file, line: line)
        }
    }

    @discardableResult
    mutating func lazilyInitialize(
        _ initializer: () -> Wrapped
    ) -> Wrapped {
        if let result = self {
            return result
        } else {
            let result = initializer()
            self = .some(result)
            return result
        }
    }

    @discardableResult
    mutating func lazilyInitializeAndMutate<R>(
        initialValue initializer: @autoclosure () -> Wrapped,
        mutator: (inout Wrapped) throws -> R
    ) rethrows -> R {
        if self == nil {
            self = .some(initializer())
        }
        return try mutator(&self!)
    }
}

extension Sequence {
    /// Evaluates `predicate` on each element in the collection.
    /// If exactly 1 element returns `true` return that element.
    /// Returns the *only* element in the sequence satisfying the specified predicate.
    ///
    /// **Complexity**.  O(n), where n is the length of the sequence.
    func only(where predicate: (Element) throws -> Bool) rethrows -> Element? {
        var match: Element?
        for candidate in self {
            if try predicate(candidate) {
                if match == nil {
                    match = candidate
                } else {
                    return nil
                }
            }
        }
        return match
    }
}

extension Collection {
    /// Positive sense of `isEmpty`.
    var hasContent: Bool {
        !self.isEmpty
    }

    var only: Element? {
        (count == 1) ? first : nil
    }

    func anySatisfy(_ predicate: (Element) throws -> Bool) rethrows -> Bool {
        try contains(where: predicate)
    }

    /// For example: `people.sorted(on: \.name)`.
    func sorted(on projection: (Element) -> some Comparable) -> [Element] {
        self.sorted(on: projection, by: <)
    }

    /// For example: `people.sorted(on: \.name, comparator: >)`.
    func sorted<T>(on projection: (Element) -> T, by comparator: (T, T) -> Bool) -> [Element] {
        self.sorted { lhs, rhs in
            comparator(projection(lhs), projection(rhs))
        }
    }
}

extension Array {
    func prepending(_ newElement: Element) -> [Element] {
        [newElement] + self
    }
}

extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if self.object(forKey: key) != nil {
            self.bool(forKey: key)
        } else {
            defaultValue
        }
    }
}

#endif
