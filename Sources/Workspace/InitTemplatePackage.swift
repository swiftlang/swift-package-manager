//
//  InitTemplatePackage.swift
//  SwiftPM
//
//  Created by John Bute on 2025-05-13.
//
import Basics
import PackageModel
import SPMBuildCore
import TSCUtility
@_spi(SwiftPMInternal)
import Foundation
import Commands


final class InitTemplatePackage {
    
    
    
    var initMode: TemplateType

    
    var packageName: String?
    
    var templatePath: AbsolutePath

    let fileSystem: FileSystem

    init(initMode: InitPackage.PackageType, packageName: String? = nil, templatePath: AbsolutePath, fileSystem: FileSystem) {
        self.initMode = initMode
        self.packageName = packageName
        self.templatePath = templatePath
        self.fileSystem = fileSystem

    }
    
    
    private func checkTemplateExists(templatePath: AbsolutePath) throws {
        //Checks if there is a package in directory, if it contains a .template command line-tool and if it contains a /template folder.
        
        //check if the path does exist
        guard self.fileSystem.exists(templatePath) else {
            throw TemplateError.invalidPath
        }

        // Check if Package.swift exists in the directory
        let manifest = templatePath.appending(component: Manifest.filename)
        guard self.fileSystem.exists(manifest) else {
            throw TemplateError.invalidPath
        }

        //check if package.swift contains a .plugin
        
        //check if it contains a template folder
        
    }

    func initPackage(_ swiftCommandState: SwiftCommandState) throws {

        //Logic here for initializing initial package (should find better way to organize this but for now)
        guard let cwd = swiftCommandState.fileSystem.currentWorkingDirectory else {
            throw InternalError("Could not find the current working directory")
        }

        let packageName = self.packageName ?? cwd.basename

        // Testing is on by default, with XCTest only enabled explicitly.
        // For macros this is reversed, since we don't support testing
        // macros with Swift Testing yet.
        var supportedTestingLibraries = Set<TestingLibrary>()
        if testLibraryOptions.isExplicitlyEnabled(.xctest, swiftCommandState: swiftCommandState) ||
            (initMode == .macro && testLibraryOptions.isEnabled(.xctest, swiftCommandState: swiftCommandState)) {
            supportedTestingLibraries.insert(.xctest)
        }
        if testLibraryOptions.isExplicitlyEnabled(.swiftTesting, swiftCommandState: swiftCommandState) ||
            (initMode != .macro && testLibraryOptions.isEnabled(.swiftTesting, swiftCommandState: swiftCommandState)) {
            supportedTestingLibraries.insert(.swiftTesting)
        }

        let initPackage = try InitPackage(
            name: packageName,
            packageType: initMode,
            supportedTestingLibraries: supportedTestingLibraries,
            destinationPath: cwd,
            installedSwiftPMConfiguration: swiftCommandState.getHostToolchain().installedSwiftPMConfiguration,
            fileSystem: swiftCommandState.fileSystem
        )
        initPackage.progressReporter = { message in
            print(message)
        }
        try initPackage.writePackageStructure()
    }
}

private enum TemplateError: Swift.Error {
    case invalidPath
    case manifestAlreadyExists
}


extension TemplateError: CustomStringConvertible {
    var description: String {
        switch self {
        case .manifestAlreadyExists:
            return "a manifest file already exists in this directory"
        case let .invalidPath:
            return "Path does not exist, or is invalid."
        }
    }
}
