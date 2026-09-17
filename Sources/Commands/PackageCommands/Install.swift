//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import CoreCommands
import Foundation
import PackageGraph
import PackageModel
import SPMBuildCore
import struct TSCBasic.StringError
import Workspace

extension SwiftPackageCommand {
    struct Install: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "experimental-install",
            abstract: "Offers the ability to install executable products of the current package.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions

        @Option(help: "The name of the executable product to install.")
        var product: String?

        func run(_ commandState: SwiftCommandState) async throws {
            let swiftpmBinDir = try commandState.fileSystem.getOrCreateSwiftPMInstalledBinariesDirectory()

            let env = Environment.current

            if let path = env[.path], !path.contains(swiftpmBinDir.pathString), !globalOptions.logging.quiet {
                commandState.observabilityScope.emit(
                    warning: """
                    PATH doesn't include \(swiftpmBinDir.pathString)! This means you won't be able to access \
                    the installed executables by default, and will need to specify the full path.
                    """
                )
            }

            let alreadyExisting = (try? InstalledPackageProduct.installedProducts(commandState.fileSystem)) ?? []

            let workspace = try commandState.getActiveWorkspace()
            let packageRoot = try commandState.getPackageRoot()

            let packageGraph = try await workspace.loadPackageGraph(
                rootPath: packageRoot,
                observabilityScope: commandState.observabilityScope
            )

            let possibleCandidates = packageGraph.rootPackages.flatMap(\.products)
                .filter { $0.type == .executable }

            let productToInstall: ResolvedProduct

            switch possibleCandidates.count {
            case 0:
                throw StringError("No Executable Products in Package.swift.")
            case 1:
                productToInstall = possibleCandidates[0]
            default:
                guard let product, let first = possibleCandidates.first(where: { $0.name == product }) else {
                    throw StringError(
                        """
                        Multiple candidates found, however, no product was specified. Specify a product with the \
                        `--product` option
                        """
                    )
                }

                productToInstall = first
            }

            if let existingPkg = alreadyExisting.first(where: { $0.name == productToInstall.name }) {
                throw StringError("\(productToInstall.name) is already installed at \(existingPkg.path)")
            }

            if commandState.options.build.configuration == nil {
                commandState.preferredBuildConfiguration = .release
            }

            let buildSystem = try await commandState.createBuildSystem(explicitProduct: productToInstall.name)
            try await buildSystem.build(subset: .product(productToInstall.name), buildOutputs: [])

            let buildProductsPath = try await buildSystem.buildProductsPath(for: commandState.productsBuildParameters)
            let binPath = buildProductsPath.appending(component: productToInstall.name)
            let finalBinPath = swiftpmBinDir.appending(component: binPath.basename)
            try commandState.fileSystem.copy(from: binPath, to: finalBinPath)

            // `Bundle.module` looks for the resource bundle next to the executable, so it has to
            // follow the binary out of the build directory.
            let bundleExtension = try commandState.productsBuildParameters.triple.nsbundleExtension
            let resourceBundles = try productToInstall.recursiveModuleDependencies()
                .compactMap(\.underlying.bundleName)
                .map { buildProductsPath.appending(component: $0 + bundleExtension) }
                .filter { commandState.fileSystem.exists($0) }

            for bundle in resourceBundles {
                let destination = swiftpmBinDir.appending(component: bundle.basename)
                try commandState.fileSystem.removeFileTree(destination)
                try commandState.fileSystem.copy(from: bundle, to: destination)
            }

            try InstalledPackageProduct(
                path: finalBinPath,
                resourceBundlePaths: resourceBundles.map { swiftpmBinDir.appending(component: $0.basename) }
            ).writeResourceRecord(commandState.fileSystem)

            print("Executable product `\(productToInstall.name)` was successfully installed to \(finalBinPath).")
        }
    }

    struct Uninstall: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "experimental-uninstall",
            abstract: "Offers the ability to uninstall executable products previously installed by `swift package experimental-install`.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
        )

        @OptionGroup
        var globalOptions: GlobalOptions

        @Argument(help: "Name of the executable to uninstall.")
        var name: String

        func run(_ tool: SwiftCommandState) throws {
            let alreadyInstalled = (try? InstalledPackageProduct.installedProducts(tool.fileSystem)) ?? []

            guard let removedExecutable = alreadyInstalled.first(where: { $0.name == name }) else {
                // The installed executable doesn't exist - let the user know, and stop here.
                throw StringError("No such installed executable as \(name)")
            }

            try tool.fileSystem.removeFileTree(removedExecutable.path)
            for bundle in removedExecutable.resourceBundlePaths {
                try tool.fileSystem.removeFileTree(bundle)
            }
            try tool.fileSystem.removeFileTree(removedExecutable.resourceRecordPath)
            print("Executable product `\(self.name)` was successfully uninstalled from \(removedExecutable.path).")
        }
    }
}

private struct InstalledPackageProduct {
    /// Suffix of the sidecar recording the resource bundles installed next to an executable, so
    /// that uninstalling removes exactly what installing added.
    private static let recordSuffix = ".resources.json"

    static func installedProducts(_ fileSystem: FileSystem) throws -> [InstalledPackageProduct] {
        let binPath = try fileSystem.getOrCreateSwiftPMInstalledBinariesDirectory()
        let contents = (try? fileSystem.getDirectoryContents(binPath)) ?? []

        let bundleNamesByProduct = try contents
            .filter { $0.hasPrefix(".") && $0.hasSuffix(self.recordSuffix) }
            .reduce(into: [String: [String]]()) { result, record in
                result[String(record.dropFirst().dropLast(self.recordSuffix.count))] = try JSONDecoder
                    .makeWithDefaults()
                    .decode(path: binPath.appending(record), fileSystem: fileSystem, as: [String].self)
            }
        let bundleNames = Set(bundleNamesByProduct.values.joined())

        return contents
            .filter { !$0.hasPrefix(".") && !bundleNames.contains($0) }
            .map { name in
                InstalledPackageProduct(
                    path: binPath.appending(name),
                    resourceBundlePaths: (bundleNamesByProduct[name] ?? []).map { binPath.appending(component: $0) }
                )
            }
    }

    /// Path of the executable.
    let path: AbsolutePath

    /// Paths of the resource bundles installed alongside the executable.
    let resourceBundlePaths: [AbsolutePath]

    /// The name of this installed product, being the basename of the path.
    var name: String {
        self.path.basename
    }

    var resourceRecordPath: AbsolutePath {
        self.path.parentDirectory.appending(component: ".\(self.name)\(Self.recordSuffix)")
    }

    func writeResourceRecord(_ fileSystem: FileSystem) throws {
        guard !self.resourceBundlePaths.isEmpty else { return }
        try JSONEncoder.makeWithDefaults().encode(
            path: self.resourceRecordPath,
            fileSystem: fileSystem,
            self.resourceBundlePaths.map(\.basename)
        )
    }
}
