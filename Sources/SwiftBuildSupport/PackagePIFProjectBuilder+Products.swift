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
import struct Basics.SourceControlURL

import class PackageModel.BinaryModule
import class PackageModel.Manifest
import enum PackageModel.PackageCondition
import class PackageModel.Product
import enum PackageModel.ProductType
import struct PackageModel.RegistryReleaseMetadata

import struct PackageGraph.ResolvedModule
import struct PackageGraph.ResolvedPackage
import struct PackageGraph.ResolvedProduct

#if canImport(SwiftBuild)

import enum SwiftBuild.ProjectModel

/// Extension to create PIF **products** for a given package.
extension PackagePIFProjectBuilder {
    // MARK: - Main Module Products

    mutating func makeMainModuleProduct(_ product: PackageGraph.ResolvedProduct) throws {
        precondition(product.isMainModuleProduct)

        // We'll be infusing the product's main module into the one for the product itself.
        guard let mainModule = product.mainModule, mainModule.isSourceModule else {
            return
        }

        // Skip test products from non-root packages. libSwiftPM will stop vending them after
        // target-based dependency resolution anyway but this should be fine until then.
        if !pifBuilder.delegate.isRootPackage && (mainModule.type == .test || mainModule.type == .binary) {
            return
        }

        // Determine the kind of PIF target *product type* to create for the package product.
        let pifProductType: ProjectModel.Target.ProductType
        let moduleOrProductType: PackagePIFBuilder.ModuleOrProductType
        let synthesizedResourceGeneratingPluginInvocationResults: [PackagePIFBuilder.BuildToolPluginInvocationResult] =
            []

        if product.type == .executable {
            if let customPIFProductType = pifBuilder.delegate.customProductType(forExecutable: product.underlying) {
                pifProductType = customPIFProductType
                moduleOrProductType = PackagePIFBuilder.ModuleOrProductType(from: customPIFProductType)
            } else {
                // No custom type provider. Current behavior is to fall back on regular executable.
                pifProductType = .executable
                moduleOrProductType = .executable
            }
        } else {
            // If it's not an executable product, it must currently be a test bundle.
            assert(product.type == .test, "Unexpected product type: \(product.type)")
            pifProductType = .unitTest
            moduleOrProductType = .unitTest
        }

        // It's not a library product, so create a regular PIF target of the appropriate product type.
        let mainModuleTargetKeyPath = try self.project.addTarget { _ in
            ProjectModel.Target(
                id: product.pifTargetGUID,
                productType: pifProductType,
                name: product.targetName(),
                productName: product.name
            )
        }
        do {
            let mainModuleTarget = self.project[keyPath: mainModuleTargetKeyPath]
            log(
                .debug,
                "Created target '\(mainModuleTarget.id)' of type '\(mainModuleTarget.productType)' " +
                "with name '\(mainModuleTarget.name)' and product name '\(mainModuleTarget.productName)'"
            )
        }

        // We're currently *not* handling other module targets (and SwiftPM should never return them) for
        // a main-module product but, for diagnostic purposes, we warn about any that we do come across.
        if product.otherModules.hasContent {
            let otherModuleNames = product.otherModules.map(\.name).joined(separator: ",")
            log(.debug, indent: 1, "Warning: ignored unexpected other module targets \(otherModuleNames)")
        }

        // Deal with any generated source files or resource files.
        let (generatedSourceFiles, pluginGeneratedResourceFiles) = computePluginGeneratedFiles(
            module: mainModule,
            targetKeyPath: mainModuleTargetKeyPath,
            addBuildToolPluginCommands: pifProductType == .application
        )
        if mainModule.resources.hasContent || pluginGeneratedResourceFiles.hasContent {
            mainModuleTargetNamesWithResources.insert(mainModule.name)
        }

        // Configure the target-wide build settings. The details depend on the kind of product we're building,
        // but are in general the ones that are suitable for end-product artifacts such as executables and test bundles.
        var settings: ProjectModel.BuildSettings = package.underlying.packageBaseBuildSettings
        settings[.TARGET_NAME] = product.name
        settings[.PACKAGE_RESOURCE_TARGET_KIND] = "regular"
        settings[.PRODUCT_NAME] = "$(TARGET_NAME)"
        settings[.PRODUCT_MODULE_NAME] = product.c99name
        settings[.PRODUCT_BUNDLE_IDENTIFIER] = "\(self.package.identity).\(product.name)"
            .spm_mangledToBundleIdentifier()
        settings[.EXECUTABLE_NAME] = product.name
        settings[.CLANG_ENABLE_MODULES] = "YES"
        settings[.SWIFT_PACKAGE_NAME] = mainModule.packageName

        if mainModule.type == .test {
            // FIXME: we shouldn't always include both the deep and shallow bundle paths here, but for that we'll need rdar://31867023
            settings[.LD_RUNPATH_SEARCH_PATHS] = [
                "@loader_path/Frameworks",
                "@loader_path/../Frameworks",
                "$(inherited)"
            ]
            settings[.GENERATE_INFOPLIST_FILE] = "YES"
            settings[.SKIP_INSTALL] = "NO"
            settings[.SWIFT_ACTIVE_COMPILATION_CONDITIONS].lazilyInitialize { ["$(inherited)"] }
        } else if mainModule.type == .executable {
            // Setup install path for executables if it's in root of a pure Swift package.
            if pifBuilder.delegate.hostsOnlyPackages && pifBuilder.delegate.isRootPackage {
                settings[.SKIP_INSTALL] = "NO"
                settings[.INSTALL_PATH] = "/usr/local/bin"
                settings[.LD_RUNPATH_SEARCH_PATHS] = ["$(inherited)", "@executable_path/../lib"]
            }
        }

        let mainTargetDeploymentTargets = mainModule.deploymentTargets(using: pifBuilder.delegate)

        settings[.MACOSX_DEPLOYMENT_TARGET] = mainTargetDeploymentTargets[.macOS] ?? nil
        settings[.IPHONEOS_DEPLOYMENT_TARGET] = mainTargetDeploymentTargets[.iOS] ?? nil
        if let deploymentTarget_macCatalyst = mainTargetDeploymentTargets[.macCatalyst] {
            settings
                .platformSpecificSettings[.macCatalyst]![.IPHONEOS_DEPLOYMENT_TARGET] = [deploymentTarget_macCatalyst]
        }
        settings[.TVOS_DEPLOYMENT_TARGET] = mainTargetDeploymentTargets[.tvOS] ?? nil
        settings[.WATCHOS_DEPLOYMENT_TARGET] = mainTargetDeploymentTargets[.watchOS] ?? nil
        settings[.DRIVERKIT_DEPLOYMENT_TARGET] = mainTargetDeploymentTargets[.driverKit] ?? nil
        settings[.XROS_DEPLOYMENT_TARGET] = mainTargetDeploymentTargets[.visionOS] ?? nil

        // If the main module includes C headers, then we need to set up the HEADER_SEARCH_PATHS setting appropriately.
        if let includeDirAbsolutePath = mainModule.includeDirAbsolutePath {
            // Let the main module itself find its own headers.
            settings[.HEADER_SEARCH_PATHS] = [includeDirAbsolutePath.pathString, "$(inherited)"]
            log(.debug, indent: 1, "Added '\(includeDirAbsolutePath)' to HEADER_SEARCH_PATHS")
        }

        // Set the appropriate language versions.
        settings[.SWIFT_VERSION] = mainModule.packageSwiftLanguageVersion(manifest: packageManifest)
        settings[.GCC_C_LANGUAGE_STANDARD] = mainModule.cLanguageStandard
        settings[.CLANG_CXX_LANGUAGE_STANDARD] = mainModule.cxxLanguageStandard
        settings[.SWIFT_ENABLE_BARE_SLASH_REGEX] = "NO"

        // Create a group for the source files of the main module
        // For now we use an absolute path for it, but we should really make it
        // container-relative, since it's always inside the package directory.
        let mainTargetSourceFileGroupKeyPath = self.project.mainGroup.addGroup { id in
            ProjectModel.Group(
                id: id,
                path: mainModule.sourceDirAbsolutePath.pathString,
                pathBase: .absolute
            )
        }
        do {
            let mainTargetSourceFileGroup = self.project.mainGroup[keyPath: mainTargetSourceFileGroupKeyPath]
            log(.debug, indent: 1, "Added source file group '\(mainTargetSourceFileGroup.path)'")
        }

        // Add a source file reference for each of the source files, and also an indexable-file URL for each one.
        // Note that the indexer requires them to have any symbolic links resolved.
        var indexableFileURLs: [SourceControlURL] = []
        for sourcePath in mainModule.sourceFileRelativePaths {
            let sourceFileRef = self.project.mainGroup[keyPath: mainTargetSourceFileGroupKeyPath]
                .addFileReference { id in
                    FileReference(
                        id: id,
                        path: sourcePath.pathString,
                        pathBase: .groupDir
                    )
                }
            self.project[keyPath: mainModuleTargetKeyPath].addSourceFile { id in
                BuildFile(id: id, fileRef: sourceFileRef)
            }
            log(.debug, indent: 2, "Added source file '\(sourcePath)'")
            indexableFileURLs.append(
                SourceControlURL(fileURLWithPath: mainModule.sourceDirAbsolutePath.appending(sourcePath))
            )
        }

        let headerFiles = Set(mainModule.headerFileAbsolutePaths)

        // Add any additional source files emitted by custom build commands.
        for path in generatedSourceFiles {
            let sourceFileRef = self.project.mainGroup[keyPath: mainTargetSourceFileGroupKeyPath]
                .addFileReference { id in
                    FileReference(
                        id: id,
                        path: path.pathString,
                        pathBase: .absolute
                    )
                }
            self.project[keyPath: mainModuleTargetKeyPath].addSourceFile { id in
                BuildFile(id: id, fileRef: sourceFileRef)
            }
            log(.debug, indent: 2, "Added generated source file '\(path)'")
        }

        // Add any additional resource files emitted by synthesized build commands
        let generatedResourceFiles: [String] = {
            var generatedResourceFiles = pluginGeneratedResourceFiles
            generatedResourceFiles.append(
                contentsOf: addBuildToolCommands(
                    from: synthesizedResourceGeneratingPluginInvocationResults,
                    targetKeyPath: mainModuleTargetKeyPath,
                    addBuildToolPluginCommands: pifProductType == .application
                )
            )
            return generatedResourceFiles
        }()

        // Create a separate target to build a resource bundle for any resources files in the product's main target.
        // FIXME: We should extend this to other kinds of products, but the immediate need for Swift Playgrounds Projects is for applications.
        if pifProductType == .application {
            let result = processResources(
                for: mainModule,
                sourceModuleTargetKeyPath: mainModuleTargetKeyPath,
                // For application products we embed the resources directly into the PIF target.
                resourceBundleTargetKeyPath: nil,
                generatedResourceFiles: generatedResourceFiles
            )

            if result.shouldGenerateBundleAccessor {
                settings[.GENERATE_RESOURCE_ACCESSORS] = "YES"
            }
            if result.shouldGenerateEmbedInCodeAccessor {
                settings[.GENERATE_EMBED_IN_CODE_ACCESSORS] = "YES"
            }
            // FIXME: We should also adjust the generated module bundle glue so that `Bundle.module` is a synonym for `Bundle.main` in this case.
        } else {
            let (result, resourceBundle) = try addResourceBundle(
                for: mainModule,
                targetKeyPath: mainModuleTargetKeyPath,
                generatedResourceFiles: generatedResourceFiles
            )
            if let resourceBundle { self.builtModulesAndProducts.append(resourceBundle) }

            if let resourceBundle = result.bundleName {
                // Associate the resource bundle with the target.
                settings[.PACKAGE_RESOURCE_BUNDLE_NAME] = resourceBundle

                if result.shouldGenerateBundleAccessor {
                    settings[.GENERATE_RESOURCE_ACCESSORS] = "YES"
                }
                if result.shouldGenerateEmbedInCodeAccessor {
                    settings[.GENERATE_EMBED_IN_CODE_ACCESSORS] = "YES"
                }

                // If it's a kind of product that can contain resources, we also add a use of it.
                let resourceBundleRef = self.project.mainGroup.addFileReference { id in
                    FileReference(id: id, path: "$(CONFIGURATION_BUILD_DIR)/\(resourceBundle).bundle")
                }
                if pifProductType == .bundle || pifProductType == .unitTest {
                    settings[.COREML_CODEGEN_LANGUAGE] = mainModule.usesSwift ? "Swift" : "Objective-C"
                    settings[.COREML_COMPILER_CONTAINER] = "swift-package"

                    self.project[keyPath: mainModuleTargetKeyPath].addResourceFile { id in
                        BuildFile(id: id, fileRef: resourceBundleRef)
                    }
                    log(.debug, indent: 2, "Added use of resource bundle '\(resourceBundleRef.path)'")
                } else {
                    log(
                        .debug,
                        indent: 2,
                        "Ignored resource bundle '\(resourceBundleRef.path)' for main module of type \(type(of: mainModule))"
                    )
                }

                // Add build tool commands to the resource bundle target.
                let mainResourceBundleTargetKeyPath = self.resourceBundleTargetKeyPath(forModuleName: mainModule.name)
                let resourceBundleTargetKeyPath = mainResourceBundleTargetKeyPath ?? mainModuleTargetKeyPath

                addBuildToolCommands(
                    module: mainModule,
                    sourceModuleTargetKeyPath: mainModuleTargetKeyPath,
                    resourceBundleTargetKeyPath: resourceBundleTargetKeyPath,
                    sourceFilePaths: generatedSourceFiles,
                    resourceFilePaths: generatedResourceFiles
                )
            } else {
                // Generated resources always trigger the creation of a bundle accessor.
                settings[.GENERATE_RESOURCE_ACCESSORS] = "YES"
                settings[.GENERATE_EMBED_IN_CODE_ACCESSORS] = "NO"

                // If we did not create a resource bundle target,
                // we still need to add build tool commands for any generated files.
                addBuildToolCommands(
                    module: mainModule,
                    sourceModuleTargetKeyPath: mainModuleTargetKeyPath,
                    resourceBundleTargetKeyPath: mainModuleTargetKeyPath,
                    sourceFilePaths: generatedSourceFiles,
                    resourceFilePaths: generatedResourceFiles
                )
            }
        }

        // Handle the main target's dependencies (and link against them).
        mainModule.recursivelyTraverseDependencies { dependency in
            switch dependency {
            case .module(let moduleDependency, let packageConditions):
                // This assertion is temporarily disabled since we may see targets from
                // _other_ packages, but this should be resolved; see rdar://95467710.
                /* assert(moduleDependency.packageName == self.package.name) */

                switch moduleDependency.type {
                case .binary:
                    let binaryFileRef = self.binaryGroup.addFileReference { id in
                        FileReference(id: id, path: moduleDependency.path.pathString)
                    }
                    let toolsVersion = self.package.manifest.toolsVersion
                    self.project[keyPath: mainModuleTargetKeyPath].addLibrary { id in
                        BuildFile(
                            id: id,
                            fileRef: binaryFileRef,
                            platformFilters: packageConditions.toPlatformFilter(toolsVersion: toolsVersion),
                            codeSignOnCopy: true,
                            removeHeadersOnCopy: true
                        )
                    }
                    log(.debug, indent: 1, "Added use of binary library '\(moduleDependency.path)'")

                case .plugin:
                    let dependencyId = moduleDependency.pifTargetGUID
                    self.project[keyPath: mainModuleTargetKeyPath].common.addDependency(
                        on: dependencyId,
                        platformFilters: packageConditions
                            .toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                        linkProduct: false
                    )
                    log(.debug, indent: 1, "Added use of plugin target '\(dependencyId)'")

                case .macro:
                    let dependencyId = moduleDependency.pifTargetGUID
                    self.project[keyPath: mainModuleTargetKeyPath].common.addDependency(
                        on: dependencyId,
                        platformFilters: packageConditions
                            .toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                        linkProduct: false
                    )
                    log(.debug, indent: 1, "Added dependency on product '\(dependencyId)'")

                    // Link with a testable version of the macro if appropriate.
                    if product.type == .test {
                        self.project[keyPath: mainModuleTargetKeyPath].common.addDependency(
                            on: moduleDependency.pifTargetGUID(suffix: .testable),
                            platformFilters: packageConditions
                                .toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                            linkProduct: true
                        )
                        log(
                            .debug,
                            indent: 1,
                            "Added linked dependency on target '\(moduleDependency.pifTargetGUID(suffix: .testable))'"
                        )

                        // FIXME: Manually propagate product dependencies of macros but the build system should really handle this.
                        moduleDependency.recursivelyTraverseDependencies { dependency in
                            switch dependency {
                            case .product(let productDependency, let packageConditions):
                                let isLinkable = productDependency.isLinkable
                                self.handleProduct(
                                    productDependency,
                                    with: packageConditions,
                                    isLinkable: isLinkable,
                                    targetKeyPath: mainModuleTargetKeyPath,
                                    settings: &settings
                                )
                            case .module:
                                break
                            }
                        }
                    }

                case .executable, .snippet:
                    // For executable targets, we depend on the *product* instead
                    // (i.e., we infuse the product's main module target into the one for the product itself).
                    let productDependency = modulesGraph.allProducts.only { $0.name == moduleDependency.name }
                    if let productDependency {
                        let productDependencyGUID = productDependency.pifTargetGUID
                        self.project[keyPath: mainModuleTargetKeyPath].common.addDependency(
                            on: productDependencyGUID,
                            platformFilters: packageConditions
                                .toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                            linkProduct: false
                        )
                        log(.debug, indent: 1, "Added dependency on product '\(productDependencyGUID)'")
                    }

                    // If we're linking against an executable and the tools version is new enough,
                    // we also link against a testable version of the executable.
                    if product.type == .test, self.package.manifest.toolsVersion >= .v5_5 {
                        let moduleDependencyGUID = moduleDependency.pifTargetGUID(suffix: .testable)
                        self.project[keyPath: mainModuleTargetKeyPath].common.addDependency(
                            on: moduleDependencyGUID,
                            platformFilters: packageConditions
                                .toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                            linkProduct: true
                        )
                        log(.debug, indent: 1, "Added linked dependency on target '\(moduleDependencyGUID)'")
                    }

                case .library, .systemModule, .test:
                    let shouldLinkProduct = moduleDependency.type != .systemModule
                    let dependencyGUID = moduleDependency.pifTargetGUID
                    self.project[keyPath: mainModuleTargetKeyPath].common.addDependency(
                        on: dependencyGUID,
                        platformFilters: packageConditions
                            .toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                        linkProduct: shouldLinkProduct
                    )
                    log(
                        .debug,
                        indent: 1,
                        "Added \(shouldLinkProduct ? "linked " : "")dependency on target '\(dependencyGUID)'"
                    )
                }

            case .product(let productDependency, let packageConditions):
                let isLinkable = productDependency.isLinkable
                self.handleProduct(
                    productDependency,
                    with: packageConditions,
                    isLinkable: isLinkable,
                    targetKeyPath: mainModuleTargetKeyPath,
                    settings: &settings
                )
            }
        }

        // Until this point the build settings for the target have been the same between debug and release
        // configurations.
        // The custom manifest settings might cause them to diverge.
        var debugSettings: ProjectModel.BuildSettings = settings
        var releaseSettings: ProjectModel.BuildSettings = settings

        // Apply target-specific build settings defined in the manifest.
        for (buildConfig, declarationsByPlatform) in mainModule.allBuildSettings.targetSettings {
            for (platform, declarations) in declarationsByPlatform {
                // A `nil` platform means that the declaration applies to *all* platforms.
                for (declaration, stringValues) in declarations {
                    switch buildConfig {
                    case .debug:
                        debugSettings.append(values: stringValues, to: declaration, platform: platform)
                    case .release:
                        releaseSettings.append(values: stringValues, to: declaration, platform: platform)
                    }
                }
            }
        }
        self.project[keyPath: mainModuleTargetKeyPath].common.addBuildConfig { id in
            BuildConfig(id: id, name: "Debug", settings: debugSettings)
        }
        self.project[keyPath: mainModuleTargetKeyPath].common.addBuildConfig { id in
            BuildConfig(id: id, name: "Release", settings: releaseSettings)
        }

        // Collect linked binaries.
        let linkedPackageBinaries: [PackagePIFBuilder.LinkedPackageBinary] = mainModule.dependencies.compactMap {
            PackagePIFBuilder.LinkedPackageBinary(dependency: $0, package: self.package)
        }

        let moduleOrProduct = PackagePIFBuilder.ModuleOrProduct(
            type: moduleOrProductType,
            name: product.name,
            moduleName: product.c99name,
            pifTarget: .target(self.project[keyPath: mainModuleTargetKeyPath]),
            indexableFileURLs: indexableFileURLs,
            headerFiles: headerFiles,
            linkedPackageBinaries: linkedPackageBinaries,
            swiftLanguageVersion: mainModule.packageSwiftLanguageVersion(manifest: packageManifest),
            declaredPlatforms: self.declaredPlatforms,
            deploymentTargets: self.deploymentTargets
        )
        self.builtModulesAndProducts.append(moduleOrProduct)
    }

    private mutating func handleProduct(
        _ product: PackageGraph.ResolvedProduct,
        with packageConditions: [PackageModel.PackageCondition],
        isLinkable: Bool,
        targetKeyPath: WritableKeyPath<ProjectModel.Project, ProjectModel.Target>,
        settings: inout ProjectModel.BuildSettings
    ) {
        // Do not add a dependency for binary-only executable products since they are not part of the build.
        if product.isBinaryOnlyExecutableProduct {
            return
        }

        if !pifBuilder.delegate.shouldSuppressProductDependency(product: product.underlying, buildSettings: &settings) {
            let shouldLinkProduct = isLinkable
            self.project[keyPath: targetKeyPath].common.addDependency(
                on: product.pifTargetGUID,
                platformFilters: packageConditions.toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                linkProduct: shouldLinkProduct
            )
            log(
                .debug,
                indent: 1,
                "Added \(shouldLinkProduct ? "linked " : "")dependency on product '\(product.pifTargetGUID)'"
            )
        }
    }

    // MARK: - Library Products

    /// We treat library products specially, in that they are just collections of other targets.
    mutating func makeLibraryProduct(
        _ libraryProduct: PackageGraph.ResolvedProduct,
        type libraryType: ProductType.LibraryType
    ) throws {
        precondition(libraryProduct.type.isLibrary)

        let library = try self.buildLibraryProduct(
            libraryProduct,
            type: libraryType,
            embedResources: false
        )
        self.builtModulesAndProducts.append(library)

        // Also create a dynamic product for use by development-time features such as Previews and Swift Playgrounds.
        // If all targets this product is comprised of are binaries, we should *not* create a dynamic variant.
        if libraryType == .automatic && libraryProduct.hasSourceTargets {
            var dynamicLibraryVariant = try self.buildLibraryProduct(
                libraryProduct,
                type: .dynamic,
                targetSuffix: .dynamic,
                embedResources: true
            )
            dynamicLibraryVariant.isDynamicLibraryVariant = true
            self.builtModulesAndProducts.append(dynamicLibraryVariant)

            guard let pifTarget = library.pifTarget,
                  let pifTargetKeyPath = self.project.findTarget(id: pifTarget.id),
                  let dynamicPifTarget = dynamicLibraryVariant.pifTarget
            else {
                fatalError("Could not assign dynamic PIF target")
            }
            self.project[keyPath: pifTargetKeyPath].dynamicTargetVariantId = dynamicPifTarget.id
        }
    }

    /// Helper function to create a PIF target for a **library product**.
    ///
    /// In order to support development-time features such as Preview and Swift Playgrounds,
    /// all SwiftPM library products are represented by two PIF targets:
    /// one of the "native" manifestation that gets linked into the client,
    /// and another for a dynamic framework specifically for use by the development-time features.
    private mutating func buildLibraryProduct(
        _ product: PackageGraph.ResolvedProduct,
        type desiredProductType: ProductType.LibraryType,
        targetSuffix: TargetSuffix? = nil,
        embedResources: Bool
    ) throws -> PackagePIFBuilder.ModuleOrProduct {
        precondition(product.type.isLibrary)

        // FIXME: Cleanup this mess with <rdar://56889224>

        let pifProductName: String
        let executableName: String
        let productType: ProjectModel.Target.ProductType

        if desiredProductType == .dynamic {
            if pifBuilder.createDylibForDynamicProducts {
                pifProductName = "lib\(product.name).dylib"
                executableName = pifProductName
                productType = .dynamicLibrary
            } else {
                // If a product is explicitly declared dynamic, we preserve its name,
                // otherwise we will compute an automatic one.
                if product.libraryType == .dynamic {
                    if let customExecutableName = pifBuilder.delegate
                        .customExecutableName(product: product.underlying)
                    {
                        executableName = customExecutableName
                    } else {
                        executableName = product.name
                    }
                } else {
                    executableName = PackagePIFBuilder.computePackageProductFrameworkName(productName: product.name)
                }
                pifProductName = "\(executableName).framework"
                productType = .framework
            }
        } else {
            pifProductName = "lib\(product.name).a"
            executableName = pifProductName
            productType = .packageProduct
        }

        // Create a special kind of PIF target that just "groups" a set of targets for clients to depend on.
        // Swift Build will *not* produce a separate artifact for a package product, but will instead consider any
        // dependency on the package product to be a dependency on the whole set of targets
        // on which the package product depends.
        let librayUmbrellaTargetKeyPath = try self.project.addTarget { _ in
            ProjectModel.Target(
                id: product.pifTargetGUID(suffix: targetSuffix),
                productType: productType,
                name: product.targetName(suffix: targetSuffix),
                productName: pifProductName
            )
        }
        do {
            let librayTarget = self.project[keyPath: librayUmbrellaTargetKeyPath]
            log(
                .debug,
                "Created target '\(librayTarget.id)' of type '\(librayTarget.productType)' with " +
                "name '\(librayTarget.name)' and product name '\(librayTarget.productName)'"
            )
        }

        // Add linked dependencies on the *targets* that comprise the product.
        for module in product.modules {
            // Binary targets are special in that they are just linked, not built.
            if let binaryTarget = module.underlying as? BinaryModule {
                let binaryFileRef = self.binaryGroup.addFileReference { id in
                    FileReference(id: id, path: binaryTarget.artifactPath.pathString)
                }
                self.project[keyPath: librayUmbrellaTargetKeyPath].addLibrary { id in
                    BuildFile(id: id, fileRef: binaryFileRef, codeSignOnCopy: true, removeHeadersOnCopy: true)
                }
                log(.debug, indent: 1, "Added use of binary library '\(binaryTarget.artifactPath)'")
                continue
            }
            // We add these as linked dependencies; because the product type is `.packageProduct`,
            // SwiftBuild won't actually link them, but will instead impart linkage to any clients that
            // link against the package product.
            self.project[keyPath: librayUmbrellaTargetKeyPath].common.addDependency(
                on: module.pifTargetGUID,
                platformFilters: [],
                linkProduct: true
            )
            log(.debug, indent: 1, "Added linked dependency on target '\(module.pifTargetGUID)'")
        }

        for module in product.modules where module.underlying.isSourceModule && module.resources.hasContent {
            // FIXME: Find a way to determine whether a module has generated resources
            // here so that we can embed resources into dynamic targets.
            self.project[keyPath: librayUmbrellaTargetKeyPath].common.addDependency(
                on: pifTargetIdForResourceBundle(module.name),
                platformFilters: []
            )

            let packageName = self.package.name
            let fileRef = self.project.mainGroup.addFileReference { id in
                FileReference(id: id, path: "$(CONFIGURATION_BUILD_DIR)/\(packageName)_\(module.name).bundle")
            }
            if embedResources {
                self.project[keyPath: librayUmbrellaTargetKeyPath].addResourceFile { id in
                    BuildFile(id: id, fileRef: fileRef)
                }
                log(.debug, indent: 1, "Added use of resource bundle '\(fileRef.path)'")
            } else {
                log(
                    .debug,
                    indent: 1,
                    "Ignored resource bundle '\(fileRef.path)' because resource embedding is disabled"
                )
            }
        }

        var settings: ProjectModel.BuildSettings = package.underlying.packageBaseBuildSettings

        // Add other build settings when we're building an actual dylib.
        if desiredProductType == .dynamic {
            settings.configureDynamicSettings(
                productName: product.name,
                targetName: product.targetName(),
                executableName: executableName,
                packageIdentity: package.identity,
                packageName: package.identity.c99name,
                createDylibForDynamicProducts: pifBuilder.createDylibForDynamicProducts,
                installPath: installPath(for: product.underlying),
                delegate: pifBuilder.delegate
            )
            self.project[keyPath: librayUmbrellaTargetKeyPath].common.addSourcesBuildPhase { id in
                ProjectModel.SourcesBuildPhase(id: id)
            }
        }

        // Additional configuration and files for this library product.
        pifBuilder.delegate.configureLibraryProduct(
            product: product.underlying,
            target: librayUmbrellaTargetKeyPath,
            additionalFiles: additionalFilesGroupKeyPath
        )

        // If the given package is a root package or it is used via a branch/revision, we allow unsafe flags.
        let implicitlyAllowAllUnsafeFlags = pifBuilder.delegate.isBranchOrRevisionBased ||
            pifBuilder.delegate.isUserManaged
        let recordUsesUnsafeFlags = try !implicitlyAllowAllUnsafeFlags && product.usesUnsafeFlags
        settings[.USES_SWIFTPM_UNSAFE_FLAGS] = recordUsesUnsafeFlags ? "YES" : "NO"

        // Handle the dependencies of the targets in the product
        // (and link against them, which in the case of a package product, really just means that clients should link
        // against them).
        product.modules.recursivelyTraverseDependencies { dependency in
            switch dependency {
            case .module(let moduleDependency, let packageConditions):
                // This assertion is temporarily disabled since we may see targets from
                // _other_ packages, but this should be resolved; see rdar://95467710.
                /* assert(moduleDependency.packageName == self.package.name) */

                if moduleDependency.type == .systemModule {
                    log(.debug, indent: 1, "Noted use of system module '\(moduleDependency.name)'")
                    return
                }

                if let binaryTarget = moduleDependency.underlying as? BinaryModule {
                    let binaryFileRef = self.binaryGroup.addFileReference { id in
                        FileReference(id: id, path: binaryTarget.path.pathString)
                    }
                    let toolsVersion = package.manifest.toolsVersion
                    self.project[keyPath: librayUmbrellaTargetKeyPath].addLibrary { id in
                        BuildFile(
                            id: id,
                            fileRef: binaryFileRef,
                            platformFilters: packageConditions.toPlatformFilter(toolsVersion: toolsVersion),
                            codeSignOnCopy: true,
                            removeHeadersOnCopy: true
                        )
                    }
                    log(.debug, indent: 1, "Added use of binary library '\(binaryTarget.path)'")
                    return
                }

                if moduleDependency.type == .plugin {
                    let dependencyId = moduleDependency.pifTargetGUID
                    self.project[keyPath: librayUmbrellaTargetKeyPath].common.addDependency(
                        on: dependencyId,
                        platformFilters: packageConditions
                            .toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                        linkProduct: false
                    )
                    log(.debug, indent: 1, "Added use of plugin target '\(dependencyId)'")
                    return
                }

                // If this dependency is already present in the product's module target then don't re-add it.
                if product.modules.contains(where: { $0.name == moduleDependency.name }) { return }

                // For executable targets, add a build time dependency on the product.
                // FIXME: Maybe we should we do this at the libSwiftPM level.
                if moduleDependency.isExecutable {
                    let mainModuleProducts = package.products.filter(\.isMainModuleProduct)

                    if let product = moduleDependency
                        .productRepresentingDependencyOfBuildPlugin(in: mainModuleProducts)
                    {
                        self.project[keyPath: librayUmbrellaTargetKeyPath].common.addDependency(
                            on: product.pifTargetGUID,
                            platformFilters: packageConditions
                                .toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                            linkProduct: false
                        )
                        log(.debug, indent: 1, "Added dependency on product '\(product.pifTargetGUID)'")
                        return
                    } else {
                        log(
                            .debug,
                            indent: 1,
                            "Could not find a build plugin product to depend on for target '\(product.pifTargetGUID)'"
                        )
                    }
                }

                self.project[keyPath: librayUmbrellaTargetKeyPath].common.addDependency(
                    on: moduleDependency.pifTargetGUID,
                    platformFilters: packageConditions.toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                    linkProduct: true
                )
                log(.debug, indent: 1, "Added linked dependency on target '\(moduleDependency.pifTargetGUID)'")

            case .product(let productDependency, let packageConditions):
                // Do not add a dependency for binary-only executable products since they are not part of the build.
                if productDependency.isBinaryOnlyExecutableProduct {
                    return
                }

                if !pifBuilder.delegate.shouldSuppressProductDependency(
                    product: productDependency.underlying,
                    buildSettings: &settings
                ) {
                    let shouldLinkProduct = productDependency.isLinkable
                    self.project[keyPath: librayUmbrellaTargetKeyPath].common.addDependency(
                        on: productDependency.pifTargetGUID,
                        platformFilters: packageConditions
                            .toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                        linkProduct: shouldLinkProduct
                    )
                    log(
                        .debug,
                        indent: 1,
                        "Added \(shouldLinkProduct ? "linked" : "") dependency on product '\(productDependency.pifTargetGUID)'"
                    )
                }
            }
        }

        // For *registry* packages, vend any registry release metadata to the build system.
        if let metadata = package.registryMetadata,
           let signature = metadata.signature,
           let version = pifBuilder.packageDisplayVersion,
           case RegistryReleaseMetadata.Source.registry(let url) = metadata.source
        {
            let signatureData = PackageRegistrySignature(
                packageIdentity: package.identity.description,
                packageVersion: version,
                signature: signature,
                libraryName: product.name,
                source: .registry(url: url)
            )

            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(signatureData)
            settings[.PACKAGE_REGISTRY_SIGNATURE] = String(data: data, encoding: .utf8)
        }

        self.project[keyPath: librayUmbrellaTargetKeyPath].common.addBuildConfig { id in
            BuildConfig(id: id, name: "Debug", settings: settings)
        }
        self.project[keyPath: librayUmbrellaTargetKeyPath].common.addBuildConfig { id in
            BuildConfig(id: id, name: "Release", settings: settings)
        }

        // Collect linked binaries.
        let linkedPackageBinaries = product.modules.compactMap {
            PackagePIFBuilder.LinkedPackageBinary(module: $0, package: self.package)
        }

        let moduleOrProductType: PackagePIFBuilder.ModuleOrProductType = switch product.libraryType {
        case .dynamic:
            pifBuilder.createDylibForDynamicProducts ? .dynamicLibrary : .framework
        default:
            .staticArchive
        }

        return PackagePIFBuilder.ModuleOrProduct(
            type: moduleOrProductType,
            name: product.name,
            moduleName: product.c99name,
            pifTarget: .target(self.project[keyPath: librayUmbrellaTargetKeyPath]),
            indexableFileURLs: [],
            headerFiles: [],
            linkedPackageBinaries: linkedPackageBinaries,
            swiftLanguageVersion: nil,
            declaredPlatforms: self.declaredPlatforms,
            deploymentTargets: self.deploymentTargets
        )
    }

    // MARK: - System Library Products

    mutating func makeSystemLibraryProduct(_ product: PackageGraph.ResolvedProduct) throws {
        precondition(product.type == .library(.automatic))

        let systemLibraryTargetKeyPath = try self.project.addTarget { _ in
            ProjectModel.Target(
                id: product.pifTargetGUID,
                productType: .packageProduct,
                name: product.targetName(),
                productName: product.name
            )
        }
        do {
            let systemLibraryTarget = self.project[keyPath: systemLibraryTargetKeyPath]
            log(
                .debug,
                "Created target '\(systemLibraryTarget.id)' of type '\(systemLibraryTarget.productType)' " +
                "with name '\(systemLibraryTarget.name)' and product name '\(systemLibraryTarget.productName)'"
            )
        }

        let buildSettings = self.package.underlying.packageBaseBuildSettings
        self.project[keyPath: systemLibraryTargetKeyPath].common.addBuildConfig { id in
            BuildConfig(id: id, name: "Debug", settings: buildSettings)
        }
        self.project[keyPath: systemLibraryTargetKeyPath].common.addBuildConfig { id in
            BuildConfig(id: id, name: "Release", settings: buildSettings)
        }

        self.project[keyPath: systemLibraryTargetKeyPath].common.addDependency(
            on: product.systemModule!.pifTargetGUID,
            platformFilters: [],
            linkProduct: false
        )

        let systemLibrary = PackagePIFBuilder.ModuleOrProduct(
            type: .staticArchive,
            name: product.name,
            moduleName: product.c99name,
            pifTarget: .target(self.project[keyPath: systemLibraryTargetKeyPath]),
            indexableFileURLs: [],
            headerFiles: [],
            linkedPackageBinaries: [],
            swiftLanguageVersion: nil,
            declaredPlatforms: self.declaredPlatforms,
            deploymentTargets: self.deploymentTargets
        )
        self.builtModulesAndProducts.append(systemLibrary)
    }

    // MARK: - Plugin Product

    mutating func makePluginProduct(_ pluginProduct: PackageGraph.ResolvedProduct) throws {
        precondition(pluginProduct.type == .plugin)

        let pluginTargetKeyPath = try self.project.addAggregateTarget { _ in
            ProjectModel.AggregateTarget(
                id: pluginProduct.pifTargetGUID,
                name: pluginProduct.targetName()
            )
        }
        do {
            let pluginTarget = self.project[keyPath: pluginTargetKeyPath]
            log(.debug, "Created aggregate target '\(pluginTarget.id)' with name '\(pluginTarget.name)'")
        }

        let buildSettings: ProjectModel.BuildSettings = package.underlying.packageBaseBuildSettings
        self.project[keyPath: pluginTargetKeyPath].common.addBuildConfig { id in
            BuildConfig(id: id, name: "Debug", settings: buildSettings)
        }
        self.project[keyPath: pluginTargetKeyPath].common.addBuildConfig { id in
            BuildConfig(id: id, name: "Release", settings: buildSettings)
        }

        for pluginModule in pluginProduct.pluginModules! {
            self.project[keyPath: pluginTargetKeyPath].common.addDependency(
                on: pluginModule.pifTargetGUID,
                platformFilters: []
            )
        }

        let pluginType: PackagePIFBuilder.ModuleOrProductType = {
            if let pluginTarget = pluginProduct.pluginModules!.only {
                switch pluginTarget.capability {
                case .buildTool:
                    return .buildToolPlugin
                case .command:
                    return .commandPlugin
                }
            } else {
                assertionFailure(
                    "This should never be reached since there is always exactly one plugin target in a product by definition"
                )
                return .commandPlugin
            }
        }()

        let pluginProductMetadata = PackagePIFBuilder.ModuleOrProduct(
            type: pluginType,
            name: pluginProduct.name,
            moduleName: pluginProduct.c99name,
            pifTarget: .aggregate(self.project[keyPath: pluginTargetKeyPath]),
            indexableFileURLs: [],
            headerFiles: [],
            linkedPackageBinaries: [],
            swiftLanguageVersion: nil,
            declaredPlatforms: self.declaredPlatforms,
            deploymentTargets: self.deploymentTargets
        )
        self.builtModulesAndProducts.append(pluginProductMetadata)
    }
}

// MARK: - Helper Types

private struct PackageRegistrySignature: Encodable {
    enum Source: Encodable {
        case registry(url: Foundation.URL)
    }

    let packageIdentity: String
    let packageVersion: String
    let signature: RegistryReleaseMetadata.RegistrySignature
    let libraryName: String
    let source: Source
    let formatVersion = 2
}

#endif
