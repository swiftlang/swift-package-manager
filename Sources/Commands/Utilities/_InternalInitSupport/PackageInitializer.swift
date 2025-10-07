import ArgumentParser
import ArgumentParserToolInfo

import Basics

@_spi(SwiftPMInternal)
import CoreCommands

import Foundation
import PackageGraph
import SPMBuildCore
@_spi(PackageRefactor) import SwiftRefactor
import TSCBasic
import TSCUtility
import Workspace

import class PackageModel.Manifest

/// Protocol for package initialization implementations.
protocol PackageInitializer {
    func run() async throws
}

/// Initializes a package from a template source.
struct TemplatePackageInitializer: PackageInitializer {
    let packageName: String
    let cwd: Basics.AbsolutePath
    let templateSource: InitTemplatePackage.TemplateSource
    let templateName: String?
    let templateDirectory: Basics.AbsolutePath?
    let templateURL: String?
    let templatePackageID: String?
    let versionResolver: DependencyRequirementResolver
    let buildOptions: BuildCommandOptions
    let globalOptions: GlobalOptions
    let validatePackage: Bool
    let args: [String]
    let swiftCommandState: SwiftCommandState

    /// Runs the template initialization process.
    func run() async throws {
        do {
            var sourceControlRequirement: PackageDependency.SourceControl.Requirement?
            var registryRequirement: PackageDependency.Registry.Requirement?

            self.swiftCommandState.observabilityScope
                .emit(debug: "Fetching versioning requirements and resolving path of template on local disk.")

            switch self.templateSource {
            case .local:
                sourceControlRequirement = nil
                registryRequirement = nil
            case .git:
                sourceControlRequirement = try? self.versionResolver.resolveSourceControl()
                registryRequirement = nil
            case .registry:
                sourceControlRequirement = nil
                registryRequirement = try? await self.versionResolver.resolveRegistry()
            }

            // Resolve version requirements
            let resolvedTemplatePath = try await TemplatePathResolver(
                source: templateSource,
                templateDirectory: templateDirectory,
                templateURL: templateURL,
                sourceControlRequirement: sourceControlRequirement,
                registryRequirement: registryRequirement,
                packageIdentity: templatePackageID,
                swiftCommandState: swiftCommandState
            ).resolve()

            let directoryManager = TemplateInitializationDirectoryManager(
                fileSystem: swiftCommandState.fileSystem,
                observabilityScope: self.swiftCommandState.observabilityScope
            )
            let (stagingPath, cleanupPath, tempDir) = try directoryManager.createTemporaryDirectories()

            self.swiftCommandState.observabilityScope
                .emit(debug: "Inferring initial type of consumer's package based on template's specifications.")

            let resolvedTemplateName: String = if self.templateName == nil {
                try await self.findTemplateName(from: resolvedTemplatePath)
            } else {
                self.templateName!
            }

            let packageType = try await TemplatePackageInitializer.inferPackageType(
                from: resolvedTemplatePath,
                templateName: resolvedTemplateName,
                swiftCommandState: self.swiftCommandState
            )

            let builder = DefaultPackageDependencyBuilder(
                templateSource: templateSource,
                packageName: packageName,
                templateURL: templateURL,
                templatePackageID: templatePackageID,
                sourceControlRequirement: sourceControlRequirement,
                registryRequirement: registryRequirement,
                resolvedTemplatePath: resolvedTemplatePath
            )

            let templatePackage = try setUpPackage(builder: builder, packageType: packageType, stagingPath: stagingPath)

            self.swiftCommandState.observabilityScope
                .emit(debug: "Finished setting up initial package: \(templatePackage.packageName).")

            self.swiftCommandState.observabilityScope.emit(debug: "Building package with dependency on template.")

            try await TemplateBuildSupport.build(
                swiftCommandState: self.swiftCommandState,
                buildOptions: self.buildOptions,
                globalOptions: self.globalOptions,
                cwd: stagingPath,
                transitiveFolder: stagingPath
            )

            self.swiftCommandState.observabilityScope
                .emit(debug: "Running plugin steps, including prompting and running the template package's plugin.")

            let buildSystem = self.globalOptions.build.buildSystem != .native ?
                self.globalOptions.build.buildSystem :
                self.swiftCommandState.options.build.buildSystem

            try await TemplateInitializationPluginManager(
                swiftCommandState: self.swiftCommandState,
                template: resolvedTemplateName,
                scratchDirectory: stagingPath,
                args: self.args,
                buildSystem: buildSystem
            ).run()

            try await directoryManager.finalize(
                cwd: self.cwd,
                stagingPath: stagingPath,
                cleanupPath: cleanupPath,
                swiftCommandState: self.swiftCommandState
            )

            if self.validatePackage {
                try await TemplateBuildSupport.build(
                    swiftCommandState: self.swiftCommandState,
                    buildOptions: self.buildOptions,
                    globalOptions: self.globalOptions,
                    cwd: self.cwd
                )
            }

            try directoryManager.cleanupTemporary(
                templateSource: self.templateSource,
                path: resolvedTemplatePath,
                temporaryDirectory: tempDir
            )

        } catch {
            self.swiftCommandState.observabilityScope.emit(error)
            throw error
        }
    }

    /// Infers the package type from a template at the given path.
    static func inferPackageType(
        from templatePath: Basics.AbsolutePath,
        templateName: String?,
        swiftCommandState: SwiftCommandState
    ) async throws -> InitPackage.PackageType {
        try await swiftCommandState.withTemporaryWorkspace(switchingTo: templatePath) { workspace, root in
            let rootManifests = try await workspace.loadRootManifests(
                packages: root.packages,
                observabilityScope: swiftCommandState.observabilityScope
            )

            guard let manifest = rootManifests.values.first else {
                throw TemplatePackageInitializerError.invalidManifestInTemplate(root.packages.description)
            }

            var targetName = templateName

            if targetName == nil {
                targetName = try TemplatePackageInitializer.findTemplateName(from: manifest)
            }

            for target in manifest.targets {
                if target.name == targetName,
                   let options = target.templateInitializationOptions,
                   case .packageInit(let type, _, _) = options
                {
                    return try .init(from: type)
                }
            }
            throw TemplatePackageInitializerError.templateNotFound(templateName ?? "<unspecified>")
        }
    }

    /// Finds the template name from a manifest.
    static func findTemplateName(from manifest: Manifest) throws -> String {
        let templateTargets = manifest.targets.compactMap { target -> String? in
            if let options = target.templateInitializationOptions,
               case .packageInit = options
            {
                return target.name
            }
            return nil
        }

        switch templateTargets.count {
        case 0:
            throw TemplatePackageInitializerError.noTemplatesInManifest
        case 1:
            return templateTargets[0]
        default:
            throw TemplatePackageInitializerError.multipleTemplatesFound(templateTargets)
        }
    }

    /// Finds the template name from a template path.
    func findTemplateName(from templatePath: Basics.AbsolutePath) async throws -> String {
        try await self.swiftCommandState.withTemporaryWorkspace(switchingTo: templatePath) { workspace, root in
            let rootManifests = try await workspace.loadRootManifests(
                packages: root.packages,
                observabilityScope: self.swiftCommandState.observabilityScope
            )

            guard let manifest = rootManifests.values.first else {
                throw TemplatePackageInitializerError.invalidManifestInTemplate(root.packages.description)
            }

            return try TemplatePackageInitializer.findTemplateName(from: manifest)
        }
    }

    /// Sets up the package with the template dependency.
    private func setUpPackage(
        builder: DefaultPackageDependencyBuilder,
        packageType: InitPackage.PackageType,
        stagingPath: Basics.AbsolutePath
    ) throws -> InitTemplatePackage {
        let templatePackage = try InitTemplatePackage(
            name: packageName,
            initMode: builder.makePackageDependency(),
            fileSystem: self.swiftCommandState.fileSystem,
            packageType: packageType,
            supportedTestingLibraries: [],
            destinationPath: stagingPath,
            installedSwiftPMConfiguration: self.swiftCommandState.getHostToolchain().installedSwiftPMConfiguration
        )

        try templatePackage.setupTemplateManifest()
        return templatePackage
    }

    /// Errors that can occur during template package initialization.
    enum TemplatePackageInitializerError: Error, CustomStringConvertible {
        case invalidManifestInTemplate(String)
        case templateNotFound(String)
        case noTemplatesInManifest
        case multipleTemplatesFound([String])

        var description: String {
            switch self {
            case .invalidManifestInTemplate(let path):
                "Invalid manifest found in template at \(path)."
            case .templateNotFound(let templateName):
                "Could not find template \(templateName)."
            case .noTemplatesInManifest:
                "No templates with packageInit options were found in the manifest."
            case .multipleTemplatesFound(let templates):
                "Multiple templates found: \(templates.joined(separator: ", ")). Please specify one using --template."
            }
        }
    }
}

/// Initializes a package using built-in templates.
struct StandardPackageInitializer: PackageInitializer {
    let packageName: String
    let initMode: String?
    let testLibraryOptions: TestLibraryOptions
    let cwd: Basics.AbsolutePath
    let swiftCommandState: SwiftCommandState

    /// Runs the standard package initialization process.
    func run() async throws {
        guard let initModeString = self.initMode else {
            throw StandardPackageInitializerError.missingInitMode
        }
        guard let knownType = InitPackage.PackageType(rawValue: initModeString) else {
            throw StandardPackageInitializerError.unsupportedPackageType(initModeString)
        }
        // Configure testing libraries
        var supportedTestingLibraries = Set<TestingLibrary>()
        if self.testLibraryOptions.isExplicitlyEnabled(.xctest, swiftCommandState: self.swiftCommandState) ||
            (knownType == .macro && self.testLibraryOptions.isEnabled(
                .xctest,
                swiftCommandState: self.swiftCommandState
            ))
        {
            supportedTestingLibraries.insert(.xctest)
        }
        if self.testLibraryOptions.isExplicitlyEnabled(.swiftTesting, swiftCommandState: self.swiftCommandState) ||
            (knownType != .macro && self.testLibraryOptions.isEnabled(
                .swiftTesting,
                swiftCommandState: self.swiftCommandState
            ))
        {
            supportedTestingLibraries.insert(.swiftTesting)
        }

        let initPackage = try InitPackage(
            name: packageName,
            packageType: knownType,
            supportedTestingLibraries: supportedTestingLibraries,
            destinationPath: cwd,
            installedSwiftPMConfiguration: swiftCommandState.getHostToolchain().installedSwiftPMConfiguration,
            fileSystem: self.swiftCommandState.fileSystem
        )
        initPackage.progressReporter = { message in print(message) }
        try initPackage.writePackageStructure()
    }

    /// Errors that can occur during standard package initialization.
    enum StandardPackageInitializerError: Error, CustomStringConvertible {
        case missingInitMode
        case unsupportedPackageType(String)

        var description: String {
            switch self {
            case .missingInitMode:
                "Specify a package type using the --type option."
            case .unsupportedPackageType(let type):
                "Package type '\(type)' is not supported."
            }
        }
    }
}
