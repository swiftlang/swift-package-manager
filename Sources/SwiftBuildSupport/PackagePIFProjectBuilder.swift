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
import struct Basics.Diagnostic
import class Basics.ObservabilitySystem
import struct Basics.SourceControlURL

import class PackageModel.Manifest
import struct PackageModel.Platform
import class PackageModel.Product
import struct PackageModel.Resource
import struct PackageModel.ToolsVersion

import struct PackageGraph.ModulesGraph
import struct PackageGraph.ResolvedModule
import struct PackageGraph.ResolvedPackage

import struct PackageLoading.FileRuleDescription
import struct PackageLoading.TargetSourcesBuilder

import enum SwiftBuild.ProjectModel
import struct SwiftBuild.SwiftBuildFileType
import struct SwiftBuild.Pair

/// Helper type to create PIF **project** and **targets** for a given package.
struct PackagePIFProjectBuilder {
    let pifBuilder: PIFPackageBuilder
    let package: PackageGraph.ResolvedPackage
    let packageManifest: PackageModel.Manifest
    let modulesGraph: PackageGraph.ModulesGraph

    var pif: ProjectModel.Project // TODO: Let's rename to `project` instead?
    let binaryGroup: ProjectModel.Group
    let additionalFilesGroup: ProjectModel.Group

    let declaredPlatforms: [PackageModel.Platform]?
    let deploymentTargets: [PackageModel.Platform: String?]

    /// Current set of names of any package products that are explicitly declared dynamic libraries.
    private let dynamicLibraryProductNames: Set<String>

    /// FIXME: We should eventually clean this up but right now we have to carry over this
    /// bit of information from processing the *products* to processing the *targets*.
    var mainModuleTargetNamesWithResources: Set<String> = []

    var builtModulesAndProducts: [PIFPackageBuilder.ModuleOrProduct]

    func log(
        _ severity: Diagnostic.Severity,
        _ message: String,
        sourceFile: StaticString = #fileID,
        sourceLine: UInt = #line
    ) {
        self.pifBuilder.log(severity, message, sourceFile: sourceFile, sourceLine: sourceLine)
    }

    init(createForPackage package: PackageGraph.ResolvedPackage, builder: PIFPackageBuilder) {
        // Create a PIF project using an identifier that's based on the normalized absolute path of the package.
        // We use the package manifest path as the project path, and the package path as the project's base source
        // directory.
        // FIXME: The PIF creation should ideally be done on a background thread.
        var pifProject = ProjectModel.Project(
            id: "PACKAGE:\(package.identity)",
            path: package.manifest.path.pathString,
            projectDir: package.path.pathString,
            name: package.name,
            developmentRegion: package.manifest.defaultLocalization
        )

        let additionalFilesGroupKP = pifProject.mainGroup.addGroup { id in
            ProjectModel.Group(
                id: id,
                path: "/",
                pathBase: .absolute,
                name: "AdditionalFiles"
            )
        }
        let binaryGroupKP = pifProject.mainGroup.addGroup { id in
            ProjectModel.Group(
                id: id,
                path: "/",
                pathBase: .absolute,
                name: "Binaries"
            )
        }
        
        // Test modules have a higher minimum deployment target by default,
        // so we favor non-test modules as representative for the package's deployment target.
        let firstModule = package.modules.first { $0.type != .test } ?? package.modules.first

        let moduleDeploymentTargets = firstModule?.deploymentTargets(using: builder.delegate)

        // The deployment targets are passed through to the eventual `ModuleOrProduct` values,
        // so that querying them yields reasonable results for those build settings.
        var deploymentTargets: [PackageModel.Platform: String?] = [
            .macOS: moduleDeploymentTargets?[.macOS],
            .macCatalyst: moduleDeploymentTargets?[.macCatalyst],
            .iOS: moduleDeploymentTargets?[.iOS],
            .tvOS: moduleDeploymentTargets?[.tvOS],
            .watchOS: moduleDeploymentTargets?[.watchOS],
            .driverKit: moduleDeploymentTargets?[.driverKit],
        ]
        deploymentTargets[.visionOS] = moduleDeploymentTargets?[.visionOS]
        let declaredPlatforms = firstModule?.declaredPlatforms

        // Compute the names of all explicitly dynamic library products, we need to avoid
        // name clashes with any package targets we could decide to build dynamically.
        let allPackages = builder.modulesGraph.packages
        let dynamicLibraryProductNames = Set(
            allPackages
                .flatMap(\.products)
                .filter { $0.type == .library(.dynamic) }
                .map(\.name)
        )

        self.pifBuilder = builder
        self.package = package
        self.packageManifest = self.pifBuilder.packageManifest
        self.modulesGraph = self.pifBuilder.modulesGraph
        self.pif = pifProject
        self.binaryGroup = pifProject.mainGroup[keyPath: binaryGroupKP]
        self.additionalFilesGroup = pifProject.mainGroup[keyPath: additionalFilesGroupKP]
        self.declaredPlatforms = declaredPlatforms
        self.deploymentTargets = deploymentTargets
        self.dynamicLibraryProductNames = dynamicLibraryProductNames
        self.builtModulesAndProducts = []
    }

    // MARK: - Handling Resources

    mutating func addResourceBundle(
        for module: PackageGraph.ResolvedModule,
        pifTargetKeyPath pifTargetKP: WritableKeyPath<ProjectModel.Project, ProjectModel.Target>,
        generatedResourceFiles: [String]
    ) throws -> (PIFPackageBuilder.EmbedResourcesResult, PIFPackageBuilder.ModuleOrProduct?) {
        if module.resources.isEmpty && generatedResourceFiles.isEmpty {
            return (PIFPackageBuilder.EmbedResourcesResult(
                bundleName: nil,
                shouldGenerateBundleAccessor: false,
                shouldGenerateEmbedInCodeAccessor: false
            ), nil)
        }

        let bundleName = self.resourceBundleName(forModuleName: module.name)
        let resourceBundleGUID = self.pifTargetIdForResourceBundle(module.name)
        let resourcesTargetKP = try self.pif.addTarget { id in
            ProjectModel.Target(
                id: resourceBundleGUID,
                productType: .bundle,
                name: bundleName,
                productName: bundleName
            )
        }
        var resourcesTarget: ProjectModel.Target { self.pif[keyPath: resourcesTargetKP] }

        self.pif[keyPath: pifTargetKP].common.addDependency(
            on: resourcesTarget.id,
            platformFilters: [],
            linkProduct: false
        )
        self.log(.debug, ".. added dependency on resource target '\(resourcesTarget.id)'")

        for pluginModule in module.pluginsAppliedToModule {
            self.pif[keyPath: resourcesTargetKP].common.addDependency(
                on: pluginModule.pifTargetGUID(),
                platformFilters: [],
                linkProduct: false
            )
        }

        self.log(
            .debug,
            ".. created \(type(of: resourcesTarget)) '\(resourcesTarget.id)' of type '\(resourcesTarget.productType)' with name '\(resourcesTarget.name)' and product name '\(resourcesTarget.productName)'"
        )

        var settings: ProjectModel.BuildSettings = self.package.underlying.packageBaseBuildSettings
        settings[.TARGET_NAME] = bundleName
        settings[.PRODUCT_NAME] = "$(TARGET_NAME)"
        settings[.PRODUCT_MODULE_NAME] = bundleName
        settings[.PRODUCT_BUNDLE_IDENTIFIER] = "\(self.package.identity).\(module.name).resources"
            .spm_mangledToBundleIdentifier()
        settings[.EXECUTABLE_NAME] = ""
        settings[.GENERATE_INFOPLIST_FILE] = "YES"
        settings[.PACKAGE_RESOURCE_TARGET_KIND] = "resource"

        settings[.COREML_COMPILER_CONTAINER] = "swift-package"
        settings[.COREML_CODEGEN_LANGUAGE] = "None"

        self.pif[keyPath: resourcesTargetKP].common.addBuildConfig { id in
            BuildConfig(id: id, name: "Debug", settings: settings)
        }
        self.pif[keyPath: resourcesTargetKP].common.addBuildConfig { id in
            BuildConfig(id: id, name: "Release", settings: settings)
        }

        let result = self.processResources(
            for: module,
            sourceModulePifTargetKP: pifTargetKP,
            resourceBundlePifTargetKP: resourcesTargetKP,
            generatedResourceFiles: generatedResourceFiles
        )

        let resourceBundle = PIFPackageBuilder.ModuleOrProduct(
            type: .resourceBundle,
            name: bundleName,
            moduleName: bundleName,
            pifTarget: .target(resourcesTarget),
            indexableFileURLs: [],
            headerFiles: [],
            linkedPackageBinaries: [],
            swiftLanguageVersion: nil,
            declaredPlatforms: [],
            deploymentTargets: [:]
        )

        return (result, resourceBundle)
    }

    mutating func processResources(
        for module: PackageGraph.ResolvedModule,
        sourceModulePifTargetKP: WritableKeyPath<ProjectModel.Project, ProjectModel.Target>,
        resourceBundlePifTargetKP: WritableKeyPath<ProjectModel.Project, ProjectModel.Target>?,
        generatedResourceFiles: [String]
    ) -> PIFPackageBuilder.EmbedResourcesResult {
        if module.resources.isEmpty && generatedResourceFiles.isEmpty {
            return PIFPackageBuilder.EmbedResourcesResult(
                bundleName: nil,
                shouldGenerateBundleAccessor: false,
                shouldGenerateEmbedInCodeAccessor: false
            )
        }
        // If `resourceBundlePifTarget` is nil, we add resources to the `sourceModulePifTarget`.
        let pifTargetForResourcesKP = resourceBundlePifTargetKP ?? sourceModulePifTargetKP

        // Generated resources get a default treatment for rule and localization.
        let generatedResources = generatedResourceFiles.compactMap {
            PIFPackageBuilder.Resource(path: $0, rule: .process(localization: nil))
        }

        let resources = module.resources.map { PIFPackageBuilder.Resource($0) } + generatedResources
        let shouldGenerateBundleAccessor = resources.anySatisfy { $0.rule != .embedInCode }
        let shouldGenerateEmbedInCodeAccessor = resources.anySatisfy { $0.rule == .embedInCode }

        for resource in resources {
            let resourcePath = resource.path
            // Add a file reference for the resource. We use an absolute path, as for all the other files,
            // but we should be able to optimize this later by making it group-relative.
            let ref = self.pif.mainGroup.addFileReference { id in
                ProjectModel.FileReference(id: id, path: resourcePath, pathBase: .absolute)
            }

            // CoreData files should also be in the actual target because they
            // can end up generating code during the build.
            // The build system will only perform codegen tasks for the main target in this case.
            let isCoreDataFile = [SWBProjectModel.SwiftBuildFileType.xcdatamodeld, .xcdatamodel]
                .contains { $0.fileTypes.contains(resourcePath.pathExtension) }

            if isCoreDataFile {
                self.pif[keyPath: sourceModulePifTargetKP].addSourceFile { id in
                    BuildFile(id: id, fileRef: ref)
                }
                self.log(.debug, ".. .. added core data resource as source file '\(resourcePath)'")
            }

            // Core ML files need to be included in the source module as well, because there is code generation.
            let coreMLFileTypes: [SWBProjectModel.SwiftBuildFileType] = [.mlmodel, .mlpackage]
            let isCoreMLFile = coreMLFileTypes.contains { $0.fileTypes.contains(resourcePath.pathExtension) }

            if isCoreMLFile {
                self.pif[keyPath: sourceModulePifTargetKP].addSourceFile { id in
                    BuildFile(id: id, fileRef: ref, generatedCodeVisibility: .public)
                }
                self.log(.debug, ".. .. added coreml resource as source file '\(resourcePath)'")
            }
            
            // Metal source code needs to be added to the source build phase.
            let isMetalFile = SWBProjectModel.SwiftBuildFileType.metal.fileTypes.contains(resourcePath.pathExtension)

            if isMetalFile {
                self.pif[keyPath: pifTargetForResourcesKP].addSourceFile { id in
                    BuildFile(id: id, fileRef: ref)
                }
            } else {
                // FIXME: Handle additional rules here (e.g. `.copy`).
                self.pif[keyPath: pifTargetForResourcesKP].addResourceFile { id in
                    BuildFile(
                        id: id,
                        fileRef: ref,
                        platformFilters: [],
                        resourceRule: resource.rule == .embedInCode ? .embedInCode : .process
                    )
                }
            }

            // Asset Catalogs need to be included in the sources modules for generated asset symbols.
            let isAssetCatalog = resourcePath.pathExtension == "xcassets"
            if isAssetCatalog {
                self.pif[keyPath: sourceModulePifTargetKP].addSourceFile { id in
                    BuildFile(id: id, fileRef: ref)
                }
                self.log(.debug, ".. .. added asset catalog as source file '\(resourcePath)'")
            }

            self.log(.debug, ".. .. added resource file '\(resourcePath)'")
        }
        
        let resourceBundlePifTargetName: String? = if let resourceBundlePifTargetKP {
            self.pif[keyPath: resourceBundlePifTargetKP].name
        } else {
            nil
        }
        return PIFPackageBuilder.EmbedResourcesResult(
            bundleName: resourceBundlePifTargetName,
            shouldGenerateBundleAccessor: shouldGenerateBundleAccessor,
            shouldGenerateEmbedInCodeAccessor: shouldGenerateEmbedInCodeAccessor
        )
    }

    func resourceBundleTargetKeyPath(forModuleName name: String) -> WritableKeyPath<ProjectModel.Project, ProjectModel.Target>? {
        let resourceBundleGUID = self.pifTargetIdForResourceBundle(name)
        let targetKP = self.pif.findTarget(id: resourceBundleGUID)
        return targetKP
    }

    func pifTargetIdForResourceBundle(_ name: String) -> GUID {
        GUID("PACKAGE-RESOURCE:\(name)")
    }

    func resourceBundleName(forModuleName name: String) -> String {
        "\(self.package.name)_\(name)"
    }

    // MARK: - Plugin Helpers

    /// Helper function that compiles the plugin-generated files for a target,
    /// optionally also adding the corresponding plugin-provided commands to the PIF target.
    ///
    /// The reason we might not add them is that some targets are derivatives of other targets — in such cases,
    /// only the primary target adds the build tool commands to the PIF target.
    func computePluginGeneratedFiles(
        module: PackageGraph.ResolvedModule,
        pifTarget: inout ProjectModel.Target,
        addBuildToolPluginCommands: Bool
    ) -> (sourceFilePaths: [AbsolutePath], resourceFilePaths: [String]) {
        guard let pluginResult = pifBuilder.buildToolPluginResultsByTargetName[module.name] else {
            // We found no results for the target.
            return (sourceFilePaths: [], resourceFilePaths: [])
        }

        // Process the results of applying any build tool plugins on the target.
        // If we've been asked to add build tool commands for the result, we do so now.
        if addBuildToolPluginCommands {
            for command in pluginResult.buildCommands {
                self.addBuildToolCommand(command, to: &pifTarget)
            }
        }

        // Process all the paths of derived output paths using the same rules as for source.
        let result = self.process(
            pluginGeneratedFilePaths: pluginResult.allDerivedOutputPaths,
            forModule: module,
            toolsVersion: self.package.manifest.toolsVersion
        )
        return (
            sourceFilePaths: result.sourceFilePaths,
            resourceFilePaths: result.resourceFilePaths.map(\.path.pathString)
        )
    }

    /// Helper function for adding build tool commands to the right PIF target depending on whether they generate
    /// sources or resources.
    func addBuildToolCommands(
        module: PackageGraph.ResolvedModule,
        sourceModulePifTarget: inout ProjectModel.Target,
        resourceBundlePifTarget: inout ProjectModel.Target,
        sourceFilePaths: [AbsolutePath],
        resourceFilePaths: [String]
    ) {
        guard let pluginResult = pifBuilder.buildToolPluginResultsByTargetName[module.name] else {
            return
        }

        for command in pluginResult.buildCommands {
            let producesResources = Set(command.outputPaths).intersection(resourceFilePaths).hasContent

            if producesResources {
                self.addBuildToolCommand(command, to: &resourceBundlePifTarget)
            } else {
                self.addBuildToolCommand(command, to: &sourceModulePifTarget)
            }
        }
    }

    /// Adds build rules to `pifTarget` for any build tool   commands from invocation results.
    /// Returns the absolute paths of any generated source files that should be added to the sources build phase of the
    /// PIF target.
    func addBuildToolCommands(
        from pluginInvocationResults: [PIFPackageBuilder.BuildToolPluginInvocationResult],
        pifTarget: inout ProjectModel.Target,
        addBuildToolPluginCommands: Bool
    ) -> [String] {
        var generatedSourceFileAbsPaths: [String] = []
        for result in pluginInvocationResults {
            // Create build rules for all the commands in the result.
            if addBuildToolPluginCommands {
                for command in result.buildCommands {
                    self.addBuildToolCommand(command, to: &pifTarget)
                }
            }
            // Add the paths of the generated source files, so that they can be added to the Sources build phase.
            generatedSourceFileAbsPaths.append(contentsOf: result.allDerivedOutputPaths.map(\.pathString))
        }
        return generatedSourceFileAbsPaths
    }

    /// Adds a single plugin-created build command to a PIF target.
    func addBuildToolCommand(
        _ command: PIFPackageBuilder.CustomBuildCommand,
        to pifTarget: inout ProjectModel.Target
    ) {
        var commandLine = [command.executable] + command.arguments
        if let sandbox = command.sandboxProfile, !pifBuilder.delegate.isPluginExecutionSandboxingDisabled {
            commandLine = try! sandbox.apply(to: commandLine)
        }

        pifTarget.customTasks.append(
            ProjectModel.CustomTask(
                commandLine: commandLine,
                environment: command.environment.map { Pair($0, $1) }.sorted(by: <),
                workingDirectory: command.workingDir?.pathString,
                executionDescription: command.displayName ?? "Performing build tool plugin command",
                inputFilePaths: [command.executable] + command.inputPaths.map(\.pathString),
                outputFilePaths: command.outputPaths,
                enableSandboxing: false,
                preparesForIndexing: true
            )
        )
    }

    /// Processes the paths of plugin-generated files for a particular package target,
    /// returning paths of those that should be treated as sources vs resources.
    private func process(
        pluginGeneratedFilePaths: [AbsolutePath],
        forModule module: PackageGraph.ResolvedModule,
        toolsVersion: PackageModel.ToolsVersion?
    ) -> (sourceFilePaths: [AbsolutePath], resourceFilePaths: [Resource]) {
        precondition(module.isSourceModule)

        // If we have no tools version, all files are treated as *source* files.
        guard let toolsVersion else {
            return (sourceFilePaths: pluginGeneratedFilePaths, resourceFilePaths: [])
        }

        // FIXME: Will be fixed by <rdar://144802163> (SwiftPM PIFBuilder — adopt ObservabilityScope as the logging API).
        let observabilityScope = ObservabilitySystem.NOOP

        // Use the `TargetSourcesBuilder` from libSwiftPM to split the generated files into sources and resources.
        let (generatedSourcePaths, generatedResourcePaths) = TargetSourcesBuilder.computeContents(
            for: pluginGeneratedFilePaths,
            toolsVersion: toolsVersion,
            additionalFileRules: Self.additionalFileRules,
            defaultLocalization: module.defaultLocalization,
            targetName: module.name,
            targetPath: module.path,
            observabilityScope: observabilityScope
        )

        // FIXME: We are not handling resource rules here, but the same is true for non-generated resources.
        // (Today, everything gets essentially treated as `.processResource` even if it may have been declared as
        // `.copy` in the manifest.)
        return (generatedSourcePaths, generatedResourcePaths)
    }

    private static let additionalFileRules: [FileRuleDescription] =
        FileRuleDescription.xcbuildFileTypes + [
            FileRuleDescription(
                rule: .compile,
                toolsVersion: .v5_5,
                fileTypes: ["docc"]
            ),
            FileRuleDescription(
                rule: .processResource(localization: .none),
                toolsVersion: .v5_7,
                fileTypes: ["mlmodel", "mlpackage"]
            ),
            FileRuleDescription(
                rule: .processResource(localization: .none),
                toolsVersion: .v5_7,
                fileTypes: ["rkassets"] // visionOS
            ),
        ]

    // MARK: - General Helpers

    func installPath(for product: PackageModel.Product) -> String {
        if let customInstallPath = pifBuilder.delegate.customInstallPath(product: product) {
            customInstallPath
        } else {
            "/usr/local/lib"
        }
    }

    /// Always create a dynamic variant for targets, for automatic resolution of diamond problems,
    /// unless there is a potential name clash with an explicitly *dynamic library* product.
    ///
    /// Swift Build will emit a diagnostic if such a package target is part of a diamond.
    func shouldOfferDynamicTarget(_ targetName: String) -> Bool {
        !self.dynamicLibraryProductNames.contains(targetName)
    }
}
