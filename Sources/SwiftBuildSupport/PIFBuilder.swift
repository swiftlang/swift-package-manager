//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import PackageGraph
import PackageLoading
import PackageModel
import TSCUtility

@_spi(SwiftPMInternal)
import SPMBuildCore

import func TSCBasic.memoize
import func TSCBasic.topologicalSort

#if canImport(SwiftBuild)
import enum SwiftBuild.ProjectModel
#endif

/// The parameters required by `PIFBuilder`.
struct PIFBuilderParameters {
    let triple: Basics.Triple

    /// Whether the toolchain supports `-package-name` option.
    let isPackageAccessModifierSupported: Bool

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

    /// The Swift language versions supported by the SwiftBuild being used for the build.
    let supportedSwiftVersions: [SwiftLanguageVersion]
}

/// PIF object builder for a package graph.
public final class PIFBuilder {
    /// Name of the PIF target aggregating all targets (*excluding* tests).
    public static let allExcludingTestsTargetName = "AllExcludingTests"

    /// Name of the PIF target aggregating all targets (*including* tests).
    public static let allIncludingTestsTargetName = "AllIncludingTests"

    /// The package graph to build from.
    let graph: ModulesGraph

    /// The parameters used to configure the PIF.
    let parameters: PIFBuilderParameters

    /// The ObservabilityScope to emit diagnostics to.
    let observabilityScope: ObservabilityScope

    /// The file system to read from.
    let fileSystem: FileSystem

    /// Creates a `PIFBuilder` instance.
    /// - Parameters:
    ///   - graph: The package graph to build from.
    ///   - parameters: The parameters used to configure the PIF.
    ///   - fileSystem: The file system to read from.
    ///   - observabilityScope: The ObservabilityScope to emit diagnostics to.
    init(
        graph: ModulesGraph,
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
    ///   - preservePIFModelStructure: Whether to preserve model structure.
    /// - Returns: The package graph in the JSON PIF format.
    func generatePIF(
        prettyPrint: Bool = true,
        preservePIFModelStructure: Bool = false
    ) throws -> String {
        #if canImport(SwiftBuild)
        let encoder = prettyPrint ? JSONEncoder.makeWithDefaults() : JSONEncoder()

        if !preservePIFModelStructure {
            encoder.userInfo[.encodeForSwiftBuild] = true
        }

        let topLevelObject = try self.construct()

        // Sign the PIF objects before encoding it for Swift Build.
        try PIF.sign(workspace: topLevelObject.workspace)

        let pifData = try encoder.encode(topLevelObject)
        let pifString = String(decoding: pifData, as: UTF8.self)
        
        return pifString
        #else
        fatalError("Swift Build support is not linked in.")
        #endif
    }
    
    #if canImport(SwiftBuild)
    
    private var cachedPIF: PIF.TopLevelObject?

    /// Constructs a `PIF.TopLevelObject` representing the package graph.
    private func construct() throws -> PIF.TopLevelObject {
        try memoize(to: &self.cachedPIF) {
            guard let rootPackage = self.graph.rootPackages.only else {
                if self.graph.rootPackages.isEmpty {
                    throw PIFGenerationError.rootPackageNotFound
                } else {
                    throw PIFGenerationError.multipleRootPackagesFound
                }
            }

            let sortedPackages = self.graph.packages
                .sorted { $0.manifest.displayName < $1.manifest.displayName } // TODO: use identity instead?
            
            let packagesAndProjects: [(ResolvedPackage, ProjectModel.Project)] = try sortedPackages.map { package in
                let packagePIFBuilderDelegate = PackagePIFBuilderDelegate(
                    package: package
                )
                let packagePIFBuilder = PackagePIFBuilder(
                    modulesGraph: self.graph,
                    resolvedPackage: package,
                    packageManifest: package.manifest,
                    delegate: packagePIFBuilderDelegate,
                    buildToolPluginResultsByTargetName: [:],
                    createDylibForDynamicProducts: self.parameters.shouldCreateDylibForDynamicProducts,
                    packageDisplayVersion: package.manifest.displayName,
                    observabilityScope: self.observabilityScope
                )
                
                try packagePIFBuilder.build()
                return (package, packagePIFBuilder.pifProject)
            }
            
            var projects = packagesAndProjects.map(\.1)
            projects.append(
                try buildAggregateProject(
                    packagesAndProjects: packagesAndProjects,
                    observabilityScope: observabilityScope
                )
            )

            let workspace = PIF.Workspace(
                guid: "Workspace:\(rootPackage.path.pathString)",
                name: rootPackage.manifest.displayName, // TODO: use identity instead?
                path: rootPackage.path,
                projects: projects
            )

            return PIF.TopLevelObject(workspace: workspace)
        }
    }
    
    #endif

    // Convenience method for generating PIF.
    public static func generatePIF(
        buildParameters: BuildParameters,
        packageGraph: ModulesGraph,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        preservePIFModelStructure: Bool
    ) throws -> String {
        let parameters = PIFBuilderParameters(buildParameters, supportedSwiftVersions: [])
        let builder = Self(
            graph: packageGraph,
            parameters: parameters,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )
        return try builder.generatePIF(preservePIFModelStructure: preservePIFModelStructure)
    }
}

#if canImport(SwiftBuild)

fileprivate final class PackagePIFBuilderDelegate: PackagePIFBuilder.BuildDelegate {
    let package: ResolvedPackage
    
    init(package: ResolvedPackage) {
        self.package = package
    }
    
    var isRootPackage: Bool {
        self.package.manifest.packageKind.isRoot
    }
    
    var hostsOnlyPackages: Bool {
        false
    }
    
    var isUserManaged: Bool {
        true
    }
    
    var isBranchOrRevisionBased: Bool {
        false
    }
    
    func customProductType(forExecutable product: PackageModel.Product) -> ProjectModel.Target.ProductType? {
        nil
    }
    
    func deviceFamilyIDs() -> Set<Int> {
        []
    }
    
    var shouldiOSPackagesBuildForARM64e: Bool {
        false
    }
    
    var isPluginExecutionSandboxingDisabled: Bool {
        false
    }
    
    func configureProjectBuildSettings(_ buildSettings: inout ProjectModel.BuildSettings) {
        /* empty */
    }
    
    func configureSourceModuleBuildSettings(sourceModule: ResolvedModule, settings: inout ProjectModel.BuildSettings) {
        /* empty */
    }
    
    func customInstallPath(product: PackageModel.Product) -> String? {
        nil
    }
    
    func customExecutableName(product: PackageModel.Product) -> String? {
        nil
    }
    
    func customLibraryType(product: PackageModel.Product) -> PackageModel.ProductType.LibraryType? {
        nil
    }
    
    func customSDKOptions(forPlatform: PackageModel.Platform) -> [String] {
        []
    }
    
    func addCustomTargets(pifProject: SwiftBuild.ProjectModel.Project) throws -> [PackagePIFBuilder.ModuleOrProduct] {
        return []
    }
    
    func shouldSuppressProductDependency(product: PackageModel.Product, buildSettings: inout SwiftBuild.ProjectModel.BuildSettings) -> Bool {
        false
    }
    
    func shouldSetInstallPathForDynamicLib(productName: String) -> Bool {
        false
    }
    
    func configureLibraryProduct(
        product: PackageModel.Product,
        target: WritableKeyPath<ProjectModel.Project, ProjectModel.Target>,
        additionalFiles: WritableKeyPath<ProjectModel.Group, ProjectModel.Group>
    ) {
        /* empty */
    }
    
    func suggestAlignedPlatformVersionGiveniOSVersion(platform: PackageModel.Platform, iOSVersion: PackageModel.PlatformVersion) -> String? {
        nil
    }
    
    func validateMacroFingerprint(for macroModule: ResolvedModule) -> Bool {
        true
    }
}

fileprivate func buildAggregateProject(
    packagesAndProjects: [(package: ResolvedPackage, project: ProjectModel.Project)],
    observabilityScope: ObservabilityScope
) throws -> ProjectModel.Project {
    precondition(!packagesAndProjects.isEmpty)
    
    var aggregateProject = ProjectModel.Project(
        id: "AGGREGATE",
        path: packagesAndProjects[0].project.path,
        projectDir: packagesAndProjects[0].project.projectDir,
        name: "Aggregate",
        developmentRegion: "en"
    )
    observabilityScope.logPIF(.debug, "Created project '\(aggregateProject.id)' with name '\(aggregateProject.name)'")
    
    var settings = ProjectModel.BuildSettings()
    settings[.PRODUCT_NAME] = "$(TARGET_NAME)"
    settings[.SUPPORTED_PLATFORMS] = ["$(AVAILABLE_PLATFORMS)"]
    settings[.SDKROOT] = "auto"
    settings[.SDK_VARIANT] = "auto"
    settings[.SKIP_INSTALL] = "YES"
    
    aggregateProject.addBuildConfig { id in BuildConfig(id: id, name: "Debug", settings: settings) }
    aggregateProject.addBuildConfig { id in BuildConfig(id: id, name: "Release", settings: settings) }
    
    func addEmptyBuildConfig(
        to targetKeyPath: WritableKeyPath<ProjectModel.Project, ProjectModel.AggregateTarget>,
        name: String
    ) {
        let emptySettings = BuildSettings()
        aggregateProject[keyPath: targetKeyPath].common.addBuildConfig { id in
            BuildConfig(id: id, name: name, settings: emptySettings)
        }
    }
    
    let allIncludingTestsTargetKeyPath = try aggregateProject.addAggregateTarget { _ in
        ProjectModel.AggregateTarget(
            id: "ALL-INCLUDING-TESTS",
            name: PIFBuilder.allIncludingTestsTargetName
        )
    }
    addEmptyBuildConfig(to: allIncludingTestsTargetKeyPath, name: "Debug")
    addEmptyBuildConfig(to: allIncludingTestsTargetKeyPath, name: "Release")
    
    let allExcludingTestsTargetKeyPath = try aggregateProject.addAggregateTarget { _ in
        ProjectModel.AggregateTarget(
            id: "ALL-EXCLUDING-TESTS",
            name: PIFBuilder.allExcludingTestsTargetName
        )
    }
    addEmptyBuildConfig(to: allExcludingTestsTargetKeyPath, name: "Debug")
    addEmptyBuildConfig(to: allExcludingTestsTargetKeyPath, name: "Release")
    
    for (package, packageProject) in packagesAndProjects where package.manifest.packageKind.isRoot {
        for target in packageProject.targets {
            switch target {
            case .target(let target):
                guard !target.id.hasSuffix(.dynamic) else {
                    // Otherwise we hit a bunch of "Unknown multiple commands produce: ..." errors,
                    // as the build artifacts from "PACKAGE-TARGET:Foo"
                    // conflicts with those from "PACKAGE-TARGET:Foo-dynamic".
                    continue
                }
                
                aggregateProject[keyPath: allIncludingTestsTargetKeyPath].common.addDependency(
                    on: target.id,
                    platformFilters: [],
                    linkProduct: false
                )
                if target.productType != .unitTest {
                    aggregateProject[keyPath: allExcludingTestsTargetKeyPath].common.addDependency(
                        on: target.id,
                        platformFilters: [],
                        linkProduct: false
                    )
                }
            case .aggregate:
                break
            }
        }
    }
    
    do {
        let allIncludingTests = aggregateProject[keyPath: allIncludingTestsTargetKeyPath]
        let allExcludingTests = aggregateProject[keyPath: allExcludingTestsTargetKeyPath]
        
        observabilityScope.logPIF(
            .debug,
            indent: 1,
            "Created target '\(allIncludingTests.id)' with name '\(allIncludingTests.name)' " +
            "and \(allIncludingTests.common.dependencies.count) (unlinked) dependencies"
        )
        observabilityScope.logPIF(
            .debug,
            indent: 1,
            "Created target '\(allExcludingTests.id)' with name '\(allExcludingTests.name)' " +
            "and \(allExcludingTests.common.dependencies.count) (unlinked) dependencies"
        )
    }
    
    return aggregateProject
}

#endif

public enum PIFGenerationError: Error {
    case rootPackageNotFound, multipleRootPackagesFound
    
    case unsupportedSwiftLanguageVersions(
        targetName: String,
        versions: [SwiftLanguageVersion],
        supportedVersions: [SwiftLanguageVersion]
    )
}

extension PIFGenerationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .rootPackageNotFound:
            "No root package was found"

        case .multipleRootPackagesFound:
            "Multiple root packages were found, making the PIF generation (root packages) ordering sensitive"

        case .unsupportedSwiftLanguageVersions(
            targetName: let target,
            versions: let given,
            supportedVersions: let supported
        ):
            "None of the Swift language versions used in target '\(target)' settings are supported." +
            " (given: \(given), supported: \(supported))"
        }
    }
}
