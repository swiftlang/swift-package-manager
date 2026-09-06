//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Basics.Diagnostic
import enum PackageModel.ProductType
import struct PackageGraph.ResolvedModule
import enum SwiftBuild.ProjectModel

extension PackagePIFProjectBuilder {
    mutating func makeAggregateLibraryModule(
        _ libraryModule: PackageGraph.ResolvedModule,
        type libraryType: ProductType.LibraryType
    ) throws {
        precondition(libraryModule.type.isLibraryAggregate)

        let productType: ProjectModel.Target.ProductType
        var productName = "$(EXECUTABLE_NAME)"
        switch libraryType {
        case .dynamic:
            if pifBuilder.createDylibForDynamicProducts {
                productType = .dynamicLibrary
            } else {
                productName = "$(WRAPPER_NAME)"
                productType = .framework
            }
        case .static:
            productType = .staticArchive
        case .automatic:
            productType = .packageProduct
        }

        let targetKeyPath = try self.project.addTarget { _ in
            ProjectModel.Target(
                id: libraryModule.pifTargetGUID,
                productType: productType,
                name: libraryModule.name,
                productName: productName
            )
        }
        do {
            let target = self.project[keyPath: targetKeyPath]
            log(
                .debug,
                "Created target '\(target.id)' of type '\(target.productType)' with " +
                "name '\(target.name)' and product name '\(target.productName)'"
            )
        }

        var settings: ProjectModel.BuildSettings = self.package.underlying.packageBaseBuildSettings

        switch libraryType {
        case .dynamic:
            settings.configureDynamicSettings(
                product: nil,
                productName: libraryModule.name,
                targetName: libraryModule.name,
                packageIdentity: package.identity,
                packageName: package.identity.c99name,
                createDylibForDynamicProducts: pifBuilder.createDylibForDynamicProducts,
                installPath: "/usr/local/lib",
                delegate: pifBuilder.delegate
            )
            // An empty sources phase is required in order to trigger linking.
            self.project[keyPath: targetKeyPath].common.addSourcesBuildPhase { id in
                ProjectModel.SourcesBuildPhase(id: id)
            }

        case .static:
            settings[.TARGET_NAME] = libraryModule.name
            settings[.TARGET_TEMP_DIR_SUFFIX] = "-p"
            settings[.PRODUCT_NAME] = libraryModule.name
            settings[.EXECUTABLE_PREFIX] = "lib"
            settings[.EXECUTABLE_PREFIX, ProjectModel.BuildSettings.Platform.windows] = ""
            // An empty sources phase is required in order to trigger linking.
            self.project[keyPath: targetKeyPath].common.addSourcesBuildPhase { id in
                ProjectModel.SourcesBuildPhase(id: id)
            }

        case .automatic:
            break
        }

        let implicitlyAllowAllUnsafeFlags = pifBuilder.delegate.isBranchOrRevisionBased ||
            pifBuilder.delegate.isUserManaged
        let recordUsesUnsafeFlags = !implicitlyAllowAllUnsafeFlags && libraryModule.underlying.usesUnsafeFlags
        settings[.USES_SWIFTPM_UNSAFE_FLAGS] = recordUsesUnsafeFlags ? "YES" : "NO"

        var aggregatedModules: [PackageGraph.ResolvedModule] = []
        var nonMemberDependencies: [PackageGraph.ResolvedModule.Dependency] = []
        for dependency in libraryModule.dependencies {
            if let module = dependency.module, module.type != .plugin, module.type != .systemModule {
                aggregatedModules.append(module)
            } else {
                nonMemberDependencies.append(dependency)
            }
        }
        self.addLinkedDependencies(
            onModulesComprising: aggregatedModules,
            to: targetKeyPath,
            embedResources: false
        )
        self.addTransitiveLinkageDependencies(
            ofModulesComprising: aggregatedModules,
            additionalDependencies: nonMemberDependencies,
            to: targetKeyPath,
            settings: &settings
        )

        var target = self.project[keyPath: targetKeyPath]
        target.common.addBuildConfig { id in
            BuildConfig(id: id, name: "Debug", settings: settings)
        }
        target.common.addBuildConfig { id in
            BuildConfig(id: id, name: "Release", settings: settings)
        }
        self.project[keyPath: targetKeyPath] = target

        let moduleOrProductType: PackagePIFBuilder.ModuleOrProductType = switch libraryType {
        case .dynamic: pifBuilder.createDylibForDynamicProducts ? .dynamicLibrary : .framework
        case .static, .automatic: .staticArchive
        }

        self.builtModulesAndProducts.append(
            PackagePIFBuilder.ModuleOrProduct(
                type: moduleOrProductType,
                name: libraryModule.name,
                moduleName: nil,
                pifTarget: .target(self.project[keyPath: targetKeyPath]),
                indexableFileURLs: [],
                headerFiles: [],
                linkedPackageBinaries: libraryModule.dependencies.compactMap {
                    PackagePIFBuilder.LinkedPackageBinary(dependency: $0)
                },
                swiftLanguageVersion: nil,
                declaredPlatforms: self.declaredPlatforms,
                deploymentTargets: self.deploymentTargets,
                toolsVersion: pifBuilder.packageManifest.toolsVersion
            )
        )
    }
}
