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

            let installedBundles = resourceBundles.map { swiftpmBinDir.appending(component: $0.basename) }
            for (source, destination) in zip(resourceBundles, installedBundles) {
                try commandState.fileSystem.removeFileTree(destination)
                try commandState.fileSystem.copy(from: source, to: destination)
            }

            let record = try InstalledPackageProduct.Record(
                executableChecksum: commandState.fileSystem.checksum(of: finalBinPath),
                resourceBundles: installedBundles.map {
                    try .init(name: $0.basename, checksum: commandState.fileSystem.checksum(of: $0))
                }
            )
            try InstalledPackageProduct.writeRecord(
                record,
                forProductAt: finalBinPath,
                commandState.fileSystem
            )

            // A bundle can belong to more than one installed product, so overwriting it invalidates
            // the checksums its other owners recorded.
            for sibling in alreadyExisting {
                guard let (refreshed, changed) = sibling.record?.refreshing(record.resourceBundles),
                      !changed.isEmpty
                else { continue }

                try InstalledPackageProduct.writeRecord(
                    refreshed,
                    forProductAt: sibling.path,
                    commandState.fileSystem
                )
                commandState.observabilityScope.emit(
                    warning: """
                    Installing \(productToInstall.name) replaced resource bundles that \(sibling.name) \
                    also uses: \(changed.joined(separator: ", ")).
                    """
                )
            }

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

            try removedExecutable.remove(tool.fileSystem, keepingBundlesUsedBy: alreadyInstalled)
            print("Executable product `\(self.name)` was successfully uninstalled from \(removedExecutable.path).")
        }
    }
}

private struct InstalledPackageProduct {
    /// Suffix of the sidecar recording what installing put in place, so that uninstalling removes
    /// exactly what it added and nothing that has changed underneath it since.
    private static let recordSuffix = ".install.json"

    struct Record: Codable {
        struct Entry: Codable {
            let name: String
            let checksum: String
        }

        static let currentVersion = 1

        let version: Int
        let executableChecksum: String
        let resourceBundles: [Entry]

        init(executableChecksum: String, resourceBundles: [Entry]) {
            self.version = Self.currentVersion
            self.executableChecksum = executableChecksum
            self.resourceBundles = resourceBundles
        }

        /// This record with `bundles`' checksums applied, along with the names of the ones that changed.
        func refreshing(_ bundles: [Entry]) -> (Self, changed: [String]) {
            let updated = Dictionary(bundles.map { ($0.name, $0.checksum) }, uniquingKeysWith: { first, _ in first })
            let refreshed = self.resourceBundles.map { Entry(name: $0.name, checksum: updated[$0.name] ?? $0.checksum) }
            return (
                Self(executableChecksum: self.executableChecksum, resourceBundles: refreshed),
                changed: zip(self.resourceBundles, refreshed).filter { $0.checksum != $1.checksum }.map(\.1.name)
            )
        }
    }

    static func installedProducts(_ fileSystem: FileSystem) throws -> [InstalledPackageProduct] {
        let binPath = try fileSystem.getOrCreateSwiftPMInstalledBinariesDirectory()
        let contents = (try? fileSystem.getDirectoryContents(binPath)) ?? []
        let decoder = JSONDecoder.makeWithDefaults()

        let recordsByProduct = try contents
            .filter { $0.hasPrefix(".") && $0.hasSuffix(self.recordSuffix) }
            .reduce(into: [String: Record]()) { result, sidecar in
                let record = try decoder.decode(
                    path: binPath.appending(sidecar),
                    fileSystem: fileSystem,
                    as: Record.self
                )
                guard record.version == Record.currentVersion else {
                    throw StringError("unknown '\(sidecar)' version \(record.version)")
                }
                result[String(sidecar.dropFirst().dropLast(self.recordSuffix.count))] = record
            }
        let bundleNames = Set(recordsByProduct.values.flatMap { $0.resourceBundles.map(\.name) })

        return contents
            .filter { !$0.hasPrefix(".") && !bundleNames.contains($0) }
            .map { name in
                InstalledPackageProduct(path: binPath.appending(name), record: recordsByProduct[name])
            }
    }

    static func writeRecord(_ record: Record, forProductAt path: AbsolutePath, _ fileSystem: FileSystem) throws {
        try JSONEncoder.makeWithDefaults().encode(
            path: self.recordPath(forProductAt: path),
            fileSystem: fileSystem,
            record
        )
    }

    private static func recordPath(forProductAt path: AbsolutePath) -> AbsolutePath {
        path.parentDirectory.appending(component: ".\(path.basename)\(self.recordSuffix)")
    }

    /// Path of the executable.
    let path: AbsolutePath

    /// What installing wrote, or `nil` for products installed before the record existed.
    let record: Record?

    /// The name of this installed product, being the basename of the path.
    var name: String {
        self.path.basename
    }

    var bundleNames: [String] {
        self.record?.resourceBundles.map(\.name) ?? []
    }

    /// Installed paths paired with the checksum recorded for them, which is `nil` for products
    /// installed before records existed and so cannot be verified.
    private var installedPaths: [(path: AbsolutePath, checksum: String?)] {
        let directory = self.path.parentDirectory
        return [(path: self.path, checksum: self.record?.executableChecksum)]
            + (self.record?.resourceBundles ?? []).map { entry -> (path: AbsolutePath, checksum: String?) in
                (path: directory.appending(component: entry.name), checksum: entry.checksum)
            }
    }

    func remove(_ fileSystem: FileSystem, keepingBundlesUsedBy others: [InstalledPackageProduct]) throws {
        let kept = Set(others.filter { $0.name != self.name }.flatMap(\.bundleNames))
        let removed = self.installedPaths.filter { !kept.contains($0.path.basename) }

        let modified = try removed.filter { entry in
            guard let checksum = entry.checksum, fileSystem.exists(entry.path) else { return false }
            return try fileSystem.checksum(of: entry.path) != checksum
        }

        guard modified.isEmpty else {
            throw StringError(
                """
                \(self.name) has been modified since it was installed, so nothing was removed. Delete \
                \(modified.map(\.path.pathString).joined(separator: ", ")) by hand to finish uninstalling it.
                """
            )
        }

        for path in removed.map(\.path) + [Self.recordPath(forProductAt: self.path)] {
            try fileSystem.removeFileTree(path)
        }
    }
}
