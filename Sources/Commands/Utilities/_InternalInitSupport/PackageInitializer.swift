import ArgumentParser
import ArgumentParserToolInfo

import Basics

@_spi(SwiftPMInternal)
import CoreCommands

import PackageModel
import Workspace
import SPMBuildCore
import TSCBasic
import TSCUtility
import Foundation
import PackageGraph

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
        let directoryManager = TemplateInitializationDirectoryManager(fileSystem: swiftCommandState.fileSystem)
        try precheck()

        let sourceControlRequirement = try? versionResolver.resolveSourceControl()
        let registryRequirement = try? versionResolver.resolveRegistry()

        let resolvedTemplatePath = try await TemplatePathResolver(
            source: templateSource,
            templateDirectory: templateDirectory,
            templateURL: templateURL,
            sourceControlRequirement: sourceControlRequirement,
            registryRequirement: registryRequirement,
            packageIdentity: templatePackageID,
            swiftCommandState: swiftCommandState
        ).resolve()

        let (stagingPath, cleanupPath, tempDir) = try directoryManager.createTemporaryDirectories()

        let initType = try await inferPackageType(from: resolvedTemplatePath)

        let builder = DefaultPackageDependencyBuilder(
            templateSource: templateSource,
            packageName: packageName,
            templateURL: templateURL,
            templatePackageID: templatePackageID,
            sourceControlRequirement: sourceControlRequirement,
            registryRequirement: registryRequirement,
            resolvedTemplatePath: resolvedTemplatePath
        )

        let templatePackage = try setUpPackage(builder: builder, packageType: initType, stagingPath: stagingPath)

        try await TemplateBuildSupport.build(
            swiftCommandState: swiftCommandState,
            buildOptions: buildOptions,
            globalOptions: globalOptions,
            cwd: stagingPath,
            transitiveFolder: stagingPath
        )

        try await TemplatePluginManager(
            swiftCommandState: swiftCommandState,
            template: templateName,
            scratchDirectory: stagingPath,
            args: args
        ).run(templatePackage)

        try await directoryManager.finalize(cwd: cwd, stagingPath: stagingPath, cleanupPath: cleanupPath, swiftCommandState: swiftCommandState)

        if validatePackage {
            try await TemplateBuildSupport.build(
                swiftCommandState: swiftCommandState,
                buildOptions: buildOptions,
                globalOptions: globalOptions,
                cwd: cwd
            )
        }

        try directoryManager.cleanupTemporary(templateSource: templateSource, path: resolvedTemplatePath, tempDir: tempDir)
    }

    private func precheck() throws {
        let manifest = cwd.appending(component: Manifest.filename)
        guard !swiftCommandState.fileSystem.exists(manifest) else {
            throw InitError.manifestAlreadyExists
        }

        if let dir = templateDirectory, !swiftCommandState.fileSystem.exists(dir) {
            throw ValidationError("The specified template path does not exist: \(dir.pathString)")
        }
    }

    private func inferPackageType(from templatePath: Basics.AbsolutePath) async throws -> InitPackage.PackageType {
        try await swiftCommandState.withTemporaryWorkspace(switchingTo: templatePath) { _, _ in
            let workspace = try swiftCommandState.getActiveWorkspace()
            let root = try swiftCommandState.getWorkspaceRoot()

            let rootManifests = try await workspace.loadRootManifests(
                packages: root.packages,
                observabilityScope: swiftCommandState.observabilityScope
            )

            guard let manifest = rootManifests.values.first else {
                throw InternalError("Invalid manifest in template at \(root.packages)")
            }

            for target in manifest.targets {
                if templateName == nil || target.name == templateName {
                    if let options = target.templateInitializationOptions {
                        if case .packageInit(let type, _, _) = options {
                            return try .init(from: type)
                        }
                    }
                }
            }

            throw ValidationError("Could not find template \(templateName ?? "<unspecified>")")
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
        try swiftCommandState.fileSystem.createDirectory(stagingPath, recursive: true)
        try templatePackage.setupTemplateManifest()
        return templatePackage
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
            throw ValidationError("Specify a package type using the --type option.")
        }
        guard let knownType = InitPackage.PackageType(rawValue: initModeString) else {
            throw ValidationError("Package type \(initModeString) not supported")
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
}

