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

import enum SwiftBuild.PIF

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
        let pifProductType: SwiftBuild.PIF.Target.ProductType
        let moduleOrProductType: PIFPackageBuilder.ModuleOrProductType
        let synthesizedResourceGeneratingPluginInvocationResults: [PIFPackageBuilder.BuildToolPluginInvocationResult] =
            []

        if product.type == .executable {
            if let customPIFProductType = pifBuilder.delegate.customProductType(forExecutable: product.underlying) {
                pifProductType = customPIFProductType
                moduleOrProductType = PIFPackageBuilder.ModuleOrProductType(from: customPIFProductType)
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
        let mainModulePifTarget = try self.pif.addTargetThrowing(
            id: product.pifTargetGUID(),
            productType: pifProductType,
            name: product.name,
            productName: product.name
        )
        log(
            .debug,
            "created \(type(of: mainModulePifTarget)) '\(mainModulePifTarget.id)' of type '\(mainModulePifTarget.productType.asString)' with name '\(mainModulePifTarget.name)' and product name '\(mainModulePifTarget.productName)'"
        )

        // We're currently *not* handling other module targets (and SwiftPM should never return them) for
        // a main-module product but, for diagnostic purposes, we warn about any that we do come across.
        if product.otherModules.hasContent {
            let otherModuleNames = product.otherModules.map(\.name).joined(separator: ",")
            log(.debug, ".. warning: ignored unexpected other module targets \(otherModuleNames)")
        }

        // Deal with any generated source files or resource files.
        let (generatedSourceFiles, pluginGeneratedResourceFiles) = computePluginGeneratedFiles(
            module: mainModule,
            pifTarget: mainModulePifTarget,
            addBuildToolPluginCommands: pifProductType == .application
        )
        if mainModule.resources.hasContent || pluginGeneratedResourceFiles.hasContent {
            mainModuleTargetNamesWithResources.insert(mainModule.name)
        }

        // Configure the target-wide build settings. The details depend on the kind of product we're building,
        // but are in general the ones that are suitable for end-product artifacts such as executables and test bundles.
        var settings: SwiftBuild.PIF.BuildSettings = package.underlying.packageBaseBuildSettings
        settings.TARGET_NAME = product.name
        settings.PACKAGE_RESOURCE_TARGET_KIND = "regular"
        settings.PRODUCT_NAME = "$(TARGET_NAME)"
        settings.PRODUCT_MODULE_NAME = product.c99name
        settings.PRODUCT_BUNDLE_IDENTIFIER = "\(self.package.identity).\(product.name)"
            .spm_mangledToBundleIdentifier()
        settings.EXECUTABLE_NAME = product.name
        settings.CLANG_ENABLE_MODULES = "YES"
        settings.SWIFT_PACKAGE_NAME = mainModule.packageName

        if mainModule.type == .test {
            // FIXME: we shouldn't always include both the deep and shallow bundle paths here, but for that we'll need rdar://31867023
            settings.LD_RUNPATH_SEARCH_PATHS = ["@loader_path/Frameworks", "@loader_path/../Frameworks", "$(inherited)"]
            settings.GENERATE_INFOPLIST_FILE = "YES"
            settings.SKIP_INSTALL = "NO"
            settings.SWIFT_ACTIVE_COMPILATION_CONDITIONS.lazilyInitialize { ["$(inherited)"] }
        } else if mainModule.type == .executable {
            // Setup install path for executables if it's in root of a pure Swift package.
            if pifBuilder.delegate.hostsOnlyPackages && pifBuilder.delegate.isRootPackage {
                settings.SKIP_INSTALL = "NO"
                settings.INSTALL_PATH = "/usr/local/bin"
                settings.LD_RUNPATH_SEARCH_PATHS = ["$(inherited)", "@executable_path/../lib"]
            }
        }

        let mainTargetDeploymentTargets = mainModule.deploymentTargets(using: pifBuilder.delegate)

        settings.MACOSX_DEPLOYMENT_TARGET = mainTargetDeploymentTargets[.macOS] ?? nil
        settings.IPHONEOS_DEPLOYMENT_TARGET = mainTargetDeploymentTargets[.iOS] ?? nil
        if let deploymentTarget_macCatalyst = mainTargetDeploymentTargets[.macCatalyst] {
            settings
                .platformSpecificSettings[.macCatalyst]![.IPHONEOS_DEPLOYMENT_TARGET] = [deploymentTarget_macCatalyst]
        }
        settings.TVOS_DEPLOYMENT_TARGET = mainTargetDeploymentTargets[.tvOS] ?? nil
        settings.WATCHOS_DEPLOYMENT_TARGET = mainTargetDeploymentTargets[.watchOS] ?? nil
        settings.DRIVERKIT_DEPLOYMENT_TARGET = mainTargetDeploymentTargets[.driverKit] ?? nil
        settings.XROS_DEPLOYMENT_TARGET = mainTargetDeploymentTargets[.visionOS] ?? nil

        // If the main module includes C headers, then we need to set up the HEADER_SEARCH_PATHS setting appropriately.
        if let includeDirAbsolutePath = mainModule.includeDirAbsolutePath {
            // Let the main module itself find its own headers.
            settings.HEADER_SEARCH_PATHS = [includeDirAbsolutePath.pathString, "$(inherited)"]
            log(.debug, ".. added '\(includeDirAbsolutePath)' to HEADER_SEARCH_PATHS")
        }

        // Set the appropriate language versions.
        settings.SWIFT_VERSION = mainModule.packageSwiftLanguageVersion(manifest: packageManifest)
        settings.GCC_C_LANGUAGE_STANDARD = mainModule.cLanguageStandard
        settings.CLANG_CXX_LANGUAGE_STANDARD = mainModule.cxxLanguageStandard
        settings.SWIFT_ENABLE_BARE_SLASH_REGEX = "NO"

        // Create a group for the source files of the main module
        // For now we use an absolute path for it, but we should really make it
        // container-relative, since it's always inside the package directory.
        let mainTargetSourceFileGroup = self.pif.mainGroup.addGroup(
            path: mainModule.sourceDirAbsolutePath.pathString,
            pathBase: .absolute
        )
        log(.debug, ".. added source file group '\(mainTargetSourceFileGroup.path)'")

        // Add a source file reference for each of the source files, and also an indexable-file URL for each one.
        // Note that the indexer requires them to have any symbolic links resolved.
        var indexableFileURLs: [SourceControlURL] = []
        for sourcePath in mainModule.sourceFileRelativePaths {
            mainModulePifTarget.addSourceFile(
                ref: mainTargetSourceFileGroup.addFileReference(path: sourcePath.pathString, pathBase: .groupDir)
            )
            log(.debug, ".. .. added source file '\(sourcePath)'")
            indexableFileURLs
                .append(SourceControlURL(fileURLWithPath: mainModule.sourceDirAbsolutePath.appending(sourcePath)))
        }

        let headerFiles = Set(mainModule.headerFileAbsolutePaths)

        // Add any additional source files emitted by custom build commands.
        for path in generatedSourceFiles {
            mainModulePifTarget.addSourceFile(
                ref: mainTargetSourceFileGroup.addFileReference(path: path.pathString, pathBase: .absolute)
            )
            log(.debug, ".. .. added generated source file '\(path)'")
        }

        // Add any additional resource files emitted by synthesized build commands
        let generatedResourceFiles: [String] = {
            var generatedResourceFiles = pluginGeneratedResourceFiles
            generatedResourceFiles.append(
                contentsOf: addBuildToolCommands(
                    from: synthesizedResourceGeneratingPluginInvocationResults,
                    pifTarget: mainModulePifTarget,
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
                sourceModulePifTarget: mainModulePifTarget,
                // For application products we embed the resources directly into the PIF target.
                resourceBundlePifTarget: nil,
                generatedResourceFiles: generatedResourceFiles
            )

            if result.shouldGenerateBundleAccessor {
                settings.GENERATE_RESOURCE_ACCESSORS = "YES"
            }
            if result.shouldGenerateEmbedInCodeAccessor {
                settings.GENERATE_EMBED_IN_CODE_ACCESSORS = "YES"
            }

            // FIXME: We should also adjust the generated module bundle glue so that `Bundle.module` is a synonym for `Bundle.main` in this case.
        } else {
            let (result, resourceBundle) = try addResourceBundle(
                for: mainModule,
                pifTarget: mainModulePifTarget,
                generatedResourceFiles: generatedResourceFiles
            )
            if let resourceBundle { self.builtModulesAndProducts.append(resourceBundle) }

            if let resourceBundle = result.bundleName {
                // Associate the resource bundle with the target.
                settings.PACKAGE_RESOURCE_BUNDLE_NAME = resourceBundle

                if result.shouldGenerateBundleAccessor {
                    settings.GENERATE_RESOURCE_ACCESSORS = "YES"
                }
                if result.shouldGenerateEmbedInCodeAccessor {
                    settings.GENERATE_EMBED_IN_CODE_ACCESSORS = "YES"
                }

                // If it's a kind of product that can contain resources, we also add a use of it.
                let ref = self.pif.mainGroup
                    .addFileReference(path: "$(CONFIGURATION_BUILD_DIR)/\(resourceBundle).bundle")
                if pifProductType == .bundle || pifProductType == .unitTest {
                    settings.COREML_CODEGEN_LANGUAGE = mainModule.usesSwift ? "Swift" : "Objective-C"
                    settings.COREML_COMPILER_CONTAINER = "swift-package"

                    mainModulePifTarget.addResourceFile(ref: ref)
                    log(.debug, ".. added use of resource bundle '\(ref.path)'")
                } else {
                    log(
                        .debug,
                        ".. ignored resource bundle '\(ref.path)' for main module of type \(type(of: mainModule))"
                    )
                }

                // Add build tool commands to the resource bundle target.
                let resourceBundlePifTarget = self
                    .resourceBundleTarget(forModuleName: mainModule.name) ?? mainModulePifTarget
                addBuildToolCommands(
                    module: mainModule,
                    sourceModulePifTarget: mainModulePifTarget,
                    resourceBundlePifTarget: resourceBundlePifTarget,
                    sourceFilePaths: generatedSourceFiles,
                    resourceFilePaths: generatedResourceFiles
                )
            } else {
                // Generated resources always trigger the creation of a bundle accessor.
                settings.GENERATE_RESOURCE_ACCESSORS = "YES"
                settings.GENERATE_EMBED_IN_CODE_ACCESSORS = "NO"

                // If we did not create a resource bundle target, we still need to add build tool commands for any
                // generated files.
                addBuildToolCommands(
                    module: mainModule,
                    sourceModulePifTarget: mainModulePifTarget,
                    resourceBundlePifTarget: mainModulePifTarget,
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
                    let binaryReference = self.binaryGroup.addFileReference(path: moduleDependency.path.pathString)
                    mainModulePifTarget.addLibrary(
                        ref: binaryReference,
                        platformFilters: packageConditions
                            .toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                        codeSignOnCopy: true,
                        removeHeadersOnCopy: true
                    )
                    log(.debug, ".. added use of binary library '\(moduleDependency.path)'")

                case .plugin:
                    let dependencyId = moduleDependency.pifTargetGUID()
                    mainModulePifTarget.addDependency(
                        on: dependencyId,
                        platformFilters: packageConditions
                            .toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                        linkProduct: false
                    )
                    log(.debug, ".. added use of plugin target '\(dependencyId)'")

                case .macro:
                    let dependencyId = moduleDependency.pifTargetGUID()
                    mainModulePifTarget.addDependency(
                        on: dependencyId,
                        platformFilters: packageConditions
                            .toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                        linkProduct: false
                    )
                    log(.debug, ".. added dependency on product '\(dependencyId)'")

                    // Link with a testable version of the macro if appropriate.
                    if product.type == .test {
                        mainModulePifTarget.addDependency(
                            on: moduleDependency.pifTargetGUID(suffix: .testable),
                            platformFilters: packageConditions
                                .toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                            linkProduct: true
                        )
                        log(
                            .debug,
                            ".. added linked dependency on target '\(moduleDependency.pifTargetGUID(suffix: .testable))'"
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
                                    pifTarget: mainModulePifTarget,
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
                        let productDependencyGUID = productDependency.pifTargetGUID()
                        mainModulePifTarget.addDependency(
                            on: productDependencyGUID,
                            platformFilters: packageConditions
                                .toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                            linkProduct: false
                        )
                        log(.debug, ".. added dependency on product '\(productDependencyGUID)'")
                    }

                    // If we're linking against an executable and the tools version is new enough,
                    // we also link against a testable version of the executable.
                    if product.type == .test, self.package.manifest.toolsVersion >= .v5_5 {
                        let moduleDependencyGUID = moduleDependency.pifTargetGUID(suffix: .testable)
                        mainModulePifTarget.addDependency(
                            on: moduleDependencyGUID,
                            platformFilters: packageConditions
                                .toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                            linkProduct: true
                        )
                        log(.debug, ".. added linked dependency on target '\(moduleDependencyGUID)'")
                    }

                case .library, .systemModule, .test:
                    let shouldLinkProduct = moduleDependency.type != .systemModule
                    let dependencyGUID = moduleDependency.pifTargetGUID()
                    mainModulePifTarget.addDependency(
                        on: dependencyGUID,
                        platformFilters: packageConditions
                            .toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                        linkProduct: shouldLinkProduct
                    )
                    log(
                        .debug,
                        ".. added \(shouldLinkProduct ? "linked " : "")dependency on target '\(dependencyGUID)'"
                    )
                }

            case .product(let productDependency, let packageConditions):
                let isLinkable = productDependency.isLinkable
                self.handleProduct(
                    productDependency,
                    with: packageConditions,
                    isLinkable: isLinkable,
                    pifTarget: mainModulePifTarget,
                    settings: &settings
                )
            }
        }

        // Until this point the build settings for the target have been the same between debug and release
        // configurations.
        // The custom manifest settings might cause them to diverge.
        var debugSettings: SwiftBuild.PIF.BuildSettings = settings
        var releaseSettings: SwiftBuild.PIF.BuildSettings = settings

        // Apply target-specific build settings defined in the manifest.
        for (buildConfig, declarationsByPlatform) in mainModule.allBuildSettings.targetSettings {
            for (platform, declarations) in declarationsByPlatform {
                // A `nil` platform means that the declaration applies to *all* platforms.
                let pifPlatform = platform.map { SwiftBuild.PIF.BuildSettings.Platform(from: $0) }
                for (declaration, stringValues) in declarations {
                    let pifDeclaration = SwiftBuild.PIF.BuildSettings.Declaration(from: declaration)
                    switch buildConfig {
                    case .debug:
                        debugSettings.append(values: stringValues, to: pifDeclaration, platform: pifPlatform)
                    case .release:
                        releaseSettings.append(values: stringValues, to: pifDeclaration, platform: pifPlatform)
                    }
                }
            }
        }
        mainModulePifTarget.addBuildConfig(name: "Debug", settings: debugSettings)
        mainModulePifTarget.addBuildConfig(name: "Release", settings: releaseSettings)

        // Collect linked binaries.
        let linkedPackageBinaries: [PIFPackageBuilder.LinkedPackageBinary] = mainModule.dependencies.compactMap {
            PIFPackageBuilder.LinkedPackageBinary(dependency: $0, package: self.package)
        }

        let moduleOrProduct = PIFPackageBuilder.ModuleOrProduct(
            type: moduleOrProductType,
            name: product.name,
            moduleName: product.c99name,
            pifTarget: mainModulePifTarget,
            indexableFileURLs: indexableFileURLs,
            headerFiles: headerFiles,
            linkedPackageBinaries: linkedPackageBinaries,
            swiftLanguageVersion: mainModule.packageSwiftLanguageVersion(manifest: packageManifest),
            declaredPlatforms: self.declaredPlatforms,
            deploymentTargets: self.deploymentTargets
        )
        self.builtModulesAndProducts.append(moduleOrProduct)
    }

    private func handleProduct(
        _ product: PackageGraph.ResolvedProduct,
        with packageConditions: [PackageModel.PackageCondition],
        isLinkable: Bool,
        pifTarget: SwiftBuild.PIF.Target,
        settings: inout SwiftBuild.PIF.BuildSettings
    ) {
        // Do not add a dependency for binary-only executable products since they are not part of the build.
        if product.isBinaryOnlyExecutableProduct {
            return
        }

        if !pifBuilder.delegate.shouldSuppressProductDependency(product: product.underlying, buildSettings: &settings) {
            let shouldLinkProduct = isLinkable
            pifTarget.addDependency(
                on: product.pifTargetGUID(),
                platformFilters: packageConditions.toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                linkProduct: shouldLinkProduct
            )
            log(
                .debug,
                ".. added \(shouldLinkProduct ? "linked " : "")dependency on product '\(product.pifTargetGUID()))'"
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

            let pifTarget = library.pifTarget as? SwiftBuild.PIF.Target
            let dynamicPifTarget = dynamicLibraryVariant.pifTarget as? SwiftBuild.PIF.Target

            if let pifTarget, let dynamicPifTarget {
                pifTarget.dynamicTargetVariant = dynamicPifTarget
            } else {
                assertionFailure("Could not assign dynamic PIF target")
            }
        }
    }

    /// Helper function to create a PIF target for a **library product**.
    ///
    /// In order to support development-time features such as Preview and Swift Playgrounds,
    /// all SwiftPM library products are represented by two PIF targets:
    /// one of the "native" manifestation that gets linked into the client,
    /// and another for a dynamic framework specifically for use by the development-time features.
    private func buildLibraryProduct(
        _ product: PackageGraph.ResolvedProduct,
        type desiredProductType: ProductType.LibraryType,
        targetSuffix: TargetGUIDSuffix? = nil,
        embedResources: Bool
    ) throws -> PIFPackageBuilder.ModuleOrProduct {
        precondition(product.type.isLibrary)

        // FIXME: Cleanup this mess with <rdar://56889224>

        let pifTargetProductName: String
        let executableName: String
        let productType: SwiftBuild.PIF.Target.ProductType

        if desiredProductType == .dynamic {
            if pifBuilder.createDylibForDynamicProducts {
                pifTargetProductName = "lib\(product.name).dylib"
                executableName = pifTargetProductName
                productType = .dynamicLibrary
            } else {
                // If a product is explicitly declared dynamic, we preserve its name, otherwise we will compute an
                // automatic one.
                if product.libraryType == .dynamic {
                    if let customExecutableName = pifBuilder.delegate
                        .customExecutableName(product: product.underlying)
                    {
                        executableName = customExecutableName
                    } else {
                        executableName = product.name
                    }
                } else {
                    executableName = PIFPackageBuilder.computePackageProductFrameworkName(productName: product.name)
                }
                pifTargetProductName = "\(executableName).framework"
                productType = .framework
            }
        } else {
            pifTargetProductName = "lib\(product.name).a"
            executableName = pifTargetProductName
            productType = .packageProduct
        }

        // Create a special kind of PIF target that just "groups" a set of targets for clients to depend on.
        // SwiftBuild will *not* produce a separate artifact for a package product, but will instead consider any
        // dependency on
        // the package product to be a dependency on the whole set of targets on which the package product depends.
        let pifTarget = try self.pif.addTargetThrowing(
            id: product.pifTargetGUID(suffix: targetSuffix),
            productType: productType,
            name: product.name,
            productName: pifTargetProductName
        )
        log(
            .debug,
            "created \(type(of: pifTarget)) '\(pifTarget.id)' of type '\(pifTarget.productType.asString)' with name '\(pifTarget.name)' and product name '\(pifTarget.productName)'"
        )

        // Add linked dependencies on the *targets* that comprise the product.
        for module in product.modules {
            // Binary targets are special in that they are just linked, not built.
            if let binaryTarget = module.underlying as? BinaryModule {
                let binaryReference = self.binaryGroup.addFileReference(path: binaryTarget.artifactPath.pathString)
                pifTarget.addLibrary(ref: binaryReference, codeSignOnCopy: true, removeHeadersOnCopy: true)
                log(.debug, ".. added use of binary library '\(binaryTarget.artifactPath.pathString)'")
                continue
            }
            // We add these as linked dependencies; because the product type is `.packageProduct`,
            // SwiftBuild won't actually link them, but will instead impart linkage to any clients that
            // link against the package product.
            pifTarget.addDependency(on: module.pifTargetGUID(), platformFilters: [], linkProduct: true)
            log(.debug, ".. added linked dependency on target '\(module.pifTargetGUID())'")
        }

        for module in product.modules where module.underlying.isSourceModule && module.resources.hasContent {
            // FIXME: Find a way to determine whether a module has generated resources here so that we can embed resources into dynamic targets.
            pifTarget.addDependency(on: pifTargetIdForResourceBundle(module.name), platformFilters: [])

            let filreRef = self.pif.mainGroup
                .addFileReference(path: "$(CONFIGURATION_BUILD_DIR)/\(package.name)_\(module.name).bundle")
            if embedResources {
                pifTarget.addResourceFile(ref: filreRef)
                log(.debug, ".. added use of resource bundle '\(filreRef.path)'")
            } else {
                log(.debug, ".. ignored resource bundle '\(filreRef.path)' because resource embedding is disabled")
            }
        }

        var settings: SwiftBuild.PIF.BuildSettings = package.underlying.packageBaseBuildSettings

        // Add other build settings when we're building an actual dylib.
        if desiredProductType == .dynamic {
            settings.configureDynamicSettings(
                productName: product.name,
                targetName: product.targetNameForProduct(),
                executableName: executableName,
                packageIdentity: package.identity,
                packageName: package.identity.c99name,
                createDylibForDynamicProducts: pifBuilder.createDylibForDynamicProducts,
                installPath: installPath(for: product.underlying),
                delegate: pifBuilder.delegate
            )

            pifTarget.addSourcesBuildPhase()
        }

        // Additional configuration and files for this library product.
        pifBuilder.delegate.configureLibraryProduct(
            product: product.underlying,
            pifTarget: pifTarget,
            additionalFiles: self.additionalFilesGroup
        )

        // If the given package is a root package or it is used via a branch/revision, we allow unsafe flags.
        let implicitlyAllowAllUnsafeFlags = pifBuilder.delegate.isBranchOrRevisionBased || pifBuilder.delegate
            .isUserManaged
        let recordUsesUnsafeFlags = try !implicitlyAllowAllUnsafeFlags && product.usesUnsafeFlags
        settings.USES_SWIFTPM_UNSAFE_FLAGS = recordUsesUnsafeFlags ? "YES" : "NO"

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
                    log(.debug, ".. noted use of system module '\(moduleDependency.name)'")
                    return
                }

                if let binaryTarget = moduleDependency.underlying as? BinaryModule {
                    let binaryReference = self.binaryGroup.addFileReference(path: binaryTarget.path.pathString)
                    pifTarget.addLibrary(
                        ref: binaryReference,
                        platformFilters: packageConditions
                            .toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                        codeSignOnCopy: true,
                        removeHeadersOnCopy: true
                    )
                    log(.debug, ".. added use of binary library '\(binaryTarget.path)'")
                    return
                }

                if moduleDependency.type == .plugin {
                    let dependencyId = moduleDependency.pifTargetGUID()
                    pifTarget.addDependency(
                        on: dependencyId,
                        platformFilters: packageConditions
                            .toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                        linkProduct: false
                    )
                    log(.debug, ".. added use of plugin target '\(dependencyId)'")
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
                        pifTarget.addDependency(
                            on: product.pifTargetGUID(),
                            platformFilters: packageConditions
                                .toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                            linkProduct: false
                        )
                        log(.debug, ".. added dependency on product '\(product.pifTargetGUID())'")
                        return
                    } else {
                        log(
                            .debug,
                            ".. could not find a build plugin product to depend on for target '\(product.pifTargetGUID()))'"
                        )
                    }
                }

                pifTarget.addDependency(
                    on: moduleDependency.pifTargetGUID(),
                    platformFilters: packageConditions.toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                    linkProduct: true
                )
                log(.debug, ".. added linked dependency on target '\(moduleDependency.pifTargetGUID()))'")

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
                    pifTarget.addDependency(
                        on: productDependency.pifTargetGUID(),
                        platformFilters: packageConditions
                            .toPlatformFilter(toolsVersion: package.manifest.toolsVersion),
                        linkProduct: shouldLinkProduct
                    )
                    log(
                        .debug,
                        ".. added \(shouldLinkProduct ? "linked" : "") dependency on product '\(productDependency.pifTargetGUID()))'"
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
            settings.PACKAGE_REGISTRY_SIGNATURE = String(data: data, encoding: .utf8)
        }

        pifTarget.addBuildConfig(name: "Debug", settings: settings)
        pifTarget.addBuildConfig(name: "Release", settings: settings)

        // Collect linked binaries.
        let linkedPackageBinaries = product.modules.compactMap {
            PIFPackageBuilder.LinkedPackageBinary(module: $0, package: self.package)
        }

        let moduleOrProductType: PIFPackageBuilder.ModuleOrProductType = switch product.libraryType {
        case .dynamic:
            pifBuilder.createDylibForDynamicProducts ? .dynamicLibrary : .framework
        default:
            .staticArchive
        }

        return PIFPackageBuilder.ModuleOrProduct(
            type: moduleOrProductType,
            name: product.name,
            moduleName: product.c99name,
            pifTarget: pifTarget,
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

        let pifTarget = try self.pif.addTargetThrowing(
            id: product.pifTargetGUID(),
            productType: .packageProduct,
            name: product.name,
            productName: product.name
        )

        log(
            .debug,
            "created \(type(of: pifTarget)) '\(pifTarget.id)' of type '\(pifTarget.productType.asString)' " +
                "with name '\(pifTarget.name)' and product name '\(pifTarget.productName)'"
        )

        let buildSettings = self.package.underlying.packageBaseBuildSettings
        pifTarget.addBuildConfig(name: "Debug", settings: buildSettings)
        pifTarget.addBuildConfig(name: "Release", settings: buildSettings)

        pifTarget.addDependency(
            on: product.systemModule!.pifTargetGUID(),
            platformFilters: [],
            linkProduct: false
        )

        let systemLibrary = PIFPackageBuilder.ModuleOrProduct(
            type: .staticArchive,
            name: product.name,
            moduleName: product.c99name,
            pifTarget: pifTarget,
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

        let pluginPifTarget = self.pif.addAggregateTarget(
            id: pluginProduct.pifTargetGUID(),
            name: pluginProduct.name
        )
        log(.debug, "created \(type(of: pluginPifTarget)) '\(pluginPifTarget.id)' with name '\(pluginPifTarget.name)'")

        let buildSettings: SwiftBuild.PIF.BuildSettings = package.underlying.packageBaseBuildSettings
        pluginPifTarget.addBuildConfig(name: "Debug", settings: buildSettings)
        pluginPifTarget.addBuildConfig(name: "Release", settings: buildSettings)

        for pluginModule in pluginProduct.pluginModules! {
            pluginPifTarget.addDependency(
                on: pluginModule.pifTargetGUID(),
                platformFilters: []
            )
        }

        let pluginType: PIFPackageBuilder.ModuleOrProductType = {
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

        let pluginProductMetadata = PIFPackageBuilder.ModuleOrProduct(
            type: pluginType,
            name: pluginProduct.name,
            moduleName: pluginProduct.c99name,
            pifTarget: pluginPifTarget,
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
        case registry(url: URL)
    }

    let packageIdentity: String
    let packageVersion: String
    let signature: RegistryReleaseMetadata.RegistrySignature
    let libraryName: String
    let source: Source
    let formatVersion = 2
}
