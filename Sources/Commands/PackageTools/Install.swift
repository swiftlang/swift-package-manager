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

import ArgumentParser
import Basics
import CoreCommands
import Workspace

import class PackageGraph.ResolvedProduct

extension SwiftPackageTool {
    enum Error: Swift.Error {
        case noExecutableProductsFound
    }

    struct Install: SwiftCommand {
        public static let configuration = CommandConfiguration(
            commandName: "experimental-install",
            abstract: "Install executable package products to a local user directory.",
            shouldDisplay: false
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        /// Specific product to install.
        @Option(help: "Install the specified product")
        var product: String?

        func run(_ swiftTool: CoreCommands.SwiftTool) throws {
            let buildParameters = try swiftTool.buildParameters()
            // FIXME: should be in release mode for installed packages
//            buildParameters.configuration = .release
            let buildSystem = try swiftTool.createBuildSystem(customBuildParameters: buildParameters)

            let rootExecutableProducts = try swiftTool.loadPackageGraph().rootPackages
                .flatMap { $0.products }
                .filter { $0.type == .executable }

            let installedProducts: [ResolvedProduct]
            if let product = self.product {
                try buildSystem.build(subset: .product(product))

                installedProducts = rootExecutableProducts.filter { $0.name == product }
            } else {
                try buildSystem.build()

                installedProducts = rootExecutableProducts
            }

            guard !installedProducts.isEmpty else {
                throw Error.noExecutableProductsFound
            }

            let fs = swiftTool.fileSystem

            let installedPackagesBinDirectory = try fs.getOrCreateSwiftPMInstalledPackagesDirectory()
                .appending(component: "bin")
            if !fs.exists(installedPackagesBinDirectory) {
                try fs.createDirectory(installedPackagesBinDirectory, recursive: true)
            }

            for product in installedProducts {
                let buildPath = try buildParameters.binaryPath(for: product)
                let installedProductPath = installedPackagesBinDirectory.appending(component: product.name)
                if fs.exists(installedProductPath) {
                    try fs.removeFileTree(installedProductPath)
                }
                try fs.copy(from: buildPath, to: installedProductPath)

                print("Product `\(product.name)` successfully installed to `\(installedProductPath)`.")
            }
        }
    }
}
