import ArgumentParser
import ArgumentParserToolInfo

import Basics

@_spi(SwiftPMInternal)
import CoreCommands

@_spi(PackageRefactor) import SwiftRefactor
import Workspace
import SPMBuildCore
import TSCBasic
import TSCUtility
import Foundation
import PackageGraph

import class PackageModel.Manifest
protocol PackageInitializer {
    func run() async throws
}

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

    func run() async throws {
        do {
            var sourceControlRequirement: PackageDependency.SourceControl.Requirement?
            var registryRequirement: PackageDependency.Registry.Requirement?

            swiftCommandState.observabilityScope.emit(debug: "Fetching versioning requirements and resolving path of template on local disk.")

            switch templateSource {
            case .local:
                sourceControlRequirement = nil
                registryRequirement = nil
            case .git:
                sourceControlRequirement = try? versionResolver.resolveSourceControl()
                registryRequirement = nil
            case .registry:
                sourceControlRequirement = nil
                registryRequirement = try? await versionResolver.resolveRegistry()
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

            let directoryManager = TemplateInitializationDirectoryManager(fileSystem: swiftCommandState.fileSystem, observabilityScope: swiftCommandState.observabilityScope)
            let (stagingPath, cleanupPath, tempDir) = try directoryManager.createTemporaryDirectories()

            swiftCommandState.observabilityScope.emit(debug: "Inferring initial type of consumer's package based on template's specifications.")

            let packageType = try await TemplatePackageInitializer.inferPackageType(from: resolvedTemplatePath, templateName: templateName, swiftCommandState: swiftCommandState)
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

            swiftCommandState.observabilityScope.emit(debug: "Finished setting up initial package: \(templatePackage.packageName).")

            swiftCommandState.observabilityScope.emit(debug: "Building package with dependency on template.")

            try await TemplateBuildSupport.build(
                swiftCommandState: swiftCommandState,
                buildOptions: buildOptions,
                globalOptions: globalOptions,
                cwd: stagingPath,
                transitiveFolder: stagingPath
            )

            swiftCommandState.observabilityScope.emit(debug: "Running plugin steps, including prompting and running the template package's plugin.")

            let buildSystem = globalOptions.build.buildSystem != .native ?
            globalOptions.build.buildSystem :
            swiftCommandState.options.build.buildSystem

            try await TemplateInitializationPluginManager(
                swiftCommandState: swiftCommandState,
                template: templateName,
                scratchDirectory: stagingPath,
                args: args,
                buildSystem: buildSystem
            ).run()

            try await directoryManager.finalize(cwd: cwd, stagingPath: stagingPath, cleanupPath: cleanupPath, swiftCommandState: swiftCommandState)

            if validatePackage {
                try await TemplateBuildSupport.build(
                    swiftCommandState: swiftCommandState,
                    buildOptions: buildOptions,
                    globalOptions: globalOptions,
                    cwd: cwd
                )
            }

            try directoryManager.cleanupTemporary(templateSource: templateSource, path: resolvedTemplatePath, temporaryDirectory: tempDir)

        } catch {
            swiftCommandState.observabilityScope.emit(error)
        }
    }

    //Will have to add checking for git + registry too
    static func inferPackageType(from templatePath: Basics.AbsolutePath, templateName: String?, swiftCommandState: SwiftCommandState) async throws -> InitPackage.PackageType {
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
                targetName = try findTemplateName(from: manifest)
            }

            for target in manifest.targets {
                if target.name == targetName,
                    let options = target.templateInitializationOptions,
                    case .packageInit(let type, _, _) = options {
                    return try .init(from: type)
                }
            }

            throw TemplatePackageInitializerError.templateNotFound(templateName ?? "<unspecified>")
        }
    }

    static func findTemplateName(from manifest: Manifest) throws -> String {
        let templateTargets = manifest.targets.compactMap { target -> String? in
            if let options = target.templateInitializationOptions,
               case .packageInit = options {
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


    private func setUpPackage(
        builder: DefaultPackageDependencyBuilder,
        packageType: InitPackage.PackageType,
        stagingPath: Basics.AbsolutePath
    ) throws -> InitTemplatePackage {
        let templatePackage = try InitTemplatePackage(
            name: packageName,
            initMode: try builder.makePackageDependency(),
            templatePath: builder.resolvedTemplatePath,
            fileSystem: swiftCommandState.fileSystem,
            packageType: packageType,
            supportedTestingLibraries: [],
            destinationPath: stagingPath,
            installedSwiftPMConfiguration: swiftCommandState.getHostToolchain().installedSwiftPMConfiguration
        )

        try templatePackage.setupTemplateManifest()
        return templatePackage
    }

    enum TemplatePackageInitializerError: Error, CustomStringConvertible {
        case invalidManifestInTemplate(String)
        case templateNotFound(String)
        case noTemplatesInManifest
        case multipleTemplatesFound([String])

        var description: String {
            switch self {
            case .invalidManifestInTemplate(let path):
                return "Invalid manifest found in template at \(path)."
            case .templateNotFound(let templateName):
                return "Could not find template \(templateName)."
            case .noTemplatesInManifest:
                return "No templates with packageInit options were found in the manifest."
            case .multipleTemplatesFound(let templates):
                return "Multiple templates found: \(templates.joined(separator: ", ")). Please specify one using --template."

            }
        }
    }

}



struct StandardPackageInitializer: PackageInitializer {
    let packageName: String
    let initMode: String?
    let testLibraryOptions: TestLibraryOptions
    let cwd: Basics.AbsolutePath
    let swiftCommandState: SwiftCommandState

    func run() async throws {

        guard let initModeString = self.initMode else {
            throw StandardPackageInitializerError.missingInitMode
        }
        guard let knownType = InitPackage.PackageType(rawValue: initModeString) else {
            throw StandardPackageInitializerError.unsupportedPackageType(initModeString)
        }
        // Configure testing libraries
        var supportedTestingLibraries = Set<TestingLibrary>()
        if testLibraryOptions.isExplicitlyEnabled(.xctest, swiftCommandState: swiftCommandState) ||
            (knownType == .macro && testLibraryOptions.isEnabled(.xctest, swiftCommandState: swiftCommandState)) {
            supportedTestingLibraries.insert(.xctest)
        }
        if testLibraryOptions.isExplicitlyEnabled(.swiftTesting, swiftCommandState: swiftCommandState) ||
            (knownType != .macro && testLibraryOptions.isEnabled(.swiftTesting, swiftCommandState: swiftCommandState)) {
            supportedTestingLibraries.insert(.swiftTesting)
        }

        let initPackage = try InitPackage(
            name: packageName,
            packageType: knownType,
            supportedTestingLibraries: supportedTestingLibraries,
            destinationPath: cwd,
            installedSwiftPMConfiguration: swiftCommandState.getHostToolchain().installedSwiftPMConfiguration,
            fileSystem: swiftCommandState.fileSystem
        )
        initPackage.progressReporter = { message in print(message) }
        try initPackage.writePackageStructure()
    }

    enum StandardPackageInitializerError: Error, CustomStringConvertible {
        case missingInitMode
        case unsupportedPackageType(String)

        var description: String {
            switch self {
            case .missingInitMode:
                return "Specify a package type using the --type option."
            case .unsupportedPackageType(let type):
                return "Package type '\(type)' is not supported."
            }
        }
    }
}

