//
//  InitTemplatePackage.swift
//  SwiftPM
//
//  Created by John Bute on 2025-05-13.
//

import ArgumentParserToolInfo
import Basics
import Foundation
import PackageModel
import PackageModelSyntax
import SPMBuildCore
import SwiftParser
import System
import TSCBasic
import TSCUtility

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

public final class InitTemplatePackage {
    /// The kind of package dependency to add for the template.
    let packageDependency: MappablePackageDependency.Kind
    /// The set of testing libraries supported by the generated package.
    public var supportedTestingLibraries: Set<TestingLibrary>

    /// The name of the template to use.
    let templateName: String
    /// The file system abstraction to use for file operations.
    let fileSystem: FileSystem

    /// The absolute path where the package will be created.
    let destinationPath: Basics.AbsolutePath

    /// Configuration information from the installed Swift Package Manager toolchain.
    let installedSwiftPMConfiguration: InstalledSwiftPMConfiguration
    /// The name of the package to create.

    var packageName: String

    /// The path to the template files.

    var templatePath: Basics.AbsolutePath
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
    public init(
        name: String,
        templateName: String,
        initMode: MappablePackageDependency.Kind,
        templatePath: Basics.AbsolutePath,
        fileSystem: FileSystem,
        packageType: InitPackage.PackageType,
        supportedTestingLibraries: Set<TestingLibrary>,
        destinationPath: Basics.AbsolutePath,
        installedSwiftPMConfiguration: InstalledSwiftPMConfiguration,
    ) {
        self.packageName = name
        self.packageDependency = initMode
        self.templatePath = templatePath
        self.packageType = packageType
        self.supportedTestingLibraries = supportedTestingLibraries
        self.destinationPath = destinationPath
        self.installedSwiftPMConfiguration = installedSwiftPMConfiguration
        self.fileSystem = fileSystem
        self.templateName = templateName
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

        let editResult = try AddPackageDependency.addPackageDependency(
            self.packageDependency, to: manifestSyntax
        )

        try editResult.applyEdits(
            to: self.fileSystem,
            manifest: manifestSyntax,
            manifestPath: manifestPath,
            verbose: false
        )
    }

    /// Prompts the user for input based on the given tool information.
    ///
    /// This method converts the command arguments of the tool into prompt questions,
    /// collects user input, and builds a command line argument array from the responses.
    ///
    /// - Parameter tool: The tool information containing command and argument metadata.
    /// - Returns: An array of strings representing the command line arguments built from user input.
    /// - Throws: `TemplateError.noArguments` if the tool command has no arguments.

    public func promptUser(tool: ToolInfoV0) throws -> [String] {
        let arguments = try convertArguments(from: tool.command)

        let responses = UserPrompter.prompt(for: arguments)

        let commandLine = self.buildCommandLine(from: responses)

        return commandLine
    }

    /// Converts the command information into an array of argument metadata.
    ///
    /// - Parameter command: The command info object.
    /// - Returns: An array of argument info objects.
    /// - Throws: `TemplateError.noArguments` if the command has no arguments.

    private func convertArguments(from command: CommandInfoV0) throws -> [ArgumentInfoV0] {
        guard let rawArgs = command.arguments else {
            throw TemplateError.noArguments
        }
        return rawArgs
    }

    /// A helper struct to prompt the user for input values for command arguments.

    private enum UserPrompter {
        /// Prompts the user for input for each argument, handling flags, options, and positional arguments.
        ///
        /// - Parameter arguments: The list of argument metadata to prompt for.
        /// - Returns: An array of `ArgumentResponse` representing the user's input.

        static func prompt(for arguments: [ArgumentInfoV0]) -> [ArgumentResponse] {
            arguments
                .filter { $0.valueName != "help" && $0.shouldDisplay != false }
                .map { arg in
                    let defaultText = arg.defaultValue.map { " (default: \($0))" } ?? ""
                    let allValuesText = (arg.allValues?.isEmpty == false) ?
                        " [\(arg.allValues!.joined(separator: ", "))]" : ""
                    let promptMessage = "\(arg.abstract ?? "")\(allValuesText)\(defaultText):"

                    var values: [String] = []

                    switch arg.kind {
                    case .flag:
                        let confirmed = promptForConfirmation(
                            prompt: promptMessage,
                            defaultBehavior: arg.defaultValue?.lowercased() == "true"
                        )
                        values = [confirmed ? "true" : "false"]

                    case .option, .positional:
                        print(promptMessage)

                        if arg.isRepeating {
                            while let input = readLine(), !input.isEmpty {
                                if let allowed = arg.allValues, !allowed.contains(input) {
                                    print(
                                        "Invalid value '\(input)'. Allowed values: \(allowed.joined(separator: ", "))"
                                    )
                                    continue
                                }
                                values.append(input)
                            }
                            if values.isEmpty, let def = arg.defaultValue {
                                values = [def]
                            }
                        } else {
                            let input = readLine()
                            if let input, !input.isEmpty {
                                if let allowed = arg.allValues, !allowed.contains(input) {
                                    print(
                                        "Invalid value '\(input)'. Allowed values: \(allowed.joined(separator: ", "))"
                                    )
                                    exit(1)
                                }
                                values = [input]
                            } else if let def = arg.defaultValue {
                                values = [def]
                            } else if arg.isOptional == false {
                                fatalError("Required argument '\(arg.valueName)' not provided.")
                            }
                        }
                    }

                    return ArgumentResponse(argument: arg, values: values)
                }
        }
    }

    /// Builds an array of command line argument strings from the given argument responses.
    ///
    /// - Parameter responses: The array of argument responses containing user inputs.
    /// - Returns: An array of strings representing the command line arguments.

    func buildCommandLine(from responses: [ArgumentResponse]) -> [String] {
        responses.flatMap(\.commandLineFragments)
    }

    /// Prompts the user for a yes/no confirmation.
    ///
    /// - Parameters:
    ///   - prompt: The prompt message to display.
    ///   - defaultBehavior: The default value if the user provides no input.
    /// - Returns: `true` if the user confirmed, otherwise `false`.

    private static func promptForConfirmation(prompt: String, defaultBehavior: Bool?) -> Bool {
        let suffix = defaultBehavior == true ? " [Y/n]" : defaultBehavior == false ? " [y/N]" : " [y/n]"
        print(prompt + suffix, terminator: " ")
        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return defaultBehavior ?? false
        }

        switch input {
        case "y", "yes": return true
        case "n", "no": return false
        default: return defaultBehavior ?? false
        }
    }

    /// Represents a user's response to an argument prompt.

    struct ArgumentResponse {
        /// The argument metadata.

        let argument: ArgumentInfoV0
        /// The values provided by the user.

        let values: [String]
        /// Returns the command line fragments representing this argument and its values.

        var commandLineFragments: [String] {
            guard let name = argument.valueName else {
                return self.values
            }

            switch self.argument.kind {
            case .flag:
                return self.values.first == "true" ? ["--\(name)"] : []
            case .option:
                return self.values.flatMap { ["--\(name)", $0] }
            case .positional:
                return self.values
            }
        }
    }
}

/// An error enum representing various template-related errors.
private enum TemplateError: Swift.Error {
    /// The provided path is invalid or does not exist.
    case invalidPath

    /// A manifest file already exists in the target directory.
    case manifestAlreadyExists

    /// The template has no arguments to prompt for.
    case noArguments
}

extension TemplateError: CustomStringConvertible {
    /// A readable description of the error
    var description: String {
        switch self {
        case .manifestAlreadyExists:
            "a manifest file already exists in this directory"
        case .invalidPath:
            "Path does not exist, or is invalid."
        case .noArguments:
            "Template has no arguments"
        }
    }
}
