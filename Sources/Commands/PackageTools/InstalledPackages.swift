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
import CoreCommands
import TSCUtility
import TSCBasic
import PackageModel
import Foundation

extension SwiftPackageTool {
    struct Install: SwiftCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(commandName: "experimental-install", abstract: "Offers the ability to install executable products of the current package.")
        }
        
        @OptionGroup()
        var globalOptions: GlobalOptions
        
        @Option(help: "The name of the executable product to install")
        var product: String?
        
        
        func run(_ tool: SwiftTool) throws {
            let swiftpmBinDir = try tool.fileSystem.getOrCreateSwiftPMInstalledBinariesDirectory()
            
            let env = ProcessInfo.processInfo.environment
            
            if let path = env.path, !path.contains(swiftpmBinDir.pathString), !globalOptions.logging.quiet {
                tool.observabilityScope.emit(warning: "PATH doesn't include \(swiftpmBinDir.pathString)! This means you won't be able to access the installed executables by default, and will need to specify the full path.")
            }
            
            var alreadyExisting = (try? InstalledPackageProduct.installedProducts(tool.fileSystem)) ?? []
            
            let workspace = try tool.getActiveWorkspace()
            let packageRoot = try tool.getPackageRoot()

            
            let packageGraph = try workspace.loadPackageGraph(rootPath: packageRoot, observabilityScope: tool.observabilityScope)
            
            let possibleCanidates = packageGraph.rootPackages.flatMap(\.products)
                .filter { $0.type == .executable }
            
            let productToInstall: Product
            
            switch possibleCanidates.count {
            case 0:
                throw StringError("No Executable Products in Package.swift.")
            case 1:
                productToInstall = possibleCanidates[0].underlyingProduct
            default: // More than one, check for possible
                guard let product, let first = possibleCanidates.first(where: { $0.name == product }) else {
                    throw StringError("Multiple canidates found, however, no product was specified. specify a product with the --product")
                }
                
                productToInstall = first.underlyingProduct
            }
            
            if let existingPkg = alreadyExisting.first(where: { $0.name == productToInstall.name }) {
                throw StringError("\(productToInstall.name) is already installed at \(existingPkg.path)")
            }
            
            try tool.createBuildSystem(explicitProduct: productToInstall.name).build(subset: .product(productToInstall.name))
            
            let binPath = try tool.buildParameters().buildPath.appending(component: productToInstall.name)
            let finalBinPath = swiftpmBinDir.appending(component: binPath.basename)
            try tool.fileSystem.copy(from: binPath, to: finalBinPath)
            
            let pkgInstance = InstalledPackageProduct(path: .init(finalBinPath))
            alreadyExisting.append(pkgInstance)
        }
    }
    
    struct Uninstall: SwiftCommand {
        
        static var configuration: CommandConfiguration {
            CommandConfiguration(commandName: "experimental-uninstall", abstract: "Offers the ability to uninstall executable products of installed package products")
        }
        
        @OptionGroup
        var globalOptions: GlobalOptions
        
        @Argument(help: "Name of the executable to uninstall.")
        var name: String
        
        func run(_ tool: SwiftTool) throws {
            let alreadyInstalled = (try? InstalledPackageProduct.installedProducts(tool.fileSystem)) ?? []
            
            guard let removedExecutable = alreadyInstalled.first(where: { $0.name == name }) else {
                // The installed executable doesn't exist - let the user know, and stop here.
                var stringError = "No such installed executable as \(name)"
                
                // and, in case there are any installed executables, let the user know which ones do exist.
                if !alreadyInstalled.isEmpty {
                    stringError += ", existing installed executables: \(alreadyInstalled.map(\.name).joined(separator: "\n"))"
                }
                
                throw StringError(stringError)
            }
            
            try tool.fileSystem.removeFileTree(removedExecutable.path)
            print("Executable product `\(name)` was successfully uninstalled from \(removedExecutable.path).")
        }
    }
}

fileprivate struct InstalledPackageProduct: Codable, Equatable {
    
    static func installedProducts(_ fileSystem: FileSystem) throws -> [InstalledPackageProduct] {
        let binPath = try fileSystem.getOrCreateSwiftPMInstalledBinariesDirectory()
        
        let contents = ((try? fileSystem.getDirectoryContents(binPath)) ?? [])
            .map { binPath.appending($0) }
        
        return contents.map { path in
            InstalledPackageProduct(path: .init(path))
        }
    }
    
    /// The name of this installed product, being the basename of the URL.
    var name: String {
        path.basename
    }
    
    /// Path of the executable
    let path: AbsolutePath
}
