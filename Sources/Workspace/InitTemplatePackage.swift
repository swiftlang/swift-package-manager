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
import Foundation
import Basics
import PackageModel
import SPMBuildCore
import TSCUtility
import System
import PackageModelSyntax
import TSCBasic
import SwiftParser


public final class InitTemplatePackage {

    var initMode: TemplateType

    public var supportedTestingLibraries: Set<TestingLibrary>


    let templateName: String
    /// The file system to use
    let fileSystem: FileSystem

    /// Where to create the new package
    let destinationPath: Basics.AbsolutePath

    /// Configuration from the used toolchain.
    let installedSwiftPMConfiguration: InstalledSwiftPMConfiguration

    var packageName: String


    var templatePath: Basics.AbsolutePath

    let packageType: InitPackage.PackageType

    public struct InitPackageOptions {
        /// The type of package to create.
        public var packageType: InitPackage.PackageType

        /// The set of supported testing libraries to include in the package.
        public var supportedTestingLibraries: Set<TestingLibrary>

        /// The list of platforms in the manifest.
        ///
        /// Note: This should only contain Apple platforms right now.
        public var platforms: [SupportedPlatform]

        public init(
            packageType: InitPackage.PackageType,
            supportedTestingLibraries: Set<TestingLibrary>,
            platforms: [SupportedPlatform] = []
        ) {
            self.packageType = packageType
            self.supportedTestingLibraries = supportedTestingLibraries
            self.platforms = platforms
        }
    }



    public enum TemplateType: String, CustomStringConvertible {
        case local = "local"
        case git = "git"
        case registry = "registry"

        public var description: String {
            return rawValue
        }
    }




    public init(
        name: String,
        templateName: String,
        initMode: TemplateType,
        templatePath: Basics.AbsolutePath,
        fileSystem: FileSystem,
        packageType: InitPackage.PackageType,
        supportedTestingLibraries: Set<TestingLibrary>,
        destinationPath: Basics.AbsolutePath,
        installedSwiftPMConfiguration: InstalledSwiftPMConfiguration,
    ) {
        self.packageName = name
        self.initMode = initMode
        self.templatePath = templatePath
        self.packageType = packageType
        self.supportedTestingLibraries = supportedTestingLibraries
        self.destinationPath = destinationPath
        self.installedSwiftPMConfiguration = installedSwiftPMConfiguration
        self.fileSystem = fileSystem
        self.templateName = templateName
    }


    public func setupTemplateManifest() throws {
        // initialize empty swift package
        let initializedPackage = try InitPackage(name: self.packageName, options: .init(packageType: self.packageType, supportedTestingLibraries: self.supportedTestingLibraries), destinationPath: self.destinationPath, installedSwiftPMConfiguration: self.installedSwiftPMConfiguration, fileSystem: self.fileSystem)
        try initializedPackage.writePackageStructure()
        try initializePackageFromTemplate()

        //try  build
        // try --experimental-help-dump
        //prompt
        //run the executable.
    }

    private func initializePackageFromTemplate() throws {
        try addTemplateDepenency()
    }

    private func addTemplateDepenency() throws {


        let manifestPath = destinationPath.appending(component: Manifest.filename)
        let manifestContents: ByteString

        do {
            manifestContents = try fileSystem.readFileContents(manifestPath)
        } catch {
            throw StringError("Cannot fin package manifest in \(manifestPath)")
        }

        let manifestSyntax = manifestContents.withData { data in
            data.withUnsafeBytes { buffer in
                buffer.withMemoryRebound(to: UInt8.self) { buffer in
                    Parser.parse(source: buffer)
                }
            }
        }

        let editResult = try AddPackageDependency.addPackageDependency(
            .fileSystem(name: nil, path: self.templatePath.pathString), to: manifestSyntax)

        try editResult.applyEdits(to: fileSystem, manifest: manifestSyntax, manifestPath: manifestPath, verbose: false)
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
        case .invalidPath:
            return "Path does not exist, or is invalid."
        }
    }
}
