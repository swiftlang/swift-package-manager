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
    
    struct Install: SwiftCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(abstract: "Offers the ability to install executable targets of the current package.")
        }
        
        @OptionGroup()
        var globalOptions: GlobalOptions
        
        func run(_ tool: SwiftTool) throws {
            let dotSwiftPMDir = try tool.fileSystem.getOrCreateDotSwiftPMDirectory()
            
            let env = ProcessInfo.processInfo.environment
            

            // ~/.swiftpm/bin/
            let swiftpmBinDir = dotSwiftPMDir.appending(component: "bin")
            
            if let path = env.path, !path.contains(swiftpmBinDir.pathString), env["SWIFTPM_SHUT_UP_ABOUT_EXECUTABLE_PATH"] == nil {
                tool.observabilityScope.emit(warning: "PATH doesn't include \(swiftpmBinDir.pathString)! This means you won't be able to access the installed executables by default, and will need to specify the full path. If you wish to stop seeing this warning, set the enviroment variable `SWIFTPM_SHUT_UP_ABOUT_EXECUTABLE_PATH`.")
            }
            
            let registryURL = dotSwiftPMDir.appending(component: "installedPackages.json").asURL
            
            var alreadyExisting = (try? InstalledPackage.registered(registryURL: registryURL)) ?? []
            
            let workspace = try tool.getActiveWorkspace()
            let packageRoot = try tool.getPackageRoot()

            let packageGraph = try tsc_await {
                workspace.loadRootPackage(at: packageRoot, observabilityScope: tool.observabilityScope, completion: $0)
            }
            
            let possibleCanidates = packageGraph.products.filter { $0.type == .executable }
            let productToInstall: Product
            
            switch possibleCanidates.count {
            case 0:
                throw StringError("No Executable Products in Package.swift.")
            case 1:
                productToInstall = possibleCanidates[0]
            default: // More than one, ask the user which one they wanna install
                print("More than one executable target selected, please select of the following which you'd like to install by typing the number and pressing enter:")
                for (index, product) in possibleCanidates.enumerated() {
                    print("[\(index)] \(product.name)")
                }
                
                guard let input = readLine(), let int = Int(input), possibleCanidates.indices.contains(int) else {
                    throw StringError("Input should be a number between 0 and \(possibleCanidates.count - 1).")
                }
                
                productToInstall = possibleCanidates[int]
            }
            
            if let existingPkg = alreadyExisting.first(where: { $0.name == productToInstall.name }) {
                throw StringError("\(productToInstall.name) is already installed at \(existingPkg.url)")
            }
            
            try tool.createBuildSystem(explicitProduct: productToInstall.name).build(subset: .product(productToInstall.name))
            
            let binPath = try tool.buildParameters().buildPath.appending(component: productToInstall.name)
            let finalBinPath = swiftpmBinDir.appending(component: binPath.basename)
            try tool.fileSystem.move(from: binPath, to: finalBinPath)
            
            let pkgInstance = InstalledPackage(name: productToInstall.name, url: finalBinPath.asURL)
            alreadyExisting.append(pkgInstance)
            try JSONEncoder().encode(alreadyExisting).write(to: registryURL)
        }
    }
    
    struct Remove: SwiftCommand {
        
        @OptionGroup
        var globalOptions: GlobalOptions
        
        @Option(help: "Name of the executable to remove.")
        var name: String
        
        func run(_ tool: SwiftTool) throws {
            let dotSwiftPMDir = try tool.fileSystem.getOrCreateDotSwiftPMDirectory()
            let registryURL = dotSwiftPMDir.appending(component: "installedPackages.json").asURL
            var alreadyRegistered = (try? InstalledPackage.registered(registryURL: registryURL)) ?? []
            
            guard let whatWeWantToRemove = alreadyRegistered.first(where: { $0.name == name || $0.url.lastPathComponent == name }) else {
                throw StringError("No such installed executable as \(name)")
            }
            
            try FileManager.default.removeItem(at: whatWeWantToRemove.url)
            alreadyRegistered.removeAll(where: { $0 == whatWeWantToRemove })
            try JSONEncoder().encode(alreadyRegistered).write(to: registryURL)
            print("Removed \(name).")
        }
    }
}

fileprivate struct InstalledPackage: Codable, Equatable {
    
    // to not conflict with in-house ``URL`` type
    typealias URL = Foundation.URL
    
    static func registered(registryURL: URL) throws -> [InstalledPackage] {
        let data = try Data(contentsOf: registryURL)
        return try JSONDecoder().decode([InstalledPackage].self, from: data)
    }
    
    // Name of the installed product
    let name: String
    // Path of the executable
    let url: URL
}
