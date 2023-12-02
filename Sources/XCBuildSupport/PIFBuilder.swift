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

import Foundation
import Basics
import PackageModel
import PackageLoading
import PackageGraph
import SPMBuildCore

import func TSCBasic.topologicalSort
import func TSCBasic.memoize

/// The parameters required by `PIFBuilder`.
struct PIFBuilderParameters {

    /// Whether or not build for testability is enabled.
    let enableTestability: Bool

    /// Whether to create dylibs for dynamic library products.
    let shouldCreateDylibForDynamicProducts: Bool

    /// The path to the library directory of the active toolchain.
    let toolchainLibDir: AbsolutePath

    /// An array of paths to search for pkg-config `.pc` files.
    let pkgConfigDirectories: [AbsolutePath]

    /// The toolchain's SDK root path.
    let sdkRootPath: AbsolutePath?
}

/// PIF object builder for a package graph.
public final class PIFBuilder {

    /// Name of the PIF target aggregating all targets (excluding tests).
    public static let allExcludingTestsTargetName = "AllExcludingTests"

    /// Name of the PIF target aggregating all targets (including tests).
    public static let allIncludingTestsTargetName = "AllIncludingTests"

    /// The package graph to build from.
    let graph: PackageGraph

    /// The parameters used to configure the PIF.
    let parameters: PIFBuilderParameters

    /// The ObservabilityScope to emit diagnostics to.
    let observabilityScope: ObservabilityScope

    /// The file system to read from.
    let fileSystem: FileSystem

    private var pif: PIF.TopLevelObject?

    /// Creates a `PIFBuilder` instance.
    /// - Parameters:
    ///   - graph: The package graph to build from.
    ///   - parameters: The parameters used to configure the PIF.
    ///   - fileSystem: The file system to read from.
    ///   - observabilityScope: The ObservabilityScope to emit diagnostics to.
    init(
        graph: PackageGraph,
        parameters: PIFBuilderParameters,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) {
        self.graph = graph
        self.parameters = parameters
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope.makeChildScope(description: "PIF Builder")
    }

    /// Generates the PIF representation.
    /// - Parameters:
    ///   - prettyPrint: Whether to return a formatted JSON.
    /// - Returns: The package graph in the JSON PIF format.
    func generatePIF(
        prettyPrint: Bool = true,
        preservePIFModelStructure: Bool = false
    ) throws -> String {
        let encoder = prettyPrint ? JSONEncoder.makeWithDefaults() : JSONEncoder()

        if !preservePIFModelStructure {
            encoder.userInfo[.encodeForXCBuild] = true
        }

        let topLevelObject = try self.construct()

        // Sign the pif objects before encoding it for XCBuild.
        try PIF.sign(topLevelObject.workspace)

        let pifData = try encoder.encode(topLevelObject)
        return String(decoding: pifData, as: UTF8.self)
    }

    /// Constructs a `PIF.TopLevelObject` representing the package graph.
    public func construct() throws -> PIF.TopLevelObject {
        try memoize(to: &pif) {
            let rootPackage = graph.rootPackages[0]

            let sortedPackages = graph.packages.sorted { $0.manifest.displayName < $1.manifest.displayName } // TODO: use identity instead?
            var projects: [PIFProjectBuilder] = try sortedPackages.map { package in
                try PackagePIFProjectBuilder(
                    package: package,
                    parameters: parameters,
                    fileSystem: self.fileSystem,
                    observabilityScope: self.observabilityScope
                )
            }

            projects.append(AggregatePIFProjectBuilder(projects: projects))

            let workspace = PIF.Workspace(
                guid: "Workspace:\(rootPackage.path.pathString)",
                name: rootPackage.manifest.displayName,  // TODO: use identity instead?
                path: rootPackage.path,
                projects: try projects.map { try $0.construct() }
            )

            return PIF.TopLevelObject(workspace: workspace)
        }
    }

    // Convenience method for generating PIF.
    public static func generatePIF(buildParameters: BuildParameters, packageGraph: PackageGraph, fileSystem: FileSystem, observabilityScope: ObservabilityScope, preservePIFModelStructure: Bool) throws -> String {
        let parameters = PIFBuilderParameters(buildParameters)
        let builder = Self.init(
            graph: packageGraph,
            parameters: parameters,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )
        return try builder.generatePIF(preservePIFModelStructure: preservePIFModelStructure)
    }
}

class PIFProjectBuilder {
    let groupTree: PIFGroupBuilder
    private(set) var targets: [PIFBaseTargetBuilder]
    private(set) var buildConfigurations: [PIFBuildConfigurationBuilder]

    @DelayedImmutable
    var guid: PIF.GUID
    @DelayedImmutable
    var name: String
    @DelayedImmutable
    var path: AbsolutePath
    @DelayedImmutable
    var projectDirectory: AbsolutePath
    @DelayedImmutable
    var developmentRegion: String

    fileprivate init() {
        groupTree = PIFGroupBuilder(path: "")
        targets = []
        buildConfigurations = []
    }

    /// Creates and adds a new empty build configuration, i.e. one that does not initially have any build settings.
    /// The name must not be empty and must not be equal to the name of any existing build configuration in the target.
    @discardableResult
    func addBuildConfiguration(
        name: String,
        settings: PIF.BuildSettings = PIF.BuildSettings(),
        impartedBuildProperties: PIF.ImpartedBuildProperties = PIF.ImpartedBuildProperties(settings: PIF.BuildSettings())
    ) -> PIFBuildConfigurationBuilder {
        let builder = PIFBuildConfigurationBuilder(name: name, settings: settings, impartedBuildProperties: impartedBuildProperties)
        buildConfigurations.append(builder)
        return builder
    }

    /// Creates and adds a new empty target, i.e. one that does not initially have any build phases. If provided,
    /// the ID must be non-empty and unique within the PIF workspace; if not provided, an arbitrary guaranteed-to-be-
    /// unique identifier will be assigned. The name must not be empty and must not be equal to the name of any existing
    /// target in the project.
    @discardableResult
    func addTarget(
        guid: PIF.GUID,
        name: String,
        productType: PIF.Target.ProductType,
        productName: String
    ) -> PIFTargetBuilder {
        let target = PIFTargetBuilder(guid: guid, name: name, productType: productType, productName: productName)
        targets.append(target)
        return target
    }

    @discardableResult
    func addAggregateTarget(guid: PIF.GUID, name: String) -> PIFAggregateTargetBuilder {
        let target = PIFAggregateTargetBuilder(guid: guid, name: name)
        targets.append(target)
        return target
    }

    func construct() throws -> PIF.Project {
        let buildConfigurations = self.buildConfigurations.map { builder -> PIF.BuildConfiguration in
            builder.guid = "\(guid)::BUILDCONFIG_\(builder.name)"
            return builder.construct()
        }

        // Construct group tree before targets to make sure file references have GUIDs.
        groupTree.guid = "\(guid)::MAINGROUP"
        let groupTree = self.groupTree.construct() as! PIF.Group
        let targets = try self.targets.map { try $0.construct() }

        return PIF.Project(
            guid: guid,
            name: name,
            path: path,
            projectDirectory: projectDirectory,
            developmentRegion: developmentRegion,
            buildConfigurations: buildConfigurations,
            targets: targets,
            groupTree: groupTree
        )
    }
}

final class PackagePIFProjectBuilder: PIFProjectBuilder {
    private let package: ResolvedPackage
    private let parameters: PIFBuilderParameters
    private let fileSystem: FileSystem
    private let observabilityScope: ObservabilityScope
    private var binaryGroup: PIFGroupBuilder!
    private let executableTargetProductMap: [ResolvedTarget: ResolvedProduct]

    var isRootPackage: Bool { package.manifest.packageKind.isRoot }

    init(
        package: ResolvedPackage,
        parameters: PIFBuilderParameters,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) throws {
        self.package = package
        self.parameters = parameters
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope.makeChildScope(
            description: "Package PIF Builder",
            metadata: package.underlying.diagnosticsMetadata
        )

        executableTargetProductMap = try Dictionary(throwingUniqueKeysWithValues:
            package.products.filter { $0.type == .executable }.map { ($0.mainTarget, $0) }
        )

        super.init()

        guid = package.pifProjectGUID
        name = package.manifest.displayName // TODO: use identity instead?
        path = package.path
        projectDirectory = package.path
        developmentRegion = package.manifest.defaultLocalization ?? "en"
        binaryGroup = groupTree.addGroup(path: "/", sourceTree: .absolute, name: "Binaries")

        // Configure the project-wide build settings.  First we set those that are in common between the "Debug" and
        // "Release" configurations, and then we set those that are different.
        var settings = PIF.BuildSettings()
        settings[.PRODUCT_NAME] = "$(TARGET_NAME)"
        settings[.SUPPORTED_PLATFORMS] = ["$(AVAILABLE_PLATFORMS)"]
        settings[.SDKROOT] = "auto"
        settings[.SDK_VARIANT] = "auto"
        settings[.SKIP_INSTALL] = "YES"
        settings[.MACOSX_DEPLOYMENT_TARGET] = package.deploymentTarget(for: .macOS)
        settings[.IPHONEOS_DEPLOYMENT_TARGET] = package.deploymentTarget(for: .iOS)
        settings[.IPHONEOS_DEPLOYMENT_TARGET, for: .macCatalyst] = package.deploymentTarget(for: .macCatalyst)
        settings[.TVOS_DEPLOYMENT_TARGET] = package.deploymentTarget(for: .tvOS)
        settings[.WATCHOS_DEPLOYMENT_TARGET] = package.deploymentTarget(for: .watchOS)
        settings[.XROS_DEPLOYMENT_TARGET] = package.deploymentTarget(for: .visionOS)
        settings[.DRIVERKIT_DEPLOYMENT_TARGET] = package.deploymentTarget(for: .driverKit)
        settings[.DYLIB_INSTALL_NAME_BASE] = "@rpath"
        settings[.USE_HEADERMAP] = "NO"
        settings[.SWIFT_ACTIVE_COMPILATION_CONDITIONS] = ["$(inherited)", "SWIFT_PACKAGE"]
        settings[.GCC_PREPROCESSOR_DEFINITIONS] = ["$(inherited)", "SWIFT_PACKAGE"]
        settings[.CLANG_ENABLE_OBJC_ARC] = "YES"
        settings[.KEEP_PRIVATE_EXTERNS] = "NO"
        // We currently deliberately do not support Swift ObjC interface headers.
        settings[.SWIFT_INSTALL_OBJC_HEADER] = "NO"
        settings[.SWIFT_OBJC_INTERFACE_HEADER_NAME] = ""
        settings[.OTHER_LDRFLAGS] = []

        // This will add the XCTest related search paths automatically
        // (including the Swift overlays).
        settings[.ENABLE_TESTING_SEARCH_PATHS] = "YES"

        // XCTest search paths should only be specified for certain platforms (watchOS doesn't have XCTest).
        for platform: PIF.BuildSettings.Platform in [.macOS, .iOS, .tvOS] {
            settings[.FRAMEWORK_SEARCH_PATHS, for: platform, default: ["$(inherited)"]]
                .append("$(PLATFORM_DIR)/Developer/Library/Frameworks")
        }

        PlatformRegistry.default.knownPlatforms.forEach {
            guard let platform = PIF.BuildSettings.Platform.from(platform: $0) else { return }
            let supportedPlatform = package.getDerived(for: $0, usingXCTest: false)
            if !supportedPlatform.options.isEmpty {
                settings[.SPECIALIZATION_SDK_OPTIONS, for: platform] = supportedPlatform.options
            }
        }

        // Disable signing for all the things since there is no way to configure
        // signing information in packages right now.
        settings[.ENTITLEMENTS_REQUIRED] = "NO"
        settings[.CODE_SIGNING_REQUIRED] = "NO"
        settings[.CODE_SIGN_IDENTITY] = ""

        var debugSettings = settings
        debugSettings[.COPY_PHASE_STRIP] = "NO"
        debugSettings[.DEBUG_INFORMATION_FORMAT] = "dwarf"
        debugSettings[.ENABLE_NS_ASSERTIONS] = "YES"
        debugSettings[.GCC_OPTIMIZATION_LEVEL] = "0"
        debugSettings[.ONLY_ACTIVE_ARCH] = "YES"
        debugSettings[.SWIFT_OPTIMIZATION_LEVEL] = "-Onone"
        debugSettings[.ENABLE_TESTABILITY] = "YES"
        debugSettings[.SWIFT_ACTIVE_COMPILATION_CONDITIONS, default: []].append("DEBUG")
        debugSettings[.GCC_PREPROCESSOR_DEFINITIONS, default: ["$(inherited)"]].append("DEBUG=1")
        addBuildConfiguration(name: "Debug", settings: debugSettings)

        var releaseSettings = settings
        releaseSettings[.COPY_PHASE_STRIP] = "YES"
        releaseSettings[.DEBUG_INFORMATION_FORMAT] = "dwarf-with-dsym"
        releaseSettings[.GCC_OPTIMIZATION_LEVEL] = "s"
        releaseSettings[.SWIFT_OPTIMIZATION_LEVEL] = "-Owholemodule"

        if parameters.enableTestability {
            releaseSettings[.ENABLE_TESTABILITY] = "YES"
        }

        addBuildConfiguration(name: "Release", settings: releaseSettings)

        for product in package.products.sorted(by: { $0.name < $1.name }) {
            try addTarget(for: product)
        }

        for target in package.targets.sorted(by: { $0.name < $1.name }) {
            try self.addTarget(for: target)
        }

        if binaryGroup.children.isEmpty {
            groupTree.removeChild(binaryGroup)
        }
    }

    private func addTarget(for product: ResolvedProduct) throws {
        switch product.type {
        case .executable, .snippet, .test:
            try addMainModuleTarget(for: product)
        case .library:
            addLibraryTarget(for: product)
        case .plugin, .macro:
            return
        }
    }

    private func addTarget(for target: ResolvedTarget) throws {
        switch target.type {
        case .library:
            try self.addLibraryTarget(for: target)
        case .systemModule:
            try self.addSystemTarget(for: target)
        case .executable, .snippet, .test:
            // Skip executable module targets and test module targets (they will have been dealt with as part of the
            // products to which they belong).
            return
        case .binary:
            // Binary target don't need to be built.
            return
        case .plugin:
            // Package plugin targets.
            return
        case .macro:
            // Macros are not supported when using XCBuild, similar to package plugins.
            return
        }
    }

    private func targetName(for product: ResolvedProduct) -> String {
        return Self.targetName(for: product.name)
    }

    static func targetName(for productName: String) -> String {
        return "\(productName)_\(String(productName.hash, radix: 16, uppercase: true))_PackageProduct"
    }

    private func addMainModuleTarget(for product: ResolvedProduct) throws {
        let productType: PIF.Target.ProductType = product.type == .executable ? .executable : .unitTest
        let pifTarget = addTarget(
            guid: product.pifTargetGUID,
            name: targetName(for: product),
            productType: productType,
            productName: product.name
        )

        // We'll be infusing the product's main module target into the one for the product itself.
        let mainTarget = product.mainTarget

        addSources(mainTarget.sources, to: pifTarget)

        let dependencies = try! topologicalSort(mainTarget.dependencies) { $0.packageDependencies }.sorted()
        for dependency in dependencies {
            addDependency(to: dependency, in: pifTarget, linkProduct: true)
        }

        // Configure the target-wide build settings. The details depend on the kind of product we're building, but are
        // in general the ones that are suitable for end-product artifacts such as executables and test bundles.
        var settings = PIF.BuildSettings()
        settings[.TARGET_NAME] = product.name
        settings[.PACKAGE_RESOURCE_TARGET_KIND] = "regular"
        settings[.PRODUCT_NAME] = product.name
        settings[.PRODUCT_MODULE_NAME] = mainTarget.c99name
        settings[.PRODUCT_BUNDLE_IDENTIFIER] = product.name
        settings[.EXECUTABLE_NAME] = product.name
        settings[.CLANG_ENABLE_MODULES] = "YES"
        settings[.DEFINES_MODULE] = "YES"
        settings[.SWIFT_FORCE_STATIC_LINK_STDLIB] = "NO"
        settings[.SWIFT_FORCE_DYNAMIC_LINK_STDLIB] = "YES"

        if product.type == .executable || product.type == .test {
            settings[.LIBRARY_SEARCH_PATHS] = ["$(inherited)", "\(parameters.toolchainLibDir.pathString)/swift/macosx"]
        }

        // Tests can have a custom deployment target based on the minimum supported by XCTest.
        if mainTarget.underlying.type == .test {
            settings[.MACOSX_DEPLOYMENT_TARGET] = mainTarget.deploymentTarget(for: .macOS, usingXCTest: true)
            settings[.IPHONEOS_DEPLOYMENT_TARGET] = mainTarget.deploymentTarget(for: .iOS, usingXCTest: true)
            settings[.TVOS_DEPLOYMENT_TARGET] = mainTarget.deploymentTarget(for: .tvOS, usingXCTest: true)
            settings[.WATCHOS_DEPLOYMENT_TARGET] = mainTarget.deploymentTarget(for: .watchOS, usingXCTest: true)
            settings[.XROS_DEPLOYMENT_TARGET] = mainTarget.deploymentTarget(for: .visionOS, usingXCTest: true)
        }

        if product.type == .executable {
            // Command-line tools are only supported for the macOS platforms.
            settings[.SDKROOT] = "macosx"
            settings[.SUPPORTED_PLATFORMS] = ["macosx", "linux"]

            // Setup install path for executables if it's in root of a pure Swift package.
            if isRootPackage {
                settings[.SKIP_INSTALL] = "NO"
                settings[.INSTALL_PATH] = "/usr/local/bin"
                settings[.LD_RUNPATH_SEARCH_PATHS, default: ["$(inherited)"]].append("@executable_path/../lib")
            }
        } else {
            // FIXME: we shouldn't always include both the deep and shallow bundle paths here, but for that we'll need
            // rdar://problem/31867023
            settings[.LD_RUNPATH_SEARCH_PATHS, default: ["$(inherited)"]] +=
                ["@loader_path/Frameworks", "@loader_path/../Frameworks"]
            settings[.GENERATE_INFOPLIST_FILE] = "YES"
        }

        if let clangTarget = mainTarget.underlying as? ClangTarget {
            // Let the target itself find its own headers.
            settings[.HEADER_SEARCH_PATHS, default: ["$(inherited)"]].append(clangTarget.includeDir.pathString)
            settings[.GCC_C_LANGUAGE_STANDARD] = clangTarget.cLanguageStandard
            settings[.CLANG_CXX_LANGUAGE_STANDARD] = clangTarget.cxxLanguageStandard
        } else if let swiftTarget = mainTarget.underlying as? SwiftTarget {
            settings[.SWIFT_VERSION] = swiftTarget.swiftVersion.description
        }

        if let resourceBundle = addResourceBundle(for: mainTarget, in: pifTarget) {
            settings[.PACKAGE_RESOURCE_BUNDLE_NAME] = resourceBundle
            settings[.GENERATE_RESOURCE_ACCESSORS] = "YES"
        }

        // For targets, we use the common build settings for both the "Debug" and the "Release" configurations (all
        // differentiation is at the project level).
        var debugSettings = settings
        var releaseSettings = settings

        var impartedSettings = PIF.BuildSettings()
        try addManifestBuildSettings(
            from: mainTarget.underlying,
            debugSettings: &debugSettings,
            releaseSettings: &releaseSettings,
            impartedSettings: &impartedSettings
        )

        let impartedBuildProperties = PIF.ImpartedBuildProperties(settings: impartedSettings)
        pifTarget.addBuildConfiguration(name: "Debug", settings: debugSettings, impartedBuildProperties: impartedBuildProperties)
        pifTarget.addBuildConfiguration(name: "Release", settings: releaseSettings, impartedBuildProperties: impartedBuildProperties)
    }

    private func addLibraryTarget(for product: ResolvedProduct) {
        let pifTargetProductName: String
        let executableName: String
        let productType: PIF.Target.ProductType
        if product.type == .library(.dynamic) {
            if parameters.shouldCreateDylibForDynamicProducts {
                pifTargetProductName = "lib\(product.name).dylib"
                executableName = pifTargetProductName
                productType = .dynamicLibrary
            } else {
                pifTargetProductName = product.name + ".framework"
                executableName = product.name
                productType = .framework
            }
        } else {
            pifTargetProductName = "lib\(product.name).a"
            executableName = pifTargetProductName
            productType = .packageProduct
        }

        // Create a special kind of .packageProduct PIF target that just "groups" a set of targets for clients to
        // depend on. XCBuild will not produce a separate artifact for a package product, but will instead consider any
        // dependency on the package product to be a dependency on the whole set of targets on which the package product
        // depends.
        let pifTarget = addTarget(
            guid: product.pifTargetGUID,
            name: targetName(for: product),
            productType: productType,
            productName: pifTargetProductName
        )

        // Handle the dependencies of the targets in the product (and link against them, which in the case of a package
        // product, really just means that clients should link against them).
        let dependencies = product.recursivePackageDependencies()
        for dependency in dependencies {
            switch dependency {
            case .target(let target, let conditions):
                if target.type != .systemModule {
                    addDependency(to: target, in: pifTarget, conditions: conditions, linkProduct: true)
                }
            case .product(let product, let conditions):
                addDependency(to: product, in: pifTarget, conditions: conditions, linkProduct: true)
            }
        }

        var settings = PIF.BuildSettings()
        let usesUnsafeFlags = dependencies.contains { $0.target?.underlying.usesUnsafeFlags == true }
        settings[.USES_SWIFTPM_UNSAFE_FLAGS] = usesUnsafeFlags ? "YES" : "NO"

        // If there are no system modules in the dependency graph, mark the target as extension-safe.
        let dependsOnAnySystemModules = dependencies.contains { $0.target?.type == .systemModule }
        if !dependsOnAnySystemModules {
            settings[.APPLICATION_EXTENSION_API_ONLY] = "YES"
        }

        // Add other build settings when we're building an actual dylib.
        if product.type == .library(.dynamic) {
            settings[.TARGET_NAME] = product.name
            settings[.PRODUCT_NAME] = executableName
            settings[.PRODUCT_MODULE_NAME] = product.name
            settings[.PRODUCT_BUNDLE_IDENTIFIER] = product.name
            settings[.EXECUTABLE_NAME] = executableName
            settings[.CLANG_ENABLE_MODULES] = "YES"
            settings[.DEFINES_MODULE] = "YES"
            settings[.SKIP_INSTALL] = "NO"
            settings[.INSTALL_PATH] = "/usr/local/lib"
            settings[.LIBRARY_SEARCH_PATHS] = ["$(inherited)", "\(parameters.toolchainLibDir.pathString)/swift/macosx"]

            if !parameters.shouldCreateDylibForDynamicProducts {
                settings[.GENERATE_INFOPLIST_FILE] = "YES"
                // If the built framework is named same as one of the target in the package, it can be picked up
                // automatically during indexing since the build system always adds a -F flag to the built products dir.
                // To avoid this problem, we build all package frameworks in a subdirectory.
                settings[.BUILT_PRODUCTS_DIR] = "$(BUILT_PRODUCTS_DIR)/PackageFrameworks"
                settings[.TARGET_BUILD_DIR] = "$(TARGET_BUILD_DIR)/PackageFrameworks"

                // Set the project and marketing version for the framework because the app store requires these to be
                // present. The AppStore requires bumping the project version when ingesting new builds but that's for
                // top-level apps and not frameworks embedded inside it.
                settings[.MARKETING_VERSION] = "1.0" // Version
                settings[.CURRENT_PROJECT_VERSION] = "1" // Build
            }

            pifTarget.addSourcesBuildPhase()
        }

        pifTarget.addBuildConfiguration(name: "Debug", settings: settings)
        pifTarget.addBuildConfiguration(name: "Release", settings: settings)
    }

    private func addLibraryTarget(for target: ResolvedTarget) throws {
        let pifTarget = addTarget(
            guid: target.pifTargetGUID,
            name: target.name,
            productType: .objectFile,
            productName: "\(target.name).o"
        )

        var settings = PIF.BuildSettings()
        settings[.TARGET_NAME] = target.name
        settings[.PACKAGE_RESOURCE_TARGET_KIND] = "regular"
        settings[.PRODUCT_NAME] = "\(target.name).o"
        settings[.PRODUCT_MODULE_NAME] = target.c99name
        settings[.PRODUCT_BUNDLE_IDENTIFIER] = target.name
        settings[.EXECUTABLE_NAME] = "\(target.name).o"
        settings[.CLANG_ENABLE_MODULES] = "YES"
        settings[.DEFINES_MODULE] = "YES"
        settings[.MACH_O_TYPE] = "mh_object"
        settings[.GENERATE_MASTER_OBJECT_FILE] = "NO"
        // Disable code coverage linker flags since we're producing .o files. Otherwise, we will run into duplicated
        // symbols when there are more than one targets that produce .o as their product.
        settings[.CLANG_COVERAGE_MAPPING_LINKER_ARGS] = "NO"
        if let aliases = target.moduleAliases {
            settings[.SWIFT_MODULE_ALIASES] = aliases.map{ $0.key + "=" + $0.value }
        }

        // Create a set of build settings that will be imparted to any target that depends on this one.
        var impartedSettings = PIF.BuildSettings()

        let generatedModuleMapDir = "$(OBJROOT)/GeneratedModuleMaps/$(PLATFORM_NAME)"
        let moduleMapFile = "\(generatedModuleMapDir)/\(target.name).modulemap"
        let moduleMapFileContents: String?
        let shouldImpartModuleMap: Bool

        if let clangTarget = target.underlying as? ClangTarget {
            // Let the target itself find its own headers.
            settings[.HEADER_SEARCH_PATHS, default: ["$(inherited)"]].append(clangTarget.includeDir.pathString)
            settings[.GCC_C_LANGUAGE_STANDARD] = clangTarget.cLanguageStandard
            settings[.CLANG_CXX_LANGUAGE_STANDARD] = clangTarget.cxxLanguageStandard

            // Also propagate this search path to all direct and indirect clients.
            impartedSettings[.HEADER_SEARCH_PATHS, default: ["$(inherited)"]].append(clangTarget.includeDir.pathString)

            if !fileSystem.exists(clangTarget.moduleMapPath) {
                impartedSettings[.OTHER_SWIFT_FLAGS, default: ["$(inherited)"]] +=
                    ["-Xcc", "-fmodule-map-file=\(moduleMapFile)"]

                moduleMapFileContents = """
                    module \(target.c99name) {
                        umbrella "\(clangTarget.includeDir.pathString)"
                        export *
                    }
                    """

                shouldImpartModuleMap = true
            } else {
                moduleMapFileContents = nil
                shouldImpartModuleMap = false
            }
        } else if let swiftTarget = target.underlying as? SwiftTarget {
            settings[.SWIFT_VERSION] = swiftTarget.swiftVersion.description
            // Generate ObjC compatibility header for Swift library targets.
            settings[.SWIFT_OBJC_INTERFACE_HEADER_DIR] = "$(OBJROOT)/GeneratedModuleMaps/$(PLATFORM_NAME)"
            settings[.SWIFT_OBJC_INTERFACE_HEADER_NAME] = "\(target.name)-Swift.h"

            moduleMapFileContents = """
                module \(target.c99name) {
                    header "\(target.name)-Swift.h"
                    export *
                }
                """

            shouldImpartModuleMap = true
        } else {
            throw InternalError("unexpected target")
        }

        if let moduleMapFileContents {
            settings[.MODULEMAP_PATH] = moduleMapFile
            settings[.MODULEMAP_FILE_CONTENTS] = moduleMapFileContents
        }

        // Pass the path of the module map up to all direct and indirect clients.
        if shouldImpartModuleMap {
            impartedSettings[.OTHER_CFLAGS, default: ["$(inherited)"]].append("-fmodule-map-file=\(moduleMapFile)")
        }
        impartedSettings[.OTHER_LDRFLAGS] = []

        if target.underlying.isCxx {
            impartedSettings[.OTHER_LDFLAGS, default: ["$(inherited)"]].append("-lc++")
        }

        addSources(target.sources, to: pifTarget)

        // Handle the target's dependencies (but don't link against them).
        let dependencies = try! topologicalSort(target.dependencies) { $0.packageDependencies }.sorted()
        for dependency in dependencies {
            addDependency(to: dependency, in: pifTarget, linkProduct: false)
        }

        if let resourceBundle = addResourceBundle(for: target, in: pifTarget) {
            settings[.PACKAGE_RESOURCE_BUNDLE_NAME] = resourceBundle
            settings[.GENERATE_RESOURCE_ACCESSORS] = "YES"
            impartedSettings[.EMBED_PACKAGE_RESOURCE_BUNDLE_NAMES, default: ["$(inherited)"]].append(resourceBundle)
        }

        // For targets, we use the common build settings for both the "Debug" and the "Release" configurations (all
        // differentiation is at the project level).
        var debugSettings = settings
        var releaseSettings = settings

        try addManifestBuildSettings(
            from: target.underlying,
            debugSettings: &debugSettings,
            releaseSettings: &releaseSettings,
            impartedSettings: &impartedSettings
        )

        let impartedBuildProperties = PIF.ImpartedBuildProperties(settings: impartedSettings)
        pifTarget.addBuildConfiguration(name: "Debug", settings: debugSettings, impartedBuildProperties: impartedBuildProperties)
        pifTarget.addBuildConfiguration(name: "Release", settings: releaseSettings, impartedBuildProperties: impartedBuildProperties)
        pifTarget.impartedBuildSettings = impartedSettings
    }

    private func addSystemTarget(for target: ResolvedTarget) throws {
        guard let systemTarget = target.underlying as? SystemLibraryTarget else {
            throw InternalError("unexpected target type")
        }

        // Impart the header search path to all direct and indirect clients.
        var impartedSettings = PIF.BuildSettings()

        var cFlags: [String] = []
        for result in try pkgConfigArgs(
            for: systemTarget,
            pkgConfigDirectories: parameters.pkgConfigDirectories,
            sdkRootPath: parameters.sdkRootPath,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        ) {
            if let error = result.error {
                self.observabilityScope.emit(
                    warning: "\(error.interpolationDescription)",
                    metadata: .pkgConfig(pcFile: result.pkgConfigName, targetName: target.name)
                )
            } else {
                cFlags = result.cFlags
                impartedSettings[.OTHER_LDFLAGS, default: ["$(inherited)"]] += result.libs
            }
        }

        impartedSettings[.OTHER_LDRFLAGS] = []
        impartedSettings[.OTHER_CFLAGS, default: ["$(inherited)"]] += ["-fmodule-map-file=\(systemTarget.moduleMapPath)"] + cFlags
        impartedSettings[.OTHER_SWIFT_FLAGS, default: ["$(inherited)"]] += ["-Xcc", "-fmodule-map-file=\(systemTarget.moduleMapPath)"] + cFlags
        let impartedBuildProperties = PIF.ImpartedBuildProperties(settings: impartedSettings)

        // Create an aggregate PIF target (which doesn't have an actual product).
        let pifTarget = addAggregateTarget(guid: target.pifTargetGUID, name: target.name)
        pifTarget.addBuildConfiguration(name: "Debug", settings: PIF.BuildSettings(), impartedBuildProperties: impartedBuildProperties)
        pifTarget.addBuildConfiguration(name: "Release", settings: PIF.BuildSettings(), impartedBuildProperties: impartedBuildProperties)
        pifTarget.impartedBuildSettings = impartedSettings
    }

    private func addSources(_ sources: Sources, to pifTarget: PIFTargetBuilder) {
        // Create a group for the target's source files.  For now we use an absolute path for it, but we should really
        // make it be container-relative, since it's always inside the package directory.
        let targetGroup = groupTree.addGroup(
            path: sources.root.relative(to: package.path).pathString,
            sourceTree: .group
        )

        // Add a source file reference for each of the source files, and also an indexable-file URL for each one.
        for path in sources.relativePaths {
            pifTarget.addSourceFile(targetGroup.addFileReference(path: path.pathString, sourceTree: .group))
        }
    }

    private func addDependency(
        to dependency: ResolvedTarget.Dependency,
        in pifTarget: PIFTargetBuilder,
        linkProduct: Bool
    ) {
        switch dependency {
        case .target(let target, let conditions):
            addDependency(
                to: target,
                in: pifTarget,
                conditions: conditions,
                linkProduct: linkProduct
            )
        case .product(let product, let conditions):
            addDependency(
                to: product,
                in: pifTarget,
                conditions: conditions,
                linkProduct: linkProduct
            )
        }
    }

    private func addDependency(
        to target: ResolvedTarget,
        in pifTarget: PIFTargetBuilder,
        conditions: [PackageCondition],
        linkProduct: Bool
    ) {
        // Only add the binary target as a library when we want to link against the product.
        if let binaryTarget = target.underlying as? BinaryTarget {
            let ref = binaryGroup.addFileReference(path: binaryTarget.artifactPath.pathString)
            pifTarget.addLibrary(ref, platformFilters: conditions.toPlatformFilters())
        } else {
            // If this is an executable target, the dependency should be to the PIF target created from the its
            // product, as we don't have PIF targets corresponding to executable targets.
            let targetGUID = executableTargetProductMap[target]?.pifTargetGUID ?? target.pifTargetGUID
            let linkProduct = linkProduct && target.type != .systemModule && target.type != .executable
            pifTarget.addDependency(
                toTargetWithGUID: targetGUID,
                platformFilters: conditions.toPlatformFilters(),
                linkProduct: linkProduct)
        }
    }

    private func addDependency(
        to product: ResolvedProduct,
        in pifTarget: PIFTargetBuilder,
        conditions: [PackageCondition],
        linkProduct: Bool
    ) {
        pifTarget.addDependency(
            toTargetWithGUID: product.pifTargetGUID,
            platformFilters: conditions.toPlatformFilters(),
            linkProduct: linkProduct
        )
    }

    private func addResourceBundle(for target: ResolvedTarget, in pifTarget: PIFTargetBuilder) -> String? {
        guard !target.underlying.resources.isEmpty else {
            return nil
        }

        let bundleName = "\(package.manifest.displayName)_\(target.name)" // TODO: use identity instead?
        let resourcesTarget = addTarget(
            guid: target.pifResourceTargetGUID,
            name: bundleName,
            productType: .bundle,
            productName: bundleName
        )

        pifTarget.addDependency(
            toTargetWithGUID: resourcesTarget.guid,
            platformFilters: [],
            linkProduct: false
        )

        var settings = PIF.BuildSettings()
        settings[.TARGET_NAME] = bundleName
        settings[.PRODUCT_NAME] = bundleName
        settings[.PRODUCT_MODULE_NAME] = bundleName
        let bundleIdentifier = "\(package.manifest.displayName).\(target.name).resources".spm_mangledToBundleIdentifier() // TODO: use identity instead?
        settings[.PRODUCT_BUNDLE_IDENTIFIER] = bundleIdentifier
        settings[.GENERATE_INFOPLIST_FILE] = "YES"
        settings[.PACKAGE_RESOURCE_TARGET_KIND] = "resource"

        resourcesTarget.addBuildConfiguration(name: "Debug", settings: settings)
        resourcesTarget.addBuildConfiguration(name: "Release", settings: settings)

        let coreDataFileTypes = [XCBuildFileType.xcdatamodeld, .xcdatamodel].flatMap { $0.fileTypes }
        for resource in target.underlying.resources {
            // FIXME: Handle rules here.
            let resourceFile = groupTree.addFileReference(
                path: resource.path.pathString,
                sourceTree: .absolute
            )

            // CoreData files should also be in the actual target because they can end up generating code during the
            // build. The build system will only perform codegen tasks for the main target in this case.
            if coreDataFileTypes.contains(resource.path.extension ?? "") {
                pifTarget.addSourceFile(resourceFile)
            }

            resourcesTarget.addResourceFile(resourceFile)
        }

        let targetGroup = groupTree.addGroup(path: "/", sourceTree: .group)
        pifTarget.addResourceFile(targetGroup.addFileReference(path: "\(bundleName).bundle", sourceTree: .builtProductsDir))

        return bundleName
    }

    // Add inferred build settings for a particular value for a manifest setting and value.
    private func addInferredBuildSettings(
        for setting: PIF.BuildSettings.MultipleValueSetting,
        value: [String],
        platform: PIF.BuildSettings.Platform? = nil,
        configuration: BuildConfiguration,
        settings: inout PIF.BuildSettings
    ) {
        // Automatically set SWIFT_EMIT_MODULE_INTERFACE if the package author uses unsafe flags to enable
        // library evolution (this is needed until there is a way to specify this in the package manifest).
        if setting == .OTHER_SWIFT_FLAGS && value.contains("-enable-library-evolution") {
            settings[.SWIFT_EMIT_MODULE_INTERFACE] = "YES"
        }
    }

    // Apply target-specific build settings defined in the manifest.
    private func addManifestBuildSettings(
        from target: Target,
        debugSettings: inout PIF.BuildSettings,
        releaseSettings: inout PIF.BuildSettings,
        impartedSettings: inout PIF.BuildSettings
    ) throws {
        for (setting, assignments) in target.buildSettings.pifAssignments {
            for assignment in assignments {
                var value = assignment.value
                if setting == .HEADER_SEARCH_PATHS {
                    value = try value.map { try AbsolutePath(validating: $0, relativeTo: target.sources.root).pathString }
                }

                if let platforms = assignment.platforms {
                    for platform in platforms {
                        for configuration in assignment.configurations {
                            switch configuration {
                            case .debug:
                                debugSettings[setting, for: platform, default: ["$(inherited)"]] += value
                                addInferredBuildSettings(for: setting, value: value, platform: platform, configuration: .debug, settings: &debugSettings)
                            case .release:
                                releaseSettings[setting, for: platform, default: ["$(inherited)"]] += value
                                addInferredBuildSettings(for: setting, value: value, platform: platform, configuration: .release, settings: &releaseSettings)
                            }
                        }

                        if setting == .OTHER_LDFLAGS {
                            impartedSettings[setting, for: platform, default: ["$(inherited)"]] += value
                        }
                    }
                } else {
                    for configuration in assignment.configurations {
                        switch configuration {
                        case .debug:
                            debugSettings[setting, default: ["$(inherited)"]] += value
                            addInferredBuildSettings(for: setting, value: value, configuration: .debug, settings: &debugSettings)
                        case .release:
                            releaseSettings[setting, default: ["$(inherited)"]] += value
                            addInferredBuildSettings(for: setting, value: value, configuration: .release, settings: &releaseSettings)
                        }
                    }

                    if setting == .OTHER_LDFLAGS {
                        impartedSettings[setting, default: ["$(inherited)"]] += value
                    }
                }
            }
        }
    }
}

final class AggregatePIFProjectBuilder: PIFProjectBuilder {
    init(projects: [PIFProjectBuilder]) {
        super.init()

        guid = "AGGREGATE"
        name = "Aggregate"
        path = projects[0].path
        projectDirectory = projects[0].projectDirectory
        developmentRegion = "en"

        var settings = PIF.BuildSettings()
        settings[.PRODUCT_NAME] = "$(TARGET_NAME)"
        settings[.SUPPORTED_PLATFORMS] = ["$(AVAILABLE_PLATFORMS)"]
        settings[.SDKROOT] = "auto"
        settings[.SDK_VARIANT] = "auto"
        settings[.SKIP_INSTALL] = "YES"

        addBuildConfiguration(name: "Debug", settings: settings)
        addBuildConfiguration(name: "Release", settings: settings)

        let allExcludingTestsTarget = addAggregateTarget(
            guid: "ALL-EXCLUDING-TESTS",
            name: PIFBuilder.allExcludingTestsTargetName
        )

        allExcludingTestsTarget.addBuildConfiguration(name: "Debug")
        allExcludingTestsTarget.addBuildConfiguration(name: "Release")

        let allIncludingTestsTarget = addAggregateTarget(
            guid: "ALL-INCLUDING-TESTS",
            name: PIFBuilder.allIncludingTestsTargetName
        )

        allIncludingTestsTarget.addBuildConfiguration(name: "Debug")
        allIncludingTestsTarget.addBuildConfiguration(name: "Release")

        for case let project as PackagePIFProjectBuilder in projects where project.isRootPackage {
            for case let target as PIFTargetBuilder in project.targets {
                if target.productType != .unitTest {
                    allExcludingTestsTarget.addDependency(toTargetWithGUID: target.guid,  platformFilters: [], linkProduct: false)
                }

                allIncludingTestsTarget.addDependency(toTargetWithGUID: target.guid, platformFilters: [], linkProduct: false)
            }
        }
    }
}

protocol PIFReferenceBuilder: AnyObject {
    var guid: String { get set }

    func construct() -> PIF.Reference
}

final class PIFFileReferenceBuilder: PIFReferenceBuilder {
    let path: String
    let sourceTree: PIF.Reference.SourceTree
    let name: String?
    let fileType: String?

    @DelayedImmutable
    var guid: String

    init(path: String, sourceTree: PIF.Reference.SourceTree, name: String? = nil, fileType: String? = nil) {
        self.path = path
        self.sourceTree = sourceTree
        self.name = name
        self.fileType = fileType
    }

    func construct() -> PIF.Reference {
        return PIF.FileReference(
            guid: guid,
            path: path,
            sourceTree: sourceTree,
            name: name,
            fileType: fileType
        )
    }
}

final class PIFGroupBuilder: PIFReferenceBuilder {
    let path: String
    let sourceTree: PIF.Reference.SourceTree
    let name: String?
    private(set) var children: [PIFReferenceBuilder]

    @DelayedImmutable
    var guid: PIF.GUID

    init(path: String, sourceTree: PIF.Reference.SourceTree = .group, name: String? = nil) {
        self.path = path
        self.sourceTree = sourceTree
        self.name = name
        children = []
    }

    /// Creates and appends a new Group to the list of children. The new group is returned so that it can be configured.
    func addGroup(
        path: String,
        sourceTree: PIF.Reference.SourceTree = .group,
        name: String? = nil
    ) -> PIFGroupBuilder {
        let group = PIFGroupBuilder(path: path, sourceTree: sourceTree, name: name)
        children.append(group)
        return group
    }

    /// Creates and appends a new FileReference to the list of children.
    func addFileReference(
        path: String,
        sourceTree: PIF.Reference.SourceTree = .group,
        name: String? = nil,
        fileType: String? = nil
    ) -> PIFFileReferenceBuilder {
        let file = PIFFileReferenceBuilder(path: path, sourceTree: sourceTree, name: name, fileType: fileType)
        children.append(file)
        return file
    }

    func removeChild(_ reference: PIFReferenceBuilder) {
        children.removeAll { $0 === reference }
    }

    func construct() -> PIF.Reference {
        let children = self.children.enumerated().map { kvp -> PIF.Reference in
            let (index, builder) = kvp
            builder.guid = "\(guid)::REF_\(index)"
            return builder.construct()
        }

        return PIF.Group(
            guid: guid,
            path: path,
            sourceTree: sourceTree,
            name: name,
            children: children
        )
    }
}

class PIFBaseTargetBuilder {
    public let guid: PIF.GUID
    public let name: String
    public fileprivate(set) var buildConfigurations: [PIFBuildConfigurationBuilder]
    public fileprivate(set) var buildPhases: [PIFBuildPhaseBuilder]
    public fileprivate(set) var dependencies: [PIF.TargetDependency]
    public fileprivate(set) var impartedBuildSettings: PIF.BuildSettings

    fileprivate init(guid: PIF.GUID, name: String) {
        self.guid = guid
        self.name = name
        self.buildConfigurations = []
        self.buildPhases = []
        self.dependencies = []
        self.impartedBuildSettings = PIF.BuildSettings()
    }

    /// Creates and adds a new empty build configuration, i.e. one that does not initially have any build settings.
    /// The name must not be empty and must not be equal to the name of any existing build configuration in the
    /// target.
    @discardableResult
    public func addBuildConfiguration(
        name: String,
        settings: PIF.BuildSettings = PIF.BuildSettings(),
        impartedBuildProperties: PIF.ImpartedBuildProperties = PIF.ImpartedBuildProperties(settings: PIF.BuildSettings())
    ) -> PIFBuildConfigurationBuilder {
        let builder = PIFBuildConfigurationBuilder(name: name, settings: settings, impartedBuildProperties: impartedBuildProperties)
        buildConfigurations.append(builder)
        return builder
    }

    func construct() throws -> PIF.BaseTarget {
        throw InternalError("implement in subclass")
    }

    /// Adds a "headers" build phase, i.e. one that copies headers into a directory of the product, after suitable
    /// processing.
    @discardableResult
    func addHeadersBuildPhase() -> PIFHeadersBuildPhaseBuilder {
        let buildPhase = PIFHeadersBuildPhaseBuilder()
        buildPhases.append(buildPhase)
        return buildPhase
    }

    /// Adds a "sources" build phase, i.e. one that compiles sources and provides them to be linked into the
    /// executable code of the product.
    @discardableResult
    func addSourcesBuildPhase() -> PIFSourcesBuildPhaseBuilder {
        let buildPhase = PIFSourcesBuildPhaseBuilder()
        buildPhases.append(buildPhase)
        return buildPhase
    }

    /// Adds a "frameworks" build phase, i.e. one that links compiled code and libraries into the executable of the
    /// product.
    @discardableResult
    func addFrameworksBuildPhase() -> PIFFrameworksBuildPhaseBuilder {
        let buildPhase = PIFFrameworksBuildPhaseBuilder()
        buildPhases.append(buildPhase)
        return buildPhase
    }

    @discardableResult
    func addResourcesBuildPhase() -> PIFResourcesBuildPhaseBuilder {
        let buildPhase = PIFResourcesBuildPhaseBuilder()
        buildPhases.append(buildPhase)
        return buildPhase
    }

    /// Adds a dependency on another target. It is the caller's responsibility to avoid creating dependency cycles.
    /// A dependency of one target on another ensures that the other target is built first. If `linkProduct` is
    /// true, the receiver will also be configured to link against the product produced by the other target (this
    /// presumes that the product type is one that can be linked against).
    func addDependency(toTargetWithGUID targetGUID: String, platformFilters: [PIF.PlatformFilter], linkProduct: Bool) {
        dependencies.append(.init(targetGUID: targetGUID, platformFilters: platformFilters))
        if linkProduct {
            let frameworksPhase = buildPhases.first { $0 is PIFFrameworksBuildPhaseBuilder }
                ?? addFrameworksBuildPhase()
            frameworksPhase.addBuildFile(toTargetWithGUID: targetGUID, platformFilters: platformFilters)
        }
    }

    /// Convenience function to add a file reference to the Headers build phase, after creating it if needed.
    @discardableResult
    public func addHeaderFile(_ fileReference: PIFFileReferenceBuilder, headerVisibility: PIF.BuildFile.HeaderVisibility) -> PIFBuildFileBuilder {
        let headerPhase = buildPhases.first { $0 is PIFHeadersBuildPhaseBuilder } ?? addHeadersBuildPhase()
        return headerPhase.addBuildFile(to: fileReference, platformFilters: [], headerVisibility: headerVisibility)
    }

    /// Convenience function to add a file reference to the Sources build phase, after creating it if needed.
    @discardableResult
    public func addSourceFile(_ fileReference: PIFFileReferenceBuilder) -> PIFBuildFileBuilder {
        let sourcesPhase = buildPhases.first { $0 is PIFSourcesBuildPhaseBuilder } ?? addSourcesBuildPhase()
        return sourcesPhase.addBuildFile(to: fileReference, platformFilters: [])
    }

    /// Convenience function to add a file reference to the Frameworks build phase, after creating it if needed.
    @discardableResult
    public func addLibrary(_ fileReference: PIFFileReferenceBuilder, platformFilters: [PIF.PlatformFilter]) -> PIFBuildFileBuilder {
        let frameworksPhase = buildPhases.first { $0 is PIFFrameworksBuildPhaseBuilder } ?? addFrameworksBuildPhase()
        return frameworksPhase.addBuildFile(to: fileReference, platformFilters: platformFilters)
    }

    @discardableResult
    public func addResourceFile(_ fileReference: PIFFileReferenceBuilder) -> PIFBuildFileBuilder {
        let resourcesPhase = buildPhases.first { $0 is PIFResourcesBuildPhaseBuilder } ?? addResourcesBuildPhase()
        return resourcesPhase.addBuildFile(to: fileReference, platformFilters: [])
    }

    fileprivate func constructBuildConfigurations() -> [PIF.BuildConfiguration] {
        buildConfigurations.map { builder -> PIF.BuildConfiguration in
            builder.guid = "\(guid)::BUILDCONFIG_\(builder.name)"
            return builder.construct()
        }
    }

    fileprivate func constructBuildPhases() throws -> [PIF.BuildPhase] {
        try buildPhases.enumerated().map { kvp in
            let (index, builder) = kvp
            builder.guid = "\(guid)::BUILDPHASE_\(index)"
            return try builder.construct()
        }
    }
}

final class PIFAggregateTargetBuilder: PIFBaseTargetBuilder {
    override func construct() throws -> PIF.BaseTarget {
        return PIF.AggregateTarget(
            guid: guid,
            name: name,
            buildConfigurations: constructBuildConfigurations(),
            buildPhases: try self.constructBuildPhases(),
            dependencies: dependencies,
            impartedBuildSettings: impartedBuildSettings
        )
    }
}

final class PIFTargetBuilder: PIFBaseTargetBuilder {
    let productType: PIF.Target.ProductType
    let productName: String
    var productReference: PIF.FileReference? = nil

    public init(guid: PIF.GUID, name: String, productType: PIF.Target.ProductType, productName: String) {
        self.productType = productType
        self.productName = productName
        super.init(guid: guid, name: name)
    }

    override func construct() throws -> PIF.BaseTarget {
        return PIF.Target(
            guid: guid,
            name: name,
            productType: productType,
            productName: productName,
            buildConfigurations: constructBuildConfigurations(),
            buildPhases: try self.constructBuildPhases(),
            dependencies: dependencies,
            impartedBuildSettings: impartedBuildSettings
        )
    }
}

class PIFBuildPhaseBuilder {
    public private(set) var buildFiles: [PIFBuildFileBuilder]

    @DelayedImmutable
    var guid: PIF.GUID

    fileprivate init() {
        buildFiles = []
    }

    /// Adds a new build file builder that refers to a file reference.
    /// - Parameters:
    ///   - file: The builder for the file reference.
    @discardableResult
    func addBuildFile(to file: PIFFileReferenceBuilder, platformFilters: [PIF.PlatformFilter], headerVisibility: PIF.BuildFile.HeaderVisibility? = nil) -> PIFBuildFileBuilder {
        let builder = PIFBuildFileBuilder(file: file, platformFilters: platformFilters, headerVisibility: headerVisibility)
        buildFiles.append(builder)
        return builder
    }

    /// Adds a new build file builder that refers to a target GUID.
    /// - Parameters:
    ///   - targetGUID: The GIUD referencing the target.
    @discardableResult
    func addBuildFile(toTargetWithGUID targetGUID: PIF.GUID, platformFilters: [PIF.PlatformFilter]) -> PIFBuildFileBuilder {
        let builder = PIFBuildFileBuilder(targetGUID: targetGUID, platformFilters: platformFilters)
        buildFiles.append(builder)
        return builder
    }

    func construct() throws -> PIF.BuildPhase {
        throw InternalError("implement in subclass")
    }

    fileprivate func constructBuildFiles() -> [PIF.BuildFile] {
        return buildFiles.enumerated().map { kvp -> PIF.BuildFile in
            let (index, builder) = kvp
            builder.guid = "\(guid)::\(index)"
            return builder.construct()
        }
    }
}

final class PIFHeadersBuildPhaseBuilder: PIFBuildPhaseBuilder {
    override func construct() -> PIF.BuildPhase {
        PIF.HeadersBuildPhase(guid: guid, buildFiles: constructBuildFiles())
    }
}

final class PIFSourcesBuildPhaseBuilder: PIFBuildPhaseBuilder {
    override func construct() -> PIF.BuildPhase {
        PIF.SourcesBuildPhase(guid: guid, buildFiles: constructBuildFiles())
    }
}

final class PIFFrameworksBuildPhaseBuilder: PIFBuildPhaseBuilder {
    override func construct() -> PIF.BuildPhase {
        PIF.FrameworksBuildPhase(guid: guid, buildFiles: constructBuildFiles())
    }
}

final class PIFResourcesBuildPhaseBuilder: PIFBuildPhaseBuilder {
    override func construct() -> PIF.BuildPhase {
        PIF.ResourcesBuildPhase(guid: guid, buildFiles: constructBuildFiles())
    }
}

final class PIFBuildFileBuilder {
    private enum Reference {
        case file(builder: PIFFileReferenceBuilder)
        case target(guid: PIF.GUID)

        var pifReference: PIF.BuildFile.Reference {
            switch self {
            case .file(let builder):
                return .file(guid: builder.guid)
            case .target(let guid):
                return .target(guid: guid)
            }
        }
    }

    private let reference: Reference

    @DelayedImmutable
    var guid: PIF.GUID

    let platformFilters: [PIF.PlatformFilter]

    let headerVisibility: PIF.BuildFile.HeaderVisibility?

    fileprivate init(file: PIFFileReferenceBuilder, platformFilters: [PIF.PlatformFilter], headerVisibility: PIF.BuildFile.HeaderVisibility? = nil) {
        reference = .file(builder: file)
        self.platformFilters = platformFilters
        self.headerVisibility = headerVisibility
    }

    fileprivate init(targetGUID: PIF.GUID, platformFilters: [PIF.PlatformFilter], headerVisibility: PIF.BuildFile.HeaderVisibility? = nil) {
        reference = .target(guid: targetGUID)
        self.platformFilters = platformFilters
        self.headerVisibility = headerVisibility
    }

    func construct() -> PIF.BuildFile {
        PIF.BuildFile(guid: guid, reference: reference.pifReference, platformFilters: platformFilters, headerVisibility: headerVisibility)
    }
}

final class PIFBuildConfigurationBuilder {
    let name: String
    let settings: PIF.BuildSettings
    let impartedBuildProperties: PIF.ImpartedBuildProperties

    @DelayedImmutable
    var guid: PIF.GUID

    public init(name: String, settings: PIF.BuildSettings, impartedBuildProperties: PIF.ImpartedBuildProperties) {
        precondition(!name.isEmpty)
        self.name = name
        self.settings = settings
        self.impartedBuildProperties = impartedBuildProperties
    }

    func construct() -> PIF.BuildConfiguration {
        PIF.BuildConfiguration(guid: guid, name: name, buildSettings: settings, impartedBuildProperties: impartedBuildProperties)
    }
}

// Helper functions to consistently generate a PIF target identifier string for a product/target/resource bundle in a
// package. This format helps make sure that there is no collision with any other PIF targets, and in particular that a
// PIF target and a PIF product can have the same name (as they often do).

extension ResolvedPackage {
    var pifProjectGUID: PIF.GUID { "PACKAGE:\(manifest.packageLocation)" }
}

extension ResolvedProduct {
    var pifTargetGUID: PIF.GUID { "PACKAGE-PRODUCT:\(name)" }

    var mainTarget: ResolvedTarget {
        targets.first { $0.type == underlying.type.targetType }!
    }

    /// Returns the recursive dependencies, limited to the target's package, which satisfy the input build environment,
    /// based on their conditions and in a stable order.
    /// - Parameters:
    ///     - environment: The build environment to use to filter dependencies on.
    public func recursivePackageDependencies() -> [ResolvedTarget.Dependency] {
        let initialDependencies = targets.map { ResolvedTarget.Dependency.target($0, conditions: []) }
        return try! topologicalSort(initialDependencies) { dependency in
            return dependency.packageDependencies
        }.sorted()
    }
}

extension ResolvedTarget {
    var pifTargetGUID: PIF.GUID { "PACKAGE-TARGET:\(name)" }
    var pifResourceTargetGUID: PIF.GUID { "PACKAGE-RESOURCE:\(name)" }
}

extension Array where Element == ResolvedTarget.Dependency {

    /// Sorts to get products first, sorted by name, followed by targets, sorted by name.
    func sorted() -> [ResolvedTarget.Dependency] {
        sorted { lhsDependency, rhsDependency in
            switch (lhsDependency, rhsDependency) {
            case (.product, .target):
                return true
            case (.target, .product):
                return false
            case (.product(let lhsProduct, _), .product(let rhsProduct, _)):
                return lhsProduct.name < rhsProduct.name
            case (.target(let lhsTarget, _), .target(let rhsTarget, _)):
                return lhsTarget.name < rhsTarget.name
            }
        }
    }
}

extension ResolvedPackage {
    func deploymentTarget(for platform: PackageModel.Platform, usingXCTest: Bool = false) -> String? {
        return self.getDerived(for: platform, usingXCTest: usingXCTest).version.versionString
    }
}

extension ResolvedTarget {
    func deploymentTarget(for platform: PackageModel.Platform, usingXCTest: Bool = false) -> String? {
        return self.getDerived(for: platform, usingXCTest: usingXCTest).version.versionString
    }
}

extension Target {
    var isCxx: Bool {
        (self as? ClangTarget)?.isCXX ?? false
    }
}

extension ProductType {
    var targetType: Target.Kind {
        switch self {
        case .executable:
            return .executable
        case .snippet:
            return .snippet
        case .test:
            return .test
        case .library:
            return .library
        case .plugin:
            return .plugin
        case .macro:
            return .macro
        }
    }
}

private struct PIFBuildSettingAssignment {
    /// The assignment value.
    let value: [String]

    /// The configurations this assignment applies to.
    let configurations: [BuildConfiguration]

    /// The platforms this assignment is restrained to, or nil to apply to all platforms.
    let platforms: [PIF.BuildSettings.Platform]?
}

private extension BuildSettings.AssignmentTable {
    var pifAssignments: [PIF.BuildSettings.MultipleValueSetting: [PIFBuildSettingAssignment]] {
        var pifAssignments: [PIF.BuildSettings.MultipleValueSetting: [PIFBuildSettingAssignment]] = [:]

        for (declaration, assignments) in self.assignments {
            for assignment in assignments {
                let setting: PIF.BuildSettings.MultipleValueSetting
                let value: [String]

                switch declaration {
                case .LINK_LIBRARIES:
                    setting = .OTHER_LDFLAGS
                    value = assignment.values.map { "-l\($0)" }
                case .LINK_FRAMEWORKS:
                    setting = .OTHER_LDFLAGS
                    value = assignment.values.flatMap { ["-framework", $0] }
                default:
                    guard let parsedSetting = PIF.BuildSettings.MultipleValueSetting(rawValue: declaration.name) else {
                        continue
                    }
                    setting = parsedSetting
                    value = assignment.values
                }

                let pifAssignment = PIFBuildSettingAssignment(
                    value: value,
                    configurations: assignment.configurations,
                    platforms: assignment.pifPlatforms)

                pifAssignments[setting, default: []].append(pifAssignment)
            }
        }

        return pifAssignments
    }
}

private extension BuildSettings.Assignment {
    var configurations: [BuildConfiguration] {
        if let configurationCondition = conditions.lazy.compactMap(\.configurationCondition).first {
            return [configurationCondition.configuration]
        } else {
            return BuildConfiguration.allCases
        }
    }

    var pifPlatforms: [PIF.BuildSettings.Platform]? {
        if let platformsCondition = conditions.lazy.compactMap(\.platformsCondition).first {
            return platformsCondition.platforms.compactMap { PIF.BuildSettings.Platform(rawValue: $0.name) }
        } else {
            return nil
        }
    }
}

@propertyWrapper
public struct DelayedImmutable<Value> {
    private var _value: Value? = nil

    public init() {
    }

    public var wrappedValue: Value {
        get {
            guard let value = _value else {
                fatalError("property accessed before being initialized")
            }
            return value
        }
        set {
            if _value != nil {
                fatalError("property initialized twice")
            }
            _value = newValue
        }
    }
}

extension [PackageCondition] {
    func toPlatformFilters() -> [PIF.PlatformFilter] {
        var result: [PIF.PlatformFilter] = []
        let platformConditions = self.compactMap(\.platformsCondition).flatMap { $0.platforms }

        for condition in platformConditions {
            switch condition {
            case .macOS:
                result += PIF.PlatformFilter.macOSFilters

            case .macCatalyst:
                result += PIF.PlatformFilter.macCatalystFilters

            case .iOS:
                result += PIF.PlatformFilter.iOSFilters

            case .tvOS:
                result += PIF.PlatformFilter.tvOSFilters

            case .watchOS:
                result += PIF.PlatformFilter.watchOSFilters

            case .linux:
                result += PIF.PlatformFilter.linuxFilters

            case .android:
                result += PIF.PlatformFilter.androidFilters

            case .windows:
                result += PIF.PlatformFilter.windowsFilters

            case .driverKit:
                result += PIF.PlatformFilter.driverKitFilters

            case .wasi:
                result += PIF.PlatformFilter.webAssemblyFilters

            case .openbsd:
                result += PIF.PlatformFilter.openBSDFilters

            default:
                assertionFailure("Unhandled platform condition: \(condition)")
                break
            }
        }
        return result
    }
}

extension PIF.PlatformFilter {

    /// macOS platform filters.
    public static let macOSFilters: [PIF.PlatformFilter] = [.init(platform: "macos")]

    /// Mac Catalyst platform filters.
    public static let macCatalystFilters: [PIF.PlatformFilter] = [
        .init(platform: "ios", environment: "maccatalyst")
    ]

    /// iOS platform filters.
    public static let iOSFilters: [PIF.PlatformFilter] = [
        .init(platform: "ios"),
        .init(platform: "ios", environment: "simulator")
    ]

    /// tvOS platform filters.
    public static let tvOSFilters: [PIF.PlatformFilter] = [
        .init(platform: "tvos"),
        .init(platform: "tvos", environment: "simulator")
    ]

    /// watchOS platform filters.
    public static let watchOSFilters: [PIF.PlatformFilter] = [
        .init(platform: "watchos"),
        .init(platform: "watchos", environment: "simulator")
    ]

    /// DriverKit platform filters.
    public static let driverKitFilters: [PIF.PlatformFilter] = [
        .init(platform: "driverkit"),
    ]

    /// Windows platform filters.
    public static let windowsFilters: [PIF.PlatformFilter] = [
        .init(platform: "windows", environment: "msvc"),
        .init(platform: "windows", environment: "gnu"),
    ]

    /// Android platform filters.
    public static let androidFilters: [PIF.PlatformFilter] = [
        .init(platform: "linux", environment: "android"),
        .init(platform: "linux", environment: "androideabi"),
    ]

    /// Common Linux platform filters.
    public static let linuxFilters: [PIF.PlatformFilter] = {
        ["", "eabi", "gnu", "gnueabi", "gnueabihf"].map {
            .init(platform: "linux", environment: $0)
        }
    }()

    /// OpenBSD filters.
    public static let openBSDFilters: [PIF.PlatformFilter] = [
        .init(platform: "openbsd"),
    ]

    /// WebAssembly platform filters.
    public static let webAssemblyFilters: [PIF.PlatformFilter] = [
        .init(platform: "wasi"),
    ]
}

private extension PIF.BuildSettings.Platform {
    static func from(platform: PackageModel.Platform) -> PIF.BuildSettings.Platform? {
        switch platform {
        case .iOS: return .iOS
        case .linux: return .linux
        case .macCatalyst: return .macCatalyst
        case .macOS: return .macOS
        case .tvOS: return .tvOS
        case .watchOS: return .watchOS
        case .driverKit: return .driverKit
        default: return nil
        }
    }
}
