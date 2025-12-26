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

import ArgumentParserToolInfo
import Basics
import Foundation
@_spi(PackageRefactor) import SwiftRefactor
@_spi(FixItApplier) import SwiftIDEUtils

import SPMBuildCore
import SwiftParser
import SwiftSyntax

import TSCBasic
import TSCUtility

import struct PackageModel.InstalledSwiftPMConfiguration
import class PackageModel.Manifest
import struct PackageModel.SupportedPlatform

/// A class responsible for initializing a Swift package from a specified template.
///
/// This class handles creating the package structure, applying a template dependency
/// to the package manifest, and optionally prompting the user for input to customize
/// the generated package.
///
/// It supports different types of templates (local, git, registry) and multiple
/// testing libraries.
///
/// Usage:
/// - Initialize an instance with the package name, template details, file system, destination path, etc.
/// - Call `setupTemplateManifest()` to create the package and add the template dependency.
/// - Use `promptUser(tool:)` to interactively prompt the user for command line argument values.

public struct InitTemplatePackage {
    /// The kind of package dependency to add for the template.
    let packageDependency: SwiftRefactor.PackageDependency

    /// The set of testing libraries supported by the generated package.
    public var supportedTestingLibraries: Set<TestingLibrary>

    /// The file system abstraction to use for file operations.
    let fileSystem: FileSystem

    /// The absolute path where the package will be created.
    let destinationPath: Basics.AbsolutePath

    /// Configuration information from the installed Swift Package Manager toolchain.
    let installedSwiftPMConfiguration: InstalledSwiftPMConfiguration
    /// The name of the package to create.
    public var packageName: String

    /// The type of package to create (e.g., library, executable).
    let packageType: InitPackage.PackageType

    /// Options used to configure package initialization.
    public struct InitPackageOptions {
        /// The type of package to create.
        public var packageType: InitPackage.PackageType

        /// The set of supported testing libraries to include in the package.
        public var supportedTestingLibraries: Set<TestingLibrary>

        /// The list of supported platforms to target in the manifest.
        ///
        /// Note: Currently only Apple platforms are supported.
        public var platforms: [SupportedPlatform]

        /// Creates a new `InitPackageOptions` instance.
        /// - Parameters:
        ///   - packageType: The type of package to create.
        ///   - supportedTestingLibraries: The set of testing libraries to support.
        ///   - platforms: The list of supported platforms (default is empty).

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

    /// The type of template source.
    public enum TemplateSource: String, CustomStringConvertible {
        case local
        case git
        case registry

        public var description: String {
            rawValue
        }
    }

    /// Creates a new `InitTemplatePackage` instance.
    ///
    /// - Parameters:
    ///   - name: The name of the package to create.
    ///   - templateName: The name of the template to use.
    ///   - initMode: The kind of package dependency to add for the template.
    ///   - templatePath: The file system path to the template files.
    ///   - fileSystem: The file system to use for operations.
    ///   - packageType: The type of package to create (e.g., library, executable).
    ///   - supportedTestingLibraries: The set of testing libraries to support.
    ///   - destinationPath: The directory where the new package should be created.
    ///   - installedSwiftPMConfiguration: Configuration from the SwiftPM toolchain.

    package init(
        name: String,
        initMode: SwiftRefactor.PackageDependency,
        fileSystem: FileSystem,
        packageType: InitPackage.PackageType,
        supportedTestingLibraries: Set<TestingLibrary>,
        destinationPath: Basics.AbsolutePath,
        installedSwiftPMConfiguration: InstalledSwiftPMConfiguration,
    ) {
        self.packageName = name
        self.packageDependency = initMode
        self.packageType = packageType
        self.supportedTestingLibraries = supportedTestingLibraries
        self.destinationPath = destinationPath
        self.installedSwiftPMConfiguration = installedSwiftPMConfiguration
        self.fileSystem = fileSystem
    }

    /// Sets up the package manifest by creating the package structure and
    /// adding the template dependency to the manifest.
    ///
    /// This method initializes an empty package using `InitPackage`, writes the
    /// package structure, and then applies the template dependency to the manifest file.
    ///
    /// - Throws: An error if package initialization or manifest modification fails.
    public func setupTemplateManifest() throws {
        // initialize empty swift package
        let initializedPackage = try InitPackage(
            name: self.packageName,
            options: .init(packageType: self.packageType, supportedTestingLibraries: self.supportedTestingLibraries),
            destinationPath: self.destinationPath,
            installedSwiftPMConfiguration: self.installedSwiftPMConfiguration,
            fileSystem: self.fileSystem
        )
        try initializedPackage.writePackageStructure()
        try self.initializePackageFromTemplate()
    }

    /// Initializes the package by adding the template dependency to the manifest.
    ///
    /// - Throws: An error if adding the dependency or modifying the manifest fails.
    private func initializePackageFromTemplate() throws {
        try self.addTemplateDepenency()
    }

    /// Adds the template dependency to the package manifest.
    ///
    /// This reads the manifest file, parses it into a syntax tree, modifies it
    /// to include the template dependency, and then writes the updated manifest
    /// back to disk.
    ///
    /// - Throws: An error if the manifest file cannot be read, parsed, or modified.

    private func addTemplateDepenency() throws {
        let manifestPath = self.destinationPath.appending(component: Manifest.filename)
        let manifestContents: ByteString

        do {
            manifestContents = try self.fileSystem.readFileContents(manifestPath)
        } catch {
            throw StringError("Cannot find package manifest in \(manifestPath)")
        }

        let manifestSyntax = manifestContents.withData { data in
            data.withUnsafeBytes { buffer in
                buffer.withMemoryRebound(to: UInt8.self) { buffer in
                    Parser.parse(source: buffer)
                }
            }
        }

        let editResult = try SwiftRefactor.AddPackageDependency.textRefactor(
            syntax: manifestSyntax,
            in: SwiftRefactor.AddPackageDependency.Context(dependency: self.packageDependency)
        )

        try editResult.applyEdits(
            to: self.fileSystem,
            manifest: manifestSyntax,
            manifestPath: manifestPath,
            verbose: false
        )
    }
}

extension [SourceEdit] {
    /// Apply the edits for the given manifest to the specified file system,
    /// updating the manifest to the given manifest
    func applyEdits(
        to filesystem: any FileSystem,
        manifest: SourceFileSyntax,
        manifestPath: Basics.AbsolutePath,
        verbose: Bool
    ) throws {
        let rootPath = manifestPath.parentDirectory

        // Update the manifest
        if verbose {
            print("Updating package manifest at \(manifestPath.relative(to: rootPath))...", terminator: "")
        }

        let updatedManifestSource = FixItApplier.apply(
            edits: self,
            to: manifest
        )
        try filesystem.writeFileContents(
            manifestPath,
            string: updatedManifestSource
        )
        if verbose {
            print(" done.")
        }
    }
}
