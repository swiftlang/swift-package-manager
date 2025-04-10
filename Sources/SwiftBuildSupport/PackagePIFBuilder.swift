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

import struct Basics.AbsolutePath
import struct Basics.SourceControlURL

import class PackageModel.Manifest
import class PackageModel.Package
import struct PackageModel.Platform
import struct PackageModel.PlatformVersion
import class PackageModel.Product
import enum PackageModel.ProductType
import struct PackageModel.Resource

import struct Basics.Diagnostic
import struct Basics.ObservabilityMetadata
import class Basics.ObservabilityScope
import struct PackageGraph.ModulesGraph
import struct PackageGraph.ResolvedModule
import struct PackageGraph.ResolvedPackage

#if canImport(SwiftBuild)

import enum SwiftBuild.ProjectModel

typealias GUID = SwiftBuild.ProjectModel.GUID
typealias BuildFile = SwiftBuild.ProjectModel.BuildFile
typealias BuildConfig = SwiftBuild.ProjectModel.BuildConfig
typealias BuildSettings = SwiftBuild.ProjectModel.BuildSettings
typealias FileReference = SwiftBuild.ProjectModel.FileReference

/// A builder for generating the PIF object from a package.
public final class PackagePIFBuilder {
    let modulesGraph: ModulesGraph
    private let package: ResolvedPackage

    /// Contains the package declarative specification.
    let packageManifest: PackageModel.Manifest // FIXME: Can't we just use `package.manifest` instead? —— Paulo

    /// The built PIF project object.
    public var pifProject: ProjectModel.Project {
        assert(self._pifProject != nil, "Call build() method to build the PIF first")
        return self._pifProject!
    }

    private var _pifProject: ProjectModel.Project?

    /// Scope for logging informational debug messages (intended for developers, not end users).
    let observabilityScope: ObservabilityScope

    /// Logs an informational message (intended for developers, not end users).
    func log(
        _ severity: Diagnostic.Severity,
        _ message: String,
        sourceFile: StaticString = #fileID,
        sourceLine: UInt = #line
    ) {
        self.observabilityScope.logPIF(severity, message, sourceFile: sourceFile, sourceLine: sourceLine)
    }

    unowned let delegate: BuildDelegate

    public protocol BuildDelegate: AnyObject {
        /// Is this the root package?
        var isRootPackage: Bool { get }

        // TODO: Maybe move these 3-4 properties to the `PIFBuilder.PIFBuilderParameters` struct.

        /// If a pure Swift package is open in the workspace.
        var hostsOnlyPackages: Bool { get }

        /// Returns `true` if the package is managed by the user
        /// (i.e., the user is allowed to modify its sources, package structure, etc).
        var isUserManaged: Bool { get }

        /// Whether or not this package is required by *branch* or *revision*.
        var isBranchOrRevisionBased: Bool { get }

        /// For executables — only executables for now — we check to see if there is a
        /// custom package product type provider that can provide this information.
        func customProductType(forExecutable product: PackageModel.Product) -> ProjectModel.Target.ProductType?

        /// Returns all *device family* IDs for all SDK variants.
        func deviceFamilyIDs() -> Set<Int>

        /// Have packages referenced by this workspace build for arm64e when building for iOS devices.
        var shouldiOSPackagesBuildForARM64e: Bool { get }

        /// Is the sandbox disabled for plug-in execution? It should be `false` by default.
        var isPluginExecutionSandboxingDisabled: Bool { get }

        /// Hook to customize the project-wide build settings.
        func configureProjectBuildSettings(_ buildSettings: inout ProjectModel.BuildSettings)

        /// Hook to customize source module build settings.
        func configureSourceModuleBuildSettings(
            sourceModule: PackageGraph.ResolvedModule,
            settings: inout ProjectModel.BuildSettings
        )

        /// Custom install path for the specified product, if any.
        func customInstallPath(product: PackageModel.Product) -> String?

        /// Custom executable name for the specified product, if any.
        func customExecutableName(product: PackageModel.Product) -> String?

        /// Custom library type for the specified product.
        func customLibraryType(product: PackageModel.Product) -> PackageModel.ProductType.LibraryType?

        /// Custom option for the specified platform.
        func customSDKOptions(forPlatform: PackageModel.Platform) -> [String]

        /// Create additional custom PIF targets after all targets have been built.
        func addCustomTargets(pifProject: ProjectModel.Project) throws -> [PackagePIFBuilder.ModuleOrProduct]

        /// Should we suppresses the specific product dependency, updating the provided build settings if necessary?
        /// The specified product may be in the same package or a different one.
        func shouldSuppressProductDependency(
            product: PackageModel.Product,
            buildSettings: inout ProjectModel.BuildSettings
        ) -> Bool

        /// Should we set the install path for a dynamic library/framework?
        func shouldSetInstallPathForDynamicLib(productName: String) -> Bool

        // FIXME: Let's try to replace `WritableKeyPath><_, Foo>` with `inout Foo` —— Paulo

        /// Provides additional configuration and files for the specified library product.
        func configureLibraryProduct(
            product: PackageModel.Product,
            target: WritableKeyPath<ProjectModel.Project, ProjectModel.Target>,
            additionalFiles: WritableKeyPath<ProjectModel.Group, ProjectModel.Group>
        )

        /// The design intention behind this is to set a value for `watchOS`, `tvOS`, and `visionOS`
        /// that "follows" the aligned iOS version if they are not explicitly set.
        ///
        /// Prior to this enhancement, it was common to find packages which worked perfectly fine on `watchOS`
        /// aside from the one issue where developers failed to specify the correct deployment target.
        ///
        /// See: rdar://144661020 (SwiftPM PIFBuilder — compute unset deployment targets).
        func suggestAlignedPlatformVersionGiveniOSVersion(platform: PackageModel.Platform, iOSVersion: PlatformVersion)
            -> String?

        /// Validates the specified macro fingerprint. Each remote package has a fingerprint.
        func validateMacroFingerprint(for macroModule: ResolvedModule) -> Bool
    }

    /// Records the results of applying build tool plugins to modules in the package.
    let buildToolPluginResultsByTargetName: [String: PackagePIFBuilder.BuildToolPluginInvocationResult]

    /// Whether to create dynamic libraries for dynamic products.
    ///
    /// This tracks removing this *user default* once clients stop relying on this implementation detail:
    /// * <rdar://56889224> Remove IDEPackageSupportCreateDylibsForDynamicProducts.
    let createDylibForDynamicProducts: Bool

    /// Package display version, if any (i.e., it can be a version, branch or a git ref).
    let packageDisplayVersion: String?

    /// Whether to suppress warnings from compilers, linkers, and other build tools for package dependencies.
    private var suppressWarningsForPackageDependencies: Bool {
        UserDefaults.standard.bool(forKey: "SuppressWarningsForPackageDependencies", defaultValue: true)
    }

    /// Whether to skip running the static analyzer for package dependencies.
    private var skipStaticAnalyzerForPackageDependencies: Bool {
        UserDefaults.standard.bool(forKey: "SkipStaticAnalyzerForPackageDependencies", defaultValue: true)
    }

    public static func computePackageProductFrameworkName(productName: String) -> String {
        "\(productName)_\(String(productName.hash, radix: 16, uppercase: true))_PackageProduct"
    }

    public init(
        modulesGraph: ModulesGraph,
        resolvedPackage: ResolvedPackage,
        packageManifest: PackageModel.Manifest,
        delegate: PackagePIFBuilder.BuildDelegate,
        buildToolPluginResultsByTargetName: [String: BuildToolPluginInvocationResult],
        createDylibForDynamicProducts: Bool = false,
        packageDisplayVersion: String?,
        observabilityScope: ObservabilityScope
    ) {
        self.package = resolvedPackage
        self.packageManifest = packageManifest
        self.modulesGraph = modulesGraph
        self.delegate = delegate
        self.buildToolPluginResultsByTargetName = buildToolPluginResultsByTargetName
        self.createDylibForDynamicProducts = createDylibForDynamicProducts
        self.packageDisplayVersion = packageDisplayVersion
        self.observabilityScope = observabilityScope
    }

    /// Build an empty PIF project.
    public func buildEmptyPIF() {
        self._pifProject = PackagePIFBuilder.buildEmptyPIF(package: self.package.underlying)
    }

    /// Build an empty PIF project for the specified `Package`.

    public class func buildEmptyPIF(package: PackageModel.Package) -> ProjectModel.Project {
        self.buildEmptyPIF(
            id: "PACKAGE:\(package.identity)",
            path: package.manifest.path.pathString,
            projectDir: package.path.pathString,
            name: package.name,
            developmentRegion: package.manifest.defaultLocalization
        )
    }

    /// Build an empty PIF project.
    public class func buildEmptyPIF(
        id: String,
        path: String,
        projectDir: String,
        name: String,
        developmentRegion: String? = nil
    ) -> ProjectModel.Project {
        var project = ProjectModel.Project(
            id: GUID(id),
            path: path,
            projectDir: projectDir,
            name: name,
            developmentRegion: developmentRegion
        )
        let settings = ProjectModel.BuildSettings()

        project.addBuildConfig { id in ProjectModel.BuildConfig(id: id, name: "Debug", settings: settings) }
        project.addBuildConfig { id in ProjectModel.BuildConfig(id: id, name: "Release", settings: settings) }

        return project
    }

    public func buildPlaceholderPIF(id: String, path: String, projectDir: String, name: String) -> ModuleOrProduct {
        var project = ProjectModel.Project(
            id: GUID(id),
            path: path,
            projectDir: projectDir,
            name: name
        )

        let projectSettings = ProjectModel.BuildSettings()

        project.addBuildConfig { id in ProjectModel.BuildConfig(id: id, name: "Debug", settings: projectSettings) }
        project.addBuildConfig { id in ProjectModel.BuildConfig(id: id, name: "Release", settings: projectSettings) }

        let targetKeyPath = try! project.addAggregateTarget { _ in
            ProjectModel.AggregateTarget(id: "PACKAGE-PLACEHOLDER:\(id)", name: id)
        }
        let targetSettings: ProjectModel.BuildSettings = self.package.underlying.packageBaseBuildSettings

        project[keyPath: targetKeyPath].common.addBuildConfig { id in
            ProjectModel.BuildConfig(id: id, name: "Debug", settings: targetSettings)
        }
        project[keyPath: targetKeyPath].common.addBuildConfig { id in
            ProjectModel.BuildConfig(id: id, name: "Release", settings: targetSettings)
        }

        self._pifProject = project

        let placeholderModule = ModuleOrProduct(
            type: .placeholder,
            name: name,
            moduleName: name,
            pifTarget: .aggregate(project[keyPath: targetKeyPath]),
            indexableFileURLs: [],
            headerFiles: [],
            linkedPackageBinaries: [],
            swiftLanguageVersion: nil,
            declaredPlatforms: nil,
            deploymentTargets: nil
        )
        return placeholderModule
    }

    // FIXME: Maybe break this up in a `ArtifactMetadata` protocol and two value types —— Paulo
    // Like `ProductMetadata` and also `ModuleMetadata`.

    /// Value type with information about a given PIF module or product.
    public struct ModuleOrProduct {
        public var type: ModuleOrProductType
        public var name: String
        public var moduleName: String?
        public var isDynamicLibraryVariant: Bool = false

        public var pifTarget: ProjectModel.BaseTarget?

        public var indexableFileURLs: [SourceControlURL]
        public var headerFiles: Set<AbsolutePath>
        public var linkedPackageBinaries: [LinkedPackageBinary]

        public var swiftLanguageVersion: String?

        public var declaredPlatforms: [PackageModel.Platform]?
        public var deploymentTargets: [PackageModel.Platform: String?]?
    }

    public struct LinkedPackageBinary {
        public let name: String
        public let packageName: String
        public let type: BinaryType

        @frozen
        public enum BinaryType {
            case product
            case target
        }

        public init(name: String, packageName: String, type: BinaryType) {
            self.name = name
            self.packageName = packageName
            self.type = type
        }
    }

    public enum ModuleOrProductType: String, Sendable, CustomStringConvertible {
        // Products.
        case application
        case staticArchive
        case objectFile
        case dynamicLibrary
        case framework
        case executable
        case unitTest
        case bundle
        case resourceBundle
        case packageProduct
        case commandPlugin
        case buildToolPlugin

        // Modules.
        case module
        case plugin
        case macro
        case placeholder

        public var description: String { rawValue }

        init(from pifProductType: ProjectModel.Target.ProductType) {
            self = switch pifProductType {
            case .application: .application
            case .staticArchive: .staticArchive
            case .objectFile: .objectFile
            case .dynamicLibrary: .dynamicLibrary
            case .framework: .framework
            case .executable: .executable
            case .unitTest: .unitTest
            case .bundle: .bundle
            case .packageProduct: .packageProduct
            case .hostBuildTool: fatalError("Unexpected hostBuildTool type")
            @unknown default:
                fatalError()
            }
        }
    }

    /// Build the PIF.
    @discardableResult
    public func build() throws -> [ModuleOrProduct] {
        self.log(
            .info,
            "Building PIF project for package '\(self.package.identity)' " +
            "(\(package.products.count) products, \(package.modules.count) modules)"
        )

        var projectBuilder = PackagePIFProjectBuilder(createForPackage: package, builder: self)
        self.addProjectBuildSettings(&projectBuilder)

        //
        // Construct PIF *targets* (for modules, products, and test bundles) based on the contents
        // of the parsed package. These PIF targets will be sent down to Swift Build.
        //
        // We also track all constructed objects as `ModuleOrProduct` value for easy introspection by clients.
        // In SwiftPM a product is a codeless entity with a reference to the modules(s) that contains the
        // implementation. In order to avoid creating two ModuleOrProducts for each product in the package,
        // the logic below creates a single unified ModuleOrProduct from the combination of a product
        // and the single target that contains its implementation.
        //
        // Products. SwiftPM considers unit tests to be products, so in this discussion, the term *product*
        // refers to an *executable*, a *library*, or an *unit test*.
        //
        // Automatic libraries. The current implementation treats all automatic libraries as *static*;
        // in the future, we will want to do more holistic analysis so that the decision about whether
        // or not to build a separate dynamic library for a package library product takes into account
        // the structure of the client(s).
        //

        self.log(.debug, "Processing \(package.products.count) products:")
        
        // For each of the **products** in the package we create a corresponding `PIFTarget` of the appropriate type.
        for product in self.package.products {
            switch product.type {
            case .library(.static):
                let libraryType = self.delegate.customLibraryType(product: product.underlying) ?? .static
                try projectBuilder.makeLibraryProduct(product, type: libraryType)

            case .library(.dynamic):
                let libraryType = self.delegate.customLibraryType(product: product.underlying) ?? .dynamic
                try projectBuilder.makeLibraryProduct(product, type: libraryType)

            case .library(.automatic):
                // Check if this is a system library product.
                if product.isSystemLibraryProduct {
                    try projectBuilder.makeSystemLibraryProduct(product)
                } else {
                    // Otherwise, it is a regular library product.
                    let libraryType = self.delegate.customLibraryType(product: product.underlying) ?? .automatic
                    try projectBuilder.makeLibraryProduct(product, type: libraryType)
                }

            case .executable, .test:
                try projectBuilder.makeMainModuleProduct(product)

            case .plugin:
                try projectBuilder.makePluginProduct(product)

            case .snippet, .macro:
                break // TODO: Double-check what's going on here as we skip snippet modules too (rdar://147705448)
            }
        }

        self.log(.debug, "Processing \(package.modules.count) modules:")

        // For each of the **modules** in the package other than those that are the *main* module of a product
        // —— which we've already dealt with above —— we create a corresponding `PIFTarget` of the appropriate type.
        for module in self.package.modules {
            switch module.type {
            case .executable:
                try projectBuilder.makeTestableExecutableSourceModule(module)

            case .snippet:
                // Already handled as a product. Note that snippets don't need testable modules.
                break

            case .library:
                try projectBuilder.makeLibraryModule(module)

            case .systemModule:
                try projectBuilder.makeSystemLibraryModule(module)

            case .test:
                // Skip test module targets.
                // They will have been dealt with as part of the *products* to which they belong.
                break

            case .binary:
                // Skip binary module targets.
                break

            case .plugin:
                try projectBuilder.makePluginModule(module)

            case .macro:
                try projectBuilder.makeMacroModule(module)
            }
        }

        let customModulesAndProducts = try delegate.addCustomTargets(pifProject: projectBuilder.project)
        projectBuilder.builtModulesAndProducts.append(contentsOf: customModulesAndProducts)

        self._pifProject = projectBuilder.project
        return projectBuilder.builtModulesAndProducts
    }

    /// Configure the project-wide build settings.
    /// First we set those that are in common between the "Debug" and "Release" configurations, and then we set those
    /// that are different.
    private func addProjectBuildSettings(_ builder: inout PackagePIFProjectBuilder) {
        var settings = ProjectModel.BuildSettings()
        settings[.PRODUCT_NAME] = "$(TARGET_NAME)"
        settings[.SUPPORTED_PLATFORMS] = ["$(AVAILABLE_PLATFORMS)"]
        settings[.SKIP_INSTALL] = "YES"
        settings[.MACOSX_DEPLOYMENT_TARGET] = builder.deploymentTargets[.macOS] ?? nil
        settings[.IPHONEOS_DEPLOYMENT_TARGET] = builder.deploymentTargets[.iOS] ?? nil
        if let deploymentTarget_macCatalyst = builder.deploymentTargets[.macCatalyst] ?? nil {
            settings
                .platformSpecificSettings[.macCatalyst]![.IPHONEOS_DEPLOYMENT_TARGET] = [deploymentTarget_macCatalyst]
        }
        settings[.TVOS_DEPLOYMENT_TARGET] = builder.deploymentTargets[.tvOS] ?? nil
        settings[.WATCHOS_DEPLOYMENT_TARGET] = builder.deploymentTargets[.watchOS] ?? nil
        settings[.DRIVERKIT_DEPLOYMENT_TARGET] = builder.deploymentTargets[.driverKit] ?? nil
        settings[.XROS_DEPLOYMENT_TARGET] = builder.deploymentTargets[.visionOS] ?? nil
        settings[.DYLIB_INSTALL_NAME_BASE] = "@rpath"
        settings[.USE_HEADERMAP] = "NO"
        settings[.OTHER_SWIFT_FLAGS].lazilyInitializeAndMutate(initialValue: ["$(inherited)"]) { $0.append("-DXcode") }

        // TODO: Might be relevant to make customizable —— Paulo
        // (If we want to be extra careful with differences to the existing PIF in the SwiftPM.)
        settings[.OTHER_CFLAGS] = ["$(inherited)", "-DXcode"]

        if !self.delegate.isRootPackage {
            if self.suppressWarningsForPackageDependencies {
                settings[.SUPPRESS_WARNINGS] = "YES"
            }
            if self.skipStaticAnalyzerForPackageDependencies {
                settings[.SKIP_CLANG_STATIC_ANALYZER] = "YES"
            }
        }
        settings[.SWIFT_ACTIVE_COMPILATION_CONDITIONS]
            .lazilyInitializeAndMutate(initialValue: ["$(inherited)"]) { $0.append("SWIFT_PACKAGE") }
        settings[.GCC_PREPROCESSOR_DEFINITIONS] = ["$(inherited)", "SWIFT_PACKAGE"]
        settings[.CLANG_ENABLE_OBJC_ARC] = "YES"
        settings[.KEEP_PRIVATE_EXTERNS] = "NO"

        // We currently deliberately do not support Swift ObjC interface headers.
        settings[.SWIFT_INSTALL_OBJC_HEADER] = "NO"
        settings[.SWIFT_OBJC_INTERFACE_HEADER_NAME] = ""
        settings[.OTHER_LDRFLAGS] = []

        // Packages use the SwiftPM workspace's cache directory as a compiler working directory to maximize module
        // sharing.
        settings[.COMPILER_WORKING_DIRECTORY] = "$(WORKSPACE_DIR)"

        // Hook to customize the project-wide build settings.
        self.delegate.configureProjectBuildSettings(&settings)

        for (platform, platformOptions) in self.package.sdkOptions(delegate: self.delegate) {
            let pifPlatform = ProjectModel.BuildSettings.Platform(from: platform)
            settings.platformSpecificSettings[pifPlatform]![.SPECIALIZATION_SDK_OPTIONS]!
                .append(contentsOf: platformOptions)
        }

        let deviceFamilyIDs: Set<Int> = self.delegate.deviceFamilyIDs()
        settings[.TARGETED_DEVICE_FAMILY] = deviceFamilyIDs.sorted().map { String($0) }.joined(separator: ",")

        // This will add the XCTest related search paths automatically,
        // including the Swift overlays.
        settings[.ENABLE_TESTING_SEARCH_PATHS] = "YES"

        // Disable signing for all the things since there is no way
        // to configure signing information in packages right now.
        settings[.ENTITLEMENTS_REQUIRED] = "NO"
        settings[.CODE_SIGNING_REQUIRED] = "NO"
        settings[.CODE_SIGN_IDENTITY] = ""

        // If in a workspace that's set to build packages for arm64e, pass that along to Swift Build.
        if self.delegate.shouldiOSPackagesBuildForARM64e {
            settings.platformSpecificSettings[._iOSDevice]![.ARCHS] = ["arm64e"]
        }

        // Add the build settings that are specific to debug builds, and set those as the "Debug" configuration.
        var debugSettings = settings
        debugSettings[.COPY_PHASE_STRIP] = "NO"
        debugSettings[.DEBUG_INFORMATION_FORMAT] = "dwarf"
        debugSettings[.ENABLE_NS_ASSERTIONS] = "YES"
        debugSettings[.GCC_OPTIMIZATION_LEVEL] = "0"
        debugSettings[.ONLY_ACTIVE_ARCH] = "YES"
        debugSettings[.SWIFT_OPTIMIZATION_LEVEL] = "-Onone"
        debugSettings[.ENABLE_TESTABILITY] = "YES"
        debugSettings[.SWIFT_ACTIVE_COMPILATION_CONDITIONS, default: []].append(contentsOf: ["DEBUG"])
        debugSettings[.GCC_PREPROCESSOR_DEFINITIONS, default: ["$(inherited)"]].append(contentsOf: ["DEBUG=1"])
        builder.project.addBuildConfig { id in BuildConfig(id: id, name: "Debug", settings: debugSettings) }

        // Add the build settings that are specific to release builds, and set those as the "Release" configuration.
        var releaseSettings = settings
        releaseSettings[.COPY_PHASE_STRIP] = "YES"
        releaseSettings[.DEBUG_INFORMATION_FORMAT] = "dwarf-with-dsym"
        releaseSettings[.GCC_OPTIMIZATION_LEVEL] = "s"
        releaseSettings[.SWIFT_OPTIMIZATION_LEVEL] = "-Owholemodule"
        builder.project.addBuildConfig { id in BuildConfig(id: id, name: "Release", settings: releaseSettings) }
    }

    private enum SourceModuleType {
        case dynamicLibrary
        case staticLibrary
        case executable
        case macro
    }

    struct EmbedResourcesResult {
        let bundleName: String?
        let shouldGenerateBundleAccessor: Bool
        let shouldGenerateEmbedInCodeAccessor: Bool
    }

    struct Resource {
        let path: String
        let rule: PackageModel.Resource.Rule

        init(path: String, rule: PackageModel.Resource.Rule) {
            self.path = path
            self.rule = rule
        }

        init(_ resource: PackageModel.Resource) {
            self.path = resource.path.pathString
            self.rule = resource.rule
        }
    }
}

// MARK: - Helpers

extension PackagePIFBuilder.ModuleOrProduct {
    public init(
        type moduleOrProductType: PackagePIFBuilder.ModuleOrProductType,
        name: String,
        moduleName: String?,
        pifTarget: ProjectModel.BaseTarget?,
        indexableFileURLs: [SourceControlURL] = [],
        headerFiles: Set<AbsolutePath> = [],
        linkedPackageBinaries: [PackagePIFBuilder.LinkedPackageBinary] = [],
        swiftLanguageVersion: String? = nil,
        declaredPlatforms: [PackageModel.Platform]? = [],
        deploymentTargets: [PackageModel.Platform: String?]? = [:]
    ) {
        self.type = moduleOrProductType
        self.name = name
        self.moduleName = moduleName
        self.pifTarget = pifTarget
        self.indexableFileURLs = indexableFileURLs
        self.headerFiles = headerFiles
        self.linkedPackageBinaries = linkedPackageBinaries
        self.swiftLanguageVersion = swiftLanguageVersion
        self.declaredPlatforms = declaredPlatforms
        self.deploymentTargets = deploymentTargets
    }
}

enum PIFBuildingError: Error {
    case packageExtensionFeatureNotEnabled
}

extension PackagePIFBuilder.LinkedPackageBinary {
    init?(module: ResolvedModule, package: ResolvedPackage) {
        let packageName = package.manifest.displayName

        switch module.type {
        case .executable, .snippet, .test:
            self.init(name: module.name, packageName: packageName, type: .product)

        case .library, .binary, .macro:
            self.init(name: module.name, packageName: packageName, type: .target)

        case .systemModule, .plugin:
            return nil
        }
    }

    init?(dependency: ResolvedModule.Dependency, package: ResolvedPackage) {
        switch dependency {
        case .product(let producutDependency, _):
            guard producutDependency.hasSourceTargets else { return nil }
            self.init(name: producutDependency.name, packageName: package.name, type: .product)

        case .module(let moduleDependency, _):
            self.init(module: moduleDependency, package: package)
        }
    }
}

#endif
