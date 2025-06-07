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
import ArgumentParserToolInfo

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

    
    public func promptUser(tool: ToolInfoV0) throws -> [String] {
        let arguments = try convertArguments(from: tool.command)

        let responses = UserPrompter.prompt(for: arguments)

        let commandLine = buildCommandLine(from: responses)

        return commandLine
    }

    private func convertArguments(from command: CommandInfoV0) throws -> [ArgumentInfoV0] {
        guard let rawArgs = command.arguments else {
            throw TemplateError.noArguments
        }
        return rawArgs
    }


    private struct UserPrompter {

        static func prompt(for arguments: [ArgumentInfoV0]) -> [ArgumentResponse] {
            return arguments
                .filter { $0.valueName != "help" }
                .map { arg in
                    let defaultText = arg.defaultValue.map { " (default: \($0))" } ?? ""
                    let promptMessage = "\(arg.abstract ?? "")\(defaultText):"

                    var values: [String] = []

                    switch arg.kind {
                    case .flag:
                        let confirmed = promptForConfirmation(prompt: promptMessage,
                                                              defaultBehavior: arg.defaultValue?.lowercased() == "true")
                        values = [confirmed ? "true" : "false"]

                    case .option, .positional:
                        print(promptMessage)

                        if arg.isRepeating {
                            while let input = readLine(), !input.isEmpty {
                                values.append(input)
                            }
                            if values.isEmpty, let def = arg.defaultValue {
                                values = [def]
                            }
                        } else {
                            let input = readLine()
                            if let input = input, !input.isEmpty {
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
    func buildCommandLine(from responses: [ArgumentResponse]) -> [String] {
        return responses.flatMap(\.commandLineFragments)
    }



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

    struct ArgumentResponse {
        let argument: ArgumentInfoV0
        let values: [String]

        var commandLineFragments: [String] {
            guard let name = argument.valueName else {
                return values
            }

            switch argument.kind {
            case .flag:
                return values.first == "true" ? ["--\(name)"] : []
            case .option:
                return values.flatMap { ["--\(name)", $0] }
            case .positional:
                return values
            }
        }
    }
}


private enum TemplateError: Swift.Error {
    case invalidPath
    case manifestAlreadyExists
    case noArguments
}


extension TemplateError: CustomStringConvertible {
    var description: String {
        switch self {
        case .manifestAlreadyExists:
            return "a manifest file already exists in this directory"
        case .invalidPath:
            return "Path does not exist, or is invalid."
        case .noArguments:
            return "Template has no arguments"
        }
    }
}


