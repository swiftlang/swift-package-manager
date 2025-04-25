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
import TSCUtility

import struct Basics.AbsolutePath
import class Basics.ObservabilitySystem
import func Basics.resolveSymlinks
import struct Basics.SourceControlURL

import class PackageModel.Manifest
import class PackageModel.Module
import class PackageModel.Product
import class PackageModel.SystemLibraryModule

import struct PackageGraph.ResolvedModule
import struct PackageGraph.ResolvedPackage

#if canImport(SwiftBuild)

import enum SwiftBuild.ProjectModel

/// Extension to create PIF **modules** for a given package.
extension PackagePIFProjectBuilder {
    // MARK: - Plugin Modules

    mutating func makePluginModule(_ pluginModule: PackageGraph.ResolvedModule) throws {
        precondition(pluginModule.type == .plugin)

        // Create an executable PIF target in order to get specialization.
        let pluginTargetKeyPath = try self.project.addTarget { _ in
            ProjectModel.Target(
                id: pluginModule.pifTargetGUID,
                productType: .executable,
                name: pluginModule.name,
                productName: pluginModule.name
            )
        }
        do {
            let pluginTarget = self.project[keyPath: pluginTargetKeyPath]
            log(
                .debug,
                "Created target '\(pluginTarget.id)' of type " +
                "\(pluginTarget.productType) and name '\(pluginTarget.name)'"
            )
        }

        var buildSettings: ProjectModel.BuildSettings = self.package.underlying.packageBaseBuildSettings

        // Add the dependencies.
        pluginModule.recursivelyTraverseDependencies { dependency in
            switch dependency {
            case .module(let moduleDependency, let packageConditions):
                // This assertion is temporarily disabled since we may see targets from
                // _other_ packages, but this should be resolved; see rdar://95467710.
                /* assert(moduleDependency.packageName == self.package.name) */

                let dependencyPlatformFilters = packageConditions
                    .toPlatformFilter(toolsVersion: self.package.manifest.toolsVersion)

                switch moduleDependency.type {
                case .executable, .snippet:
                    // For executable targets, add a build time dependency on the product.
                    // FIXME: Maybe we should we do this at the libSwiftPM level.
                    let moduleProducts = self.package.products.filter(\.isMainModuleProduct)
                    let productDependency = moduleDependency
                        .productRepresentingDependencyOfBuildPlugin(in: moduleProducts)

                    if let productDependency {
                        self.project[keyPath: pluginTargetKeyPath].common.addDependency(
                            on: productDependency.pifTargetGUID,
                            platformFilters: dependencyPlatformFilters
                        )
                        log(.debug, indent: 1, "Added dependency on product '\(productDependency.pifTargetGUID)'")
                    } else {
                        log(
                            .debug,
                            indent: 1,
                            "Could not find a build plugin product to depend on for target '\(moduleDependency.pifTargetGUID)'"
                        )
                    }

                case .library, .systemModule, .test, .binary, .plugin, .macro:
                    let dependencyGUID = moduleDependency.pifTargetGUID
                    self.project[keyPath: pluginTargetKeyPath].common.addDependency(
                        on: dependencyGUID,
                        platformFilters: dependencyPlatformFilters
                    )
                    log(.debug, indent: 1, "Added dependency on target '\(dependencyGUID)'")
                }

            case .product(let productDependency, let packageConditions):
                // Do not add a dependency for binary-only executable products since they are not part of the build.
                if productDependency.isBinaryOnlyExecutableProduct {
                    break
                }

                if !pifBuilder.delegate.shouldSuppressProductDependency(
                    product: productDependency.underlying,
                    buildSettings: &buildSettings
                ) {
                    let dependencyGUID = productDependency.pifTargetGUID
                    let dependencyPlatformFilters = packageConditions
                        .toPlatformFilter(toolsVersion: self.package.manifest.toolsVersion)

                    self.project[keyPath: pluginTargetKeyPath].common.addDependency(
                        on: dependencyGUID,
                        platformFilters: dependencyPlatformFilters
                    )
                    log(.debug, indent: 1, "Added dependency on product '\(dependencyGUID)'")
                }
            }
        }

        // Any dependencies of plugin targets need to be built for the host.
        buildSettings[.SUPPORTED_PLATFORMS] = ["$(HOST_PLATFORM)"]

        self.project[keyPath: pluginTargetKeyPath].common.addBuildConfig { id in
            BuildConfig(id: id, name: "Debug", settings: buildSettings)
        }
        self.project[keyPath: pluginTargetKeyPath].common.addBuildConfig { id in
            BuildConfig(id: id, name: "Release", settings: buildSettings)
        }

        let pluginModuleMetadata = PackagePIFBuilder.ModuleOrProduct(
            type: .plugin,
            name: pluginModule.name,
            moduleName: pluginModule.name,
            pifTarget: .target(self.project[keyPath: pluginTargetKeyPath]),
            indexableFileURLs: [],
            headerFiles: [],
            linkedPackageBinaries: [],
            swiftLanguageVersion: nil,
            declaredPlatforms: self.declaredPlatforms,
            deploymentTargets: self.deploymentTargets
        )
        self.builtModulesAndProducts.append(pluginModuleMetadata)
    }

    // MARK: - Macro Modules

    mutating func makeMacroModule(_ macroModule: PackageGraph.ResolvedModule) throws {
        precondition(macroModule.type == .macro)

        let (builtMacroModule, _) = try buildSourceModule(macroModule, type: .macro)
        self.builtModulesAndProducts.append(builtMacroModule)

        // We also create a testable version of the macro, similar to what we're doing for regular executable targets.
        let (builtTestableMacroModule, _) = try buildSourceModule(
            macroModule,
            type: .executable,
            targetSuffix: .testable
        )
        self.builtModulesAndProducts.append(builtTestableMacroModule)
    }

    // MARK: - Library Modules

    // Build a *static library* that can be linked together into other products.
    mutating func makeLibraryModule(_ libraryModule: PackageGraph.ResolvedModule) throws {
        precondition(libraryModule.type == .library)

        let (staticLibrary, resourceBundleName) = try buildSourceModule(libraryModule, type: .staticLibrary)
        self.builtModulesAndProducts.append(staticLibrary)

        if self.shouldOfferDynamicTarget(libraryModule.name) {
            var (dynamicLibraryVariant, _) = try buildSourceModule(
                libraryModule,
                type: .dynamicLibrary,
                targetSuffix: .dynamic,
                addBuildToolPluginCommands: false,
                inputResourceBundleName: resourceBundleName
            )
            dynamicLibraryVariant.isDynamicLibraryVariant = true
            self.builtModulesAndProducts.append(dynamicLibraryVariant)

            guard let pifTarget = staticLibrary.pifTarget,
                  let pifTargetKeyPath = self.project.findTarget(id: pifTarget.id),
                  let dynamicPifTarget = dynamicLibraryVariant.pifTarget
            else {
                fatalError("Could not assign dynamic PIF target")
            }
            self.project[keyPath: pifTargetKeyPath].dynamicTargetVariantId = dynamicPifTarget.id
        }
    }

    // MARK: - Executable Source Modules

    /// If we're building an *executable* and the tools version is new enough,
    /// we also construct a testable version of said executable.
    mutating func makeTestableExecutableSourceModule(_ executableModule: PackageGraph.ResolvedModule) throws {
        precondition(executableModule.type == .executable)
        guard self.package.manifest.toolsVersion >= .v5_5 else { return }

        let inputResourceBundleName: String? = if mainModuleTargetNamesWithResources.contains(executableModule.name) {
            resourceBundleName(forModuleName: executableModule.name)
        } else {
            nil
        }

        let (testableExecutableModule, _) = try buildSourceModule(
            executableModule,
            type: .executable,
            targetSuffix: .testable,
            addBuildToolPluginCommands: false,
            inputResourceBundleName: inputResourceBundleName
        )
        self.builtModulesAndProducts.append(testableExecutableModule)
    }

    // MARK: - Source Modules

    enum SourceModuleType: String {
        case dynamicLibrary
        case staticLibrary
        case executable
        case macro
    }

    /// Constructs a *PIF target* for building a *module* target as a particular type.
    /// An optional target identifier suffix is passed when building variants of a target.
    @discardableResult
    private mutating func buildSourceModule(
        _ sourceModule: PackageGraph.ResolvedModule,
        type desiredModuleType: SourceModuleType,
        targetSuffix: TargetSuffix? = nil,
        addBuildToolPluginCommands: Bool = true,
        inputResourceBundleName: String? = nil
    ) throws -> (PackagePIFBuilder.ModuleOrProduct, resourceBundleName: String?) {
        precondition(sourceModule.isSourceModule)

        let pifProductName: String
        let executableName: String
        let productType: ProjectModel.Target.ProductType

        switch desiredModuleType {
        case .dynamicLibrary:
            if pifBuilder.createDylibForDynamicProducts { // We are re-using this default for dynamic targets as well.
                pifProductName = "lib\(sourceModule.name).dylib"
                executableName = pifProductName
                productType = .dynamicLibrary
            } else {
                pifProductName = sourceModule.name + ".framework"
                executableName = sourceModule.name
                productType = .framework
            }

        case .staticLibrary, .executable:
            pifProductName = "\(sourceModule.name).o"
            executableName = pifProductName
            productType = .objectFile

        case .macro:
            pifProductName = sourceModule.name
            executableName = pifProductName
            productType = .hostBuildTool
        }

        // Create a PIF target configured to build a single .o file.
        // For now wrapped in a static archive, since Swift Build can *not* yet produce a single .o as an output.

        // Macros are currently the only target type that requires explicit approval by users.
        let approvedByUser: Bool = if desiredModuleType == .macro {
            // Look up the current approval status in the underlying fingerprint storage.
            pifBuilder.delegate.validateMacroFingerprint(for: sourceModule) == true
        } else {
            true
        }

        let sourceModuleTargetKeyPath = try self.project.addTarget { _ in
            ProjectModel.Target(
                id: sourceModule.pifTargetGUID(suffix: targetSuffix),
                productType: productType,
                name: "\(sourceModule.name)",
                productName: pifProductName,
                approvedByUser: approvedByUser
            )
        }
        do {
            let sourceModule = self.project[keyPath: sourceModuleTargetKeyPath]
            log(
                .debug,
                "Created target '\(sourceModule.id)' of type '\(sourceModule.productType)' " +
                "with name '\(sourceModule.name)' and product name '\(sourceModule.productName)'"
            )
        }

        // Deal with any generated source files or resource files.
        let (generatedSourceFiles, generatedResourceFiles) = computePluginGeneratedFiles(
            module: sourceModule,
            targetKeyPath: sourceModuleTargetKeyPath,
            addBuildToolPluginCommands: false
        )

        // Either create or reuse the resource bundle.
        var resourceBundleName = inputResourceBundleName
        let shouldGenerateBundleAccessor: Bool
        let shouldGenerateEmbedInCodeAccessor: Bool
        if resourceBundleName == nil && desiredModuleType != .executable && desiredModuleType != .macro {
            let (result, resourceBundle) = try addResourceBundle(
                for: sourceModule,
                targetKeyPath: sourceModuleTargetKeyPath,
                generatedResourceFiles: generatedResourceFiles
            )
            if let resourceBundle { self.builtModulesAndProducts.append(resourceBundle) }

            resourceBundleName = result.bundleName
            shouldGenerateBundleAccessor = result.shouldGenerateBundleAccessor
            shouldGenerateEmbedInCodeAccessor = result.shouldGenerateEmbedInCodeAccessor
        } else {
            // Here we have to assume we need both types of accessors which will always bring in Foundation into the
            // current target
            // through the bundle accessor and will lead to Swift Build evaluating all resources, but neither should
            // technically be a problem.
            // Would still be nice to eventually make this accurate which would require storing these in addition to
            // `inputResourceBundleName`.
            shouldGenerateBundleAccessor = true
            shouldGenerateEmbedInCodeAccessor = true
        }

        // Find the PIF target for the resource bundle, if any. Otherwise fall back to the module.
        let resourceBundleTargetKeyPath = self.resourceBundleTargetKeyPath(
            forModuleName: sourceModule.name
        ) ?? sourceModuleTargetKeyPath

        // Add build tool commands to the resource bundle target.
        if desiredModuleType != .executable && desiredModuleType != .macro && addBuildToolPluginCommands {
            addBuildToolCommands(
                module: sourceModule,
                sourceModuleTargetKeyPath: sourceModuleTargetKeyPath,
                resourceBundleTargetKeyPath: resourceBundleTargetKeyPath,
                sourceFilePaths: generatedSourceFiles,
                resourceFilePaths: generatedResourceFiles
            )
        }

        // Create a set of build settings that will be imparted to any target that depends on this one.
        var impartedSettings = BuildSettings()

        // Configure the target-wide build settings. The details depend on the kind of product we're building.
        var settings: BuildSettings = self.package.underlying.packageBaseBuildSettings

        if shouldGenerateBundleAccessor {
            settings[.GENERATE_RESOURCE_ACCESSORS] = "YES"
        }
        if shouldGenerateEmbedInCodeAccessor {
            settings[.GENERATE_EMBED_IN_CODE_ACCESSORS] = "YES"
        }

        // Generate a module map file, if needed.
        var moduleMapFileContents = ""
        var moduleMapFile = ""
        let generatedModuleMapDir = "$(GENERATED_MODULEMAP_DIR)"

        if sourceModule.usesSwift && desiredModuleType != .macro {
            // Generate ObjC compatibility header for Swift library targets.
            settings[.SWIFT_OBJC_INTERFACE_HEADER_DIR] = generatedModuleMapDir
            settings[.SWIFT_OBJC_INTERFACE_HEADER_NAME] = "\(sourceModule.name)-Swift.h"

            moduleMapFileContents = """
            module \(sourceModule.c99name) {
            header "\(sourceModule.name)-Swift.h"
            export *
            }
            """
            moduleMapFile = "\(generatedModuleMapDir)/\(sourceModule.name).modulemap"

            // We only need to impart this to C clients.
            impartedSettings[.OTHER_CFLAGS] = ["-fmodule-map-file=\(moduleMapFile)", "$(inherited)"]
        } else if sourceModule.moduleMapFileRelativePath == nil {
            // Otherwise, this is a C library module and we generate a modulemap if one is already not provided.
            if case .umbrellaHeader(let path) = sourceModule.moduleMapType {
                log(.debug, "\(package.name).\(sourceModule.name) generated umbrella header")
                moduleMapFileContents = """
                module \(sourceModule.c99name) {
                umbrella header "\(path)"
                export *
                }
                """
            } else if case .umbrellaDirectory(let path) = sourceModule.moduleMapType {
                log(.debug, "\(package.name).\(sourceModule.name) generated umbrella directory")
                moduleMapFileContents = """
                module \(sourceModule.c99name) {
                umbrella "\(path)"
                export *
                }
                """
            }
            if moduleMapFileContents.hasContent {
                // Pass the path of the module map up to all direct and indirect clients.
                moduleMapFile = "\(generatedModuleMapDir)/\(sourceModule.name).modulemap"
                impartedSettings[.OTHER_CFLAGS] = ["-fmodule-map-file=\(moduleMapFile)", "$(inherited)"]
                impartedSettings[.OTHER_SWIFT_FLAGS] = ["-Xcc", "-fmodule-map-file=\(moduleMapFile)", "$(inherited)"]
            }
        }

        if desiredModuleType == .dynamicLibrary {
            settings.configureDynamicSettings(
                productName: sourceModule.name,
                targetName: sourceModule.name,
                executableName: executableName,
                packageIdentity: package.identity,
                packageName: sourceModule.packageName,
                createDylibForDynamicProducts: pifBuilder.createDylibForDynamicProducts,
                installPath: "/usr/local/lib",
                delegate: pifBuilder.delegate
            )
        } else {
            settings[.TARGET_NAME] = sourceModule.name
            settings[.PRODUCT_NAME] = "$(TARGET_NAME)"
            settings[.PRODUCT_MODULE_NAME] = sourceModule.c99name
            settings[.PRODUCT_BUNDLE_IDENTIFIER] = "\(self.package.identity).\(sourceModule.name)"
                .spm_mangledToBundleIdentifier()
            settings[.EXECUTABLE_NAME] = executableName
            settings[.CLANG_ENABLE_MODULES] = "YES"
            settings[.GENERATE_MASTER_OBJECT_FILE] = "NO"
            settings[.STRIP_INSTALLED_PRODUCT] = "NO"

            // Macros build as executables, so they need slightly different
            // build settings from other module types which build a "*.o".
            if desiredModuleType == .macro {
                settings[.MACH_O_TYPE] = "mh_execute"
            } else {
                settings[.MACH_O_TYPE] = "mh_object"
                // Disable code coverage linker flags since we're producing .o files.
                // Otherwise, we will run into duplicated symbols when there are more than one targets that produce .o
                // as their product.
                settings[.CLANG_COVERAGE_MAPPING_LINKER_ARGS] = "NO"
            }
            settings[.SWIFT_PACKAGE_NAME] = sourceModule.packageName

            if desiredModuleType == .executable {
                // Tell the Swift compiler to produce an alternate entry point rather than the standard `_main` entry
                // point`,
                // so that we can link one or more testable executable modules together into a single test bundle.
                // This allows the test bundle to treat the executable as if it were any regular library module,
                // and will have access to all symbols except the main entry point its.
                settings[.OTHER_SWIFT_FLAGS].lazilyInitializeAndMutate(initialValue: ["$(inherited)"]) {
                    $0.append(contentsOf: ["-Xfrontend", "-entry-point-function-name"])
                    $0.append(contentsOf: ["-Xfrontend", "\(sourceModule.c99name)_main"])
                }

                // We have to give each target a unique name.
                settings[.TARGET_NAME] = sourceModule.name + targetSuffix.description(forName: sourceModule.name)

                // Redirect the built executable into a separate directory so it won't conflict with the real one.
                settings[.TARGET_BUILD_DIR] = "$(TARGET_BUILD_DIR)/ExecutableModules"

                // Don't install the Swift module of the testable side-built artifact, lest it conflict with the regular
                // one.
                // The modules should have compatible contents in any case — only the entry point function name is
                // different in the Swift module
                // (the actual runtime artifact is of course very different, and that's why we're building a separate
                // testable artifact).
                settings[.SWIFT_INSTALL_MODULE] = "NO"
            }

            if let aliases = sourceModule.moduleAliases {
                // Format each entry as "original_name=alias"
                let list = aliases.map { $0.0 + "=" + $0.1 }
                settings[.SWIFT_MODULE_ALIASES] = list.isEmpty ? nil : list
            }

            // We mark in the PIF that we are intentionally not offering a dynamic target here,
            // so we can emit a diagnostic if it is being requested by Swift Build.
            if !self.shouldOfferDynamicTarget(sourceModule.name) {
                settings[.PACKAGE_TARGET_NAME_CONFLICTS_WITH_PRODUCT_NAME] = "YES"
            }

            // We are setting this instead of `LD_DYLIB_INSTALL_NAME` because `mh_object` files
            // don't actually have install names, so we should not pass an install name to the linker.
            settings[.TAPI_DYLIB_INSTALL_NAME] = sourceModule.name
        }

        settings[.PACKAGE_RESOURCE_TARGET_KIND] = "regular"
        settings[.MODULEMAP_FILE_CONTENTS] = moduleMapFileContents
        settings[.MODULEMAP_PATH] = moduleMapFile
        settings[.DEFINES_MODULE] = "YES"

        // Settings for text-based API.
        // Due to rdar://78331694 (Cannot use TAPI for packages in contexts where we need to code-sign (e.g. apps))
        // we are only enabling TAPI in `configureSourceModuleBuildSettings`, if desired.
        settings[.SUPPORTS_TEXT_BASED_API] = "NO"

        // If the module includes C headers, we set up the HEADER_SEARCH_PATHS setting appropriately.
        if let includeDirAbsPath = sourceModule.includeDirAbsolutePath {
            // Let the target itself find its own headers.
            settings[.HEADER_SEARCH_PATHS] = [includeDirAbsPath.pathString, "$(inherited)"]
            log(.debug, indent: 1, "Added '\(includeDirAbsPath)' to HEADER_SEARCH_PATHS")

            // Also propagate this search path to all direct and indirect clients.
            impartedSettings[.HEADER_SEARCH_PATHS] = [includeDirAbsPath.pathString, "$(inherited)"]
            log(.debug, indent: 1, "Added '\(includeDirAbsPath)' to imparted HEADER_SEARCH_PATHS")
        }

        // Additional settings for the linker.
        let baselineOTHER_LDFLAGS: [String]
        let enableDuplicateLinkageCulling = UserDefaults.standard.bool(
            forKey: "IDESwiftPackagesEnableDuplicateLinkageCulling",
            defaultValue: true
        )
        if enableDuplicateLinkageCulling {
            baselineOTHER_LDFLAGS = [
                "-Wl,-no_warn_duplicate_libraries",
                "$(inherited)"
            ]
        } else {
            baselineOTHER_LDFLAGS = ["$(inherited)"]
        }
        impartedSettings[.OTHER_LDFLAGS] = (sourceModule.isCxx ? ["-lc++"] : []) + baselineOTHER_LDFLAGS
        impartedSettings[.OTHER_LDRFLAGS] = []
        log(
            .debug,
            indent: 1,
            "Added '\(impartedSettings[.OTHER_LDFLAGS]!)' to imparted OTHER_LDFLAGS"
        )

        // This should be only for dynamic targets, but that isn't possible today.
        // Improvement is tracked by rdar://77403529 (Only impart `PackageFrameworks` search paths to clients of dynamic
        // package targets and products).
        impartedSettings[.FRAMEWORK_SEARCH_PATHS] = ["$(BUILT_PRODUCTS_DIR)/PackageFrameworks", "$(inherited)"]
        log(
            .debug,
            indent: 1,
            "Added '\(impartedSettings[.FRAMEWORK_SEARCH_PATHS]!)' to imparted FRAMEWORK_SEARCH_PATHS"
        )

        // Set the appropriate language versions.
        settings[.SWIFT_VERSION] = sourceModule.packageSwiftLanguageVersion(manifest: packageManifest)
        settings[.GCC_C_LANGUAGE_STANDARD] = sourceModule.cLanguageStandard
        settings[.CLANG_CXX_LANGUAGE_STANDARD] = sourceModule.cxxLanguageStandard
        settings[.SWIFT_ENABLE_BARE_SLASH_REGEX] = "NO"

        // Create a group for the target's source files.
        //
        // For now we use an absolute path for it, but we should really make it be container-relative,
        // since it's always inside the package directory. Resolve symbolic links otherwise there will
        // be a mismatch between the paths that the index service is using for Swift Build queries,
        // and what paths Swift Build uses in its build description; such a mismatch would result
        // in the index service failing to get compiler arguments for source files of the target.
        let targetSourceFileGroupKeyPath = self.project.mainGroup.addGroup { id in
            ProjectModel.Group(
                id: id,
                path: try! resolveSymlinks(sourceModule.sourceDirAbsolutePath).pathString,
                pathBase: .absolute
            )
        }
        do {
            let targetSourceFileGroup = self.project.mainGroup[keyPath: targetSourceFileGroupKeyPath]
            log(.debug, indent: 1, "Added source file group '\(targetSourceFileGroup.path)'")
        }

        // Add a source file reference for each of the source files,
        // and also an indexable-file URL for each one.
        //
        // Symlinks should be resolved externally.
        var indexableFileURLs: [SourceControlURL] = []
        for sourcePath in sourceModule.sourceFileRelativePaths {
            let sourceFileRef = self.project.mainGroup[keyPath: targetSourceFileGroupKeyPath].addFileReference { id in
                FileReference(id: id, path: sourcePath.pathString, pathBase: .groupDir)
            }
            self.project[keyPath: sourceModuleTargetKeyPath].addSourceFile { id in
                BuildFile(id: id, fileRef: sourceFileRef)
            }
            indexableFileURLs.append(
                SourceControlURL(fileURLWithPath: sourceModule.sourceDirAbsolutePath.appending(sourcePath))
            )
            log(.debug, indent: 2, "Added source file '\(sourcePath)'")
        }
        for resource in sourceModule.resources {
            log(.debug, indent: 2, "Added resource file '\(resource.path)'")
            indexableFileURLs.append(SourceControlURL(fileURLWithPath: resource.path))
        }

        let headerFiles = Set(sourceModule.headerFileAbsolutePaths)

        // Add any additional source files emitted by custom build commands.
        for path in generatedSourceFiles {
            let sourceFileRef = self.project.mainGroup[keyPath: targetSourceFileGroupKeyPath].addFileReference { id in
                FileReference(id: id, path: path.pathString, pathBase: .absolute)
            }
            self.project[keyPath: sourceModuleTargetKeyPath].addSourceFile { id in
                BuildFile(id: id, fileRef: sourceFileRef)
            }
            log(.debug, indent: 2, "Added generated source file '\(path)'")
        }

        if let resourceBundle = resourceBundleName {
            impartedSettings[.EMBED_PACKAGE_RESOURCE_BUNDLE_NAMES] = ["$(inherited)", resourceBundle]
            settings[.PACKAGE_RESOURCE_BUNDLE_NAME] = resourceBundle
            settings[.COREML_CODEGEN_LANGUAGE] = sourceModule.usesSwift ? "Swift" : "Objective-C"
            settings[.COREML_COMPILER_CONTAINER] = "swift-package"
        }

        if desiredModuleType == .macro {
            settings[.SWIFT_IMPLEMENTS_MACROS_FOR_MODULE_NAMES] = [sourceModule.c99name]
        }
        if sourceModule.type == .macro {
            settings[.SKIP_BUILDING_DOCUMENTATION] = "YES"
        }

        // Handle the target's dependencies (but only link against them if needed).
        let shouldLinkProduct = (desiredModuleType == .dynamicLibrary) || (desiredModuleType == .macro)
        sourceModule.recursivelyTraverseDependencies { dependency in
            switch dependency {
            case .module(let moduleDependency, let packageConditions):
                // This assertion is temporarily disabled since we may see targets from
                // _other_ packages, but this should be resolved; see rdar://95467710.
                /* assert(moduleDependency.packageName == self.package.name) */

                let dependencyPlatformFilters = packageConditions
                    .toPlatformFilter(toolsVersion: self.package.manifest.toolsVersion)

                switch moduleDependency.type {
                case .executable, .snippet:
                    // Always depend on product of executable targets (if available).
                    // FIXME: Maybe we should we do this at the libSwiftPM level.
                    let moduleMainProducts = self.package.products.filter(\.isMainModuleProduct)
                    if let product = moduleDependency
                        .productRepresentingDependencyOfBuildPlugin(in: moduleMainProducts)
                    {
                        self.project[keyPath: sourceModuleTargetKeyPath].common.addDependency(
                            on: product.pifTargetGUID,
                            platformFilters: dependencyPlatformFilters,
                            linkProduct: false
                        )
                        log(.debug, indent: 1, "Added dependency on product '\(product.pifTargetGUID)'")
                    } else {
                        log(
                            .debug,
                            indent: 1,
                            "Could not find a build plugin product to depend on for target '\(moduleDependency.pifTargetGUID)'"
                        )
                    }

                case .binary:
                    let binaryReference = self.binaryGroup.addFileReference { id in
                        FileReference(id: id, path: moduleDependency.path.pathString)
                    }
                    if shouldLinkProduct {
                        self.project[keyPath: sourceModuleTargetKeyPath].addLibrary { id in
                            BuildFile(
                                id: id,
                                fileRef: binaryReference,
                                platformFilters: dependencyPlatformFilters,
                                codeSignOnCopy: true,
                                removeHeadersOnCopy: true
                            )
                        }
                    } else {
                        // If we are producing a single ".o", don't link binaries since they
                        // could be static which would cause them to become part of the ".o".
                        self.project[keyPath: sourceModuleTargetKeyPath].addResourceFile { id in
                            BuildFile(
                                id: id,
                                fileRef: binaryReference,
                                platformFilters: dependencyPlatformFilters
                            )
                        }
                    }
                    log(.debug, indent: 1, "Added use of binary library '\(moduleDependency.path)'")

                case .plugin:
                    let dependencyGUID = moduleDependency.pifTargetGUID
                    self.project[keyPath: sourceModuleTargetKeyPath].common.addDependency(
                        on: dependencyGUID,
                        platformFilters: dependencyPlatformFilters,
                        linkProduct: false
                    )
                    log(.debug, indent: 1, "Added use of plugin target '\(dependencyGUID)'")

                case .library, .test, .macro, .systemModule:
                    self.project[keyPath: sourceModuleTargetKeyPath].common.addDependency(
                        on: moduleDependency.pifTargetGUID,
                        platformFilters: dependencyPlatformFilters,
                        linkProduct: shouldLinkProduct
                    )
                    log(
                        .debug,
                        indent: 1,
                        "Added \(shouldLinkProduct ? "linked " : "")dependency on target '\(moduleDependency.pifTargetGUID)'"
                    )
                }

            case .product(let productDependency, let packageConditions):
                // Do not add a dependency for binary-only executable products since they are not part of the build.
                if productDependency.isBinaryOnlyExecutableProduct {
                    return
                }

                if !pifBuilder.delegate.shouldSuppressProductDependency(
                    product: productDependency.underlying,
                    buildSettings: &settings
                ) {
                    let dependencyPlatformFilters = packageConditions
                        .toPlatformFilter(toolsVersion: self.package.manifest.toolsVersion)
                    let shouldLinkProduct = shouldLinkProduct && productDependency.isLinkable

                    self.project[keyPath: sourceModuleTargetKeyPath].common.addDependency(
                        on: productDependency.pifTargetGUID,
                        platformFilters: dependencyPlatformFilters,
                        linkProduct: shouldLinkProduct
                    )
                    log(
                        .debug,
                        indent: 1,
                        "Added \(shouldLinkProduct ? "linked " : "")dependency on product '\(productDependency.pifTargetGUID)'"
                    )
                }
            }
        }

        // Custom source module build settings, if any.
        pifBuilder.delegate.configureSourceModuleBuildSettings(sourceModule: sourceModule, settings: &settings)

        // Until this point the build settings for the target have been the same between debug and release
        // configurations.
        // The custom manifest settings might cause them to diverge.
        var debugSettings = settings
        var releaseSettings = settings

        let allBuildSettings = sourceModule.allBuildSettings

        // Apply target-specific build settings defined in the manifest.
        for (buildConfig, declarationsByPlatform) in allBuildSettings.targetSettings {
            for (platform, settingsByDeclaration) in declarationsByPlatform {
                // Note: A `nil` platform means that the declaration applies to *all* platforms.
                for (declaration, stringValues) in settingsByDeclaration {
                    switch buildConfig {
                    case .debug:
                        debugSettings.append(values: stringValues, to: declaration, platform: platform)
                    case .release:
                        releaseSettings.append(values: stringValues, to: declaration, platform: platform)
                    }
                }
            }
        }

        // Impart the linker flags.
        for (platform, settingsByDeclaration) in sourceModule.allBuildSettings.impartedSettings {
            // Note: A `nil` platform means that the declaration applies to *all* platforms.
            for (declaration, stringValues) in settingsByDeclaration {
                impartedSettings.append(values: stringValues, to: declaration, platform: platform)
            }
        }

        // Set the imparted settings, which are ones that clients (both direct and indirect ones) use.
        var debugImpartedSettings = impartedSettings
        debugImpartedSettings[.LD_RUNPATH_SEARCH_PATHS] =
            ["$(BUILT_PRODUCTS_DIR)/PackageFrameworks"] +
            (debugImpartedSettings[.LD_RUNPATH_SEARCH_PATHS] ?? ["$(inherited)"])

        self.project[keyPath: sourceModuleTargetKeyPath].common.addBuildConfig { id in
            BuildConfig(
                id: id,
                name: "Debug",
                settings: debugSettings,
                impartedBuildSettings: debugImpartedSettings
            )
        }
        self.project[keyPath: sourceModuleTargetKeyPath].common.addBuildConfig { id in
            BuildConfig(
                id: id,
                name: "Release",
                settings: releaseSettings,
                impartedBuildSettings: impartedSettings
            )
        }

        // Collect linked binaries.
        let linkedPackageBinaries: [PackagePIFBuilder.LinkedPackageBinary] = sourceModule.dependencies.compactMap {
            PackagePIFBuilder.LinkedPackageBinary(dependency: $0, package: self.package)
        }

        let productOrModuleType: PackagePIFBuilder.ModuleOrProductType = if desiredModuleType == .dynamicLibrary {
            pifBuilder.createDylibForDynamicProducts ? .dynamicLibrary : .framework
        } else if desiredModuleType == .macro {
            .macro
        } else {
            .module
        }

        let moduleOrProduct = PackagePIFBuilder.ModuleOrProduct(
            type: productOrModuleType,
            name: sourceModule.name,
            moduleName: sourceModule.c99name,
            pifTarget: .target(self.project[keyPath: sourceModuleTargetKeyPath]),
            indexableFileURLs: indexableFileURLs,
            headerFiles: headerFiles,
            linkedPackageBinaries: linkedPackageBinaries,
            swiftLanguageVersion: sourceModule.packageSwiftLanguageVersion(manifest: packageManifest),
            declaredPlatforms: self.declaredPlatforms,
            deploymentTargets: self.deploymentTargets
        )

        return (moduleOrProduct, resourceBundleName)
    }

    // MARK: - System Library Targets

    mutating func makeSystemLibraryModule(_ resolvedSystemLibrary: PackageGraph.ResolvedModule) throws {
        precondition(resolvedSystemLibrary.type == .systemModule)
        let systemLibrary = resolvedSystemLibrary.underlying as! SystemLibraryModule

        // Create an aggregate PIF target (which doesn't have an actual product).
        let systemLibraryTargetKeyPath = try self.project.addAggregateTarget { _ in
            ProjectModel.AggregateTarget(
                id: resolvedSystemLibrary.pifTargetGUID,
                name: resolvedSystemLibrary.name
            )
        }
        do {
            let systemLibraryTarget = self.project[keyPath: systemLibraryTargetKeyPath]
            log(
                .debug,
                "Created aggregate target '\(systemLibraryTarget.id)' with name '\(systemLibraryTarget.name)'"
            )
        }

        let settings: ProjectModel.BuildSettings = self.package.underlying.packageBaseBuildSettings
        let pkgConfig = try systemLibrary.pkgConfig(
            package: self.package,
            observabilityScope: pifBuilder.observabilityScope
        )

        // Impart the header search path to all direct and indirect clients.
        var impartedSettings = ProjectModel.BuildSettings()
        impartedSettings[.OTHER_CFLAGS] = ["-fmodule-map-file=\(systemLibrary.modulemapFileAbsolutePath)"] +
            pkgConfig.cFlags.prepending("$(inherited)")
        impartedSettings[.OTHER_LDFLAGS] = pkgConfig.libs.prepending("$(inherited)")
        impartedSettings[.OTHER_LDRFLAGS] = []
        impartedSettings[.OTHER_SWIFT_FLAGS] = ["-Xcc"] + impartedSettings[.OTHER_CFLAGS]!
        log(.debug, indent: 1, "Added '\(systemLibrary.path.pathString)' to imparted HEADER_SEARCH_PATHS")

        self.project[keyPath: systemLibraryTargetKeyPath].common.addBuildConfig { id in
            BuildConfig(
                id: id,
                name: "Debug",
                settings: settings,
                impartedBuildSettings: impartedSettings
            )
        }
        self.project[keyPath: systemLibraryTargetKeyPath].common.addBuildConfig { id in
            BuildConfig(
                id: id,
                name: "Release",
                settings: settings,
                impartedBuildSettings: impartedSettings
            )
        }
        // FIXME: Should we also impart linkage?

        let systemModule = PackagePIFBuilder.ModuleOrProduct(
            type: .module,
            name: resolvedSystemLibrary.name,
            moduleName: resolvedSystemLibrary.c99name,
            pifTarget: .aggregate(self.project[keyPath: systemLibraryTargetKeyPath]),
            indexableFileURLs: [],
            headerFiles: [],
            linkedPackageBinaries: [],
            swiftLanguageVersion: nil,
            declaredPlatforms: self.declaredPlatforms,
            deploymentTargets: self.deploymentTargets
        )
        self.builtModulesAndProducts.append(systemModule)
    }
}

#endif
