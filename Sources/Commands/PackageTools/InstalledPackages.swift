//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023-2022 Apple Inc. and the Swift project authors
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
    
    struct Install: AsyncSwiftCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(abstract: "Offers the ability to install executable targets of the current package.")
        }
        
        @OptionGroup()
        var globalOptions: GlobalOptions
        
        @Option(help: "The name of the product to install")
        var product: String?
        
        func run(_ tool: SwiftTool) async throws {
            let swiftpmBinDir = try tool.fileSystem.getOrCreateSwiftPMInstalledBinariesDirectory()
            
            let env = ProcessInfo.processInfo.environment
            
            if let path = env.path, !path.contains(swiftpmBinDir.pathString), !globalOptions.logging.quiet {
                tool.observabilityScope.emit(warning: "PATH doesn't include \(swiftpmBinDir.pathString)! This means you won't be able to access the installed executables by default, and will need to specify the full path.")
            }
            
            let installedPackagesJSONPath = try tool.fileSystem.dotSwiftPM.appending(component: "installedPackages.json")
            
            var alreadyExisting = (try? InstalledPackage.registered(registryPath: .init(installedPackagesJSONPath), withFS: tool.fileSystem)) ?? []
            
            let workspace = try tool.getActiveWorkspace()
            let packageRoot = try tool.getPackageRoot()

            let packageGraph = try await workspace.loadRootPackage(at: packageRoot, observabilityScope: tool.observabilityScope)
            
            let possibleCanidates = packageGraph.products.filter { $0.type == .executable }
            let productToInstall: Product
            
            switch possibleCanidates.count {
            case 0:
                throw StringError("No Executable Products in Package.swift.")
            case 1:
                productToInstall = possibleCanidates[0]
            default: // More than one, check for possible
                guard let product, let first = possibleCanidates.first(where: { $0.name == product }) else {
                    throw StringError("Multiple canidates found, however, no product was specified. specify a product with the --product")
                }
                
                productToInstall = first
            }
            
            if let existingPkg = alreadyExisting.first(where: { $0.name == productToInstall.name }) {
                throw StringError("\(productToInstall.name) is already installed at \(existingPkg.url)")
            }
            
            try tool.createBuildSystem(explicitProduct: productToInstall.name).build(subset: .product(productToInstall.name))
            
            let binPath = try tool.buildParameters().buildPath.appending(component: productToInstall.name)
            let finalBinPath = swiftpmBinDir.appending(component: binPath.basename)
            try tool.fileSystem.copy(from: binPath, to: finalBinPath)
            
            let pkgInstance = InstalledPackage(name: productToInstall.name, url: .init(finalBinPath))
            alreadyExisting.append(pkgInstance)
            
            try JSONEncoder().encode(path: installedPackagesJSONPath, fileSystem: tool.fileSystem, alreadyExisting)
        }
    }
    
    struct Remove: SwiftCommand {
        @OptionGroup
        var globalOptions: GlobalOptions
        
        @Option(help: "Name of the executable to remove.")
        var name: String
        
        func run(_ tool: SwiftTool) throws {
            let dotSwiftPMDir = try tool.fileSystem.dotSwiftPM
            let registryURL = dotSwiftPMDir.appending(component: "installedPackages.json").asURL
            var alreadyRegistered = (try? InstalledPackage.registered(registryPath: .init(try tool.fileSystem.getOrCreateSwiftPMInstalledBinariesDirectory()),
                                                                      withFS: tool.fileSystem)) ?? []
            
            guard let whatWeWantToRemove = alreadyRegistered.first(where: { $0.name == name || $0.url.basename == name }) else {
                throw StringError("No such installed executable as \(name)")
            }
            
            try tool.fileSystem.removeFileTree(whatWeWantToRemove.url)
//            try FileManager.default.removeItem(at: whatWeWantToRemove.url)
            alreadyRegistered.removeAll(where: { $0 == whatWeWantToRemove })
            try JSONEncoder().encode(alreadyRegistered).write(to: registryURL)
            print("Removed \(name).")
        }
    }
}

fileprivate struct InstalledPackage: Codable, Equatable {
    
    static func registered(registryPath: AbsolutePath, withFS fileSystem: FileSystem) throws -> [InstalledPackage] {
        return try JSONDecoder().decode(path: .init(registryPath), fileSystem: fileSystem, as: [InstalledPackage].self)
    }
    
    // Name of the installed product
    let name: String
    
    
    // Path of the executable
    let url: AbsolutePath
}
