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

import _InternalTestSupport
import Basics
import Foundation
import PackageGraph
import PackageModel
@testable import SBOMModel

extension SBOMTestModulesGraph {
    // MARK: - Root SPM Package - Part 3: Executable Modules

    /// Creates all executable modules for the root SwiftPM package
    /// These are the CLI tools: swift-build, swift-package, swift-run, etc.
    static func createSPMRootExecutableModules(
        coreResolvedModules: [ResolvedModule],
        commandResolvedModules: [ResolvedModule],
        argumentParserProduct: ResolvedProduct,
        orderedCollectionsProduct: ResolvedProduct
    ) -> (
        modules: [Module],
        resolvedModules: [ResolvedModule]
    ) {
        let identity = PackageIdentity.plain("swift-package-manager")

        // Extract resolved modules we need
        let resolvedBasicsModule = coreResolvedModules.first { $0.name == "Basics" }!
        let resolvedBuildModule = coreResolvedModules.first { $0.name == "Build" }!
        let resolvedPackageModelModule = coreResolvedModules.first { $0.name == "PackageModel" }!
        let resolvedPackageLoadingModule = coreResolvedModules.first { $0.name == "PackageLoading" }!
        let resolvedPackageGraphModule = coreResolvedModules.first { $0.name == "PackageGraph" }!
        let resolvedWorkspaceModule = coreResolvedModules.first { $0.name == "Workspace" }!

        let resolvedCommandsModule = commandResolvedModules.first { $0.name == "Commands" }!
        let resolvedXCBuildSupportModule = commandResolvedModules.first { $0.name == "XCBuildSupport" }!
        let resolvedSwiftBuildSupportModule = commandResolvedModules.first { $0.name == "SwiftBuildSupport" }!
        let resolvedSwiftSDKCommandModule = commandResolvedModules.first { $0.name == "SwiftSDKCommand" }!
        let resolvedPackageCollectionsCommandModule = commandResolvedModules
            .first { $0.name == "PackageCollectionsCommand" }!
        let resolvedPackageRegistryCommandModule = commandResolvedModules.first { $0.name == "PackageRegistryCommand" }!

        // MARK: - Create Executable Modules

        let dummySwiftcModule = self.createSwiftModule(name: "dummy-swiftc", type: .executable)
        let packageInfoModule = self.createSwiftModule(name: "package-info", type: .executable)
        let swiftBootstrapModule = self.createSwiftModule(name: "swift-bootstrap", type: .executable)
        let swiftBuildExecModule = self.createSwiftModule(name: "swift-build", type: .executable)
        let swiftBuildPrebuiltsModule = self.createSwiftModule(name: "swift-build-prebuilts", type: .executable)
        let swiftExperimentalSDKModule = self.createSwiftModule(name: "swift-experimental-sdk", type: .executable)
        let swiftPackageExecModule = self.createSwiftModule(name: "swift-package", type: .executable)
        let swiftPackageCollectionExecModule = self.createSwiftModule(
            name: "swift-package-collection",
            type: .executable
        )
        let swiftPackageManagerExecModule = self.createSwiftModule(name: "swift-package-manager", type: .executable)
        let swiftPackageRegistryExecModule = self.createSwiftModule(name: "swift-package-registry", type: .executable)
        let swiftRunModule = self.createSwiftModule(name: "swift-run", type: .executable)
        let swiftSDKModule = self.createSwiftModule(name: "swift-sdk", type: .executable)
        let swiftTestModule = self.createSwiftModule(name: "swift-test", type: .executable)
        let swiftpmTestingHelperModule = self.createSwiftModule(name: "swiftpm-testing-helper", type: .executable)

        // MARK: - Create Resolved Modules with Dependencies

        let resolvedDummySwiftcModule = self.createResolvedModule(
            packageIdentity: identity,
            module: dummySwiftcModule,
            dependencies: [.module(resolvedBasicsModule, conditions: [])]
        )

        let resolvedPackageInfoModule = self.createResolvedModule(
            packageIdentity: identity,
            module: packageInfoModule,
            dependencies: [.module(resolvedWorkspaceModule, conditions: [])]
        )

        let resolvedSwiftBootstrapModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftBootstrapModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedBuildModule, conditions: []),
                .module(resolvedPackageGraphModule, conditions: []),
                .module(resolvedPackageLoadingModule, conditions: []),
                .module(resolvedPackageModelModule, conditions: []),
                .module(resolvedXCBuildSupportModule, conditions: []),
                .module(resolvedSwiftBuildSupportModule, conditions: []),
                .product(argumentParserProduct, conditions: []),
                .product(orderedCollectionsProduct, conditions: []),
            ]
        )

        let resolvedSwiftBuildExecModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftBuildExecModule,
            dependencies: [.module(resolvedCommandsModule, conditions: [])]
        )

        let resolvedSwiftBuildPrebuiltsModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftBuildPrebuiltsModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedWorkspaceModule, conditions: []),
                .product(argumentParserProduct, conditions: []),
            ]
        )

        let resolvedSwiftExperimentalSDKModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftExperimentalSDKModule,
            dependencies: [
                .module(resolvedCommandsModule, conditions: []),
                .module(resolvedSwiftSDKCommandModule, conditions: []),
            ]
        )

        let resolvedSwiftPackageExecModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftPackageExecModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedCommandsModule, conditions: []),
            ]
        )

        let resolvedSwiftPackageCollectionExecModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftPackageCollectionExecModule,
            dependencies: [
                .module(resolvedCommandsModule, conditions: []),
                .module(resolvedPackageCollectionsCommandModule, conditions: []),
            ]
        )

        let resolvedSwiftPackageManagerExecModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftPackageManagerExecModule,
            dependencies: [
                .module(resolvedBasicsModule, conditions: []),
                .module(resolvedCommandsModule, conditions: []),
                .module(resolvedSwiftSDKCommandModule, conditions: []),
                .module(resolvedPackageCollectionsCommandModule, conditions: []),
                .module(resolvedPackageRegistryCommandModule, conditions: []),
            ]
        )

        let resolvedSwiftPackageRegistryExecModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftPackageRegistryExecModule,
            dependencies: [
                .module(resolvedCommandsModule, conditions: []),
                .module(resolvedPackageRegistryCommandModule, conditions: []),
            ]
        )

        let resolvedSwiftRunModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftRunModule,
            dependencies: [.module(resolvedCommandsModule, conditions: [])]
        )

        let resolvedSwiftSDKModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftSDKModule,
            dependencies: [
                .module(resolvedCommandsModule, conditions: []),
                .module(resolvedSwiftSDKCommandModule, conditions: []),
            ]
        )

        let resolvedSwiftTestModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftTestModule,
            dependencies: [.module(resolvedCommandsModule, conditions: [])]
        )

        let resolvedSwiftpmTestingHelperModule = self.createResolvedModule(
            packageIdentity: identity,
            module: swiftpmTestingHelperModule
        )

        return (
            modules: [
                dummySwiftcModule, packageInfoModule, swiftBootstrapModule, swiftBuildExecModule,
                swiftBuildPrebuiltsModule, swiftExperimentalSDKModule, swiftPackageExecModule,
                swiftPackageCollectionExecModule, swiftPackageManagerExecModule, swiftPackageRegistryExecModule,
                swiftRunModule, swiftSDKModule, swiftTestModule, swiftpmTestingHelperModule,
            ],
            resolvedModules: [
                resolvedDummySwiftcModule, resolvedPackageInfoModule, resolvedSwiftBootstrapModule,
                resolvedSwiftBuildExecModule, resolvedSwiftBuildPrebuiltsModule, resolvedSwiftExperimentalSDKModule,
                resolvedSwiftPackageExecModule, resolvedSwiftPackageCollectionExecModule,
                resolvedSwiftPackageManagerExecModule, resolvedSwiftPackageRegistryExecModule,
                resolvedSwiftRunModule, resolvedSwiftSDKModule, resolvedSwiftTestModule,
                resolvedSwiftpmTestingHelperModule,
            ]
        )
    }
}
