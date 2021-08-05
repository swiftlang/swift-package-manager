/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import ArgumentParser
import Basics
import TSCBasic
import SPMBuildCore
import Build
import PackageModel
import PackageLoading
import PackageGraph
import SourceControl
import TSCUtility
import XCBuildSupport
import Workspace
import Foundation
import PackageRegistry

private enum RegistryConfigurationError: Swift.Error {
    case missingScope(String? = nil)
    case invalidURL(String)
}

extension RegistryConfigurationError: CustomStringConvertible {
    var description: String {
        switch self {
        case .missingScope(let scope?):
            return "no existing entry for scope: \(scope)"
        case .missingScope:
            return "no existing entry for default scope"
        case .invalidURL(let url):
            return "invalid URL: \(url)"
        }
    }
}

public struct SwiftPackageRegistryTool: ParsableCommand {
    public static var configuration = CommandConfiguration(
        commandName: "package-registry",
        _superCommandName: "swift",
        abstract: "Perform operations on Swift packages",
        discussion: "SEE ALSO: swift package",
        version: SwiftVersion.currentVersion.completeDisplayString,
        subcommands: [
            Set.self,
            Unset.self
        ],
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)])

    @OptionGroup()
    var swiftOptions: SwiftToolOptions

    public init() {}

    struct Set: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set a custom registry")

        @OptionGroup(_hiddenFromHelp: true)
        var swiftOptions: SwiftToolOptions

        @Flag(help: "Apply settings to all projects for this user")
        var global: Bool = false

        @Option(help: "Associate the registry with a given scope")
        var scope: String?

        // TODO: Uncomment once .netrc management is implemented

        // @Option(help: "Specify a user name for the remote machine")
        // var login: String?

        // @Option(help: "Supply a password for the remote machine")
        // var password: String?

        @Argument(help: "The registry URL")
        var url: String

        func run(_ swiftTool: SwiftTool) throws {
            guard let url = URL(string: url),
                  url.scheme == "https"
            else {
                throw RegistryConfigurationError.invalidURL(url)
            }

            // TODO: Require login if password is specified

            let path = try swiftTool.getRegistryConfigurationPath(fileSystem: localFileSystem, global: global)

            var configuration = RegistryConfiguration()
            if localFileSystem.exists(path) {
                configuration = try RegistryConfiguration.readFromJSONFile(in: localFileSystem, at: path)
            }

            if let scope = scope {
                configuration.scopedRegistries[scope] = .init(url: url)
            } else {
                configuration.defaultRegistry = .init(url: url)
            }

            try configuration.writeToJSONFile(in: localFileSystem, at: path)

            // TODO: Add login and password to .netrc
        }
    }

    struct Unset: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove a configured registry")

        @OptionGroup(_hiddenFromHelp: true)
        var swiftOptions: SwiftToolOptions

        @Flag(help: "Apply settings to all projects for this user")
        var global: Bool = false

        @Option(help: "Associate the registry with a given scope")
        var scope: String?

        func run(_ swiftTool: SwiftTool) throws {
            let path = try swiftTool.getRegistryConfigurationPath(fileSystem: localFileSystem, global: global)
            var configuration = try RegistryConfiguration.readFromJSONFile(in: localFileSystem, at: path)

            if let scope = scope {
                guard let _ = configuration.scopedRegistries[scope] else {
                    throw RegistryConfigurationError.missingScope(scope)
                }
                configuration.scopedRegistries.removeValue(forKey: scope)
            } else {
                guard let _ = configuration.defaultRegistry else {
                    throw RegistryConfigurationError.missingScope()
                }
                configuration.defaultRegistry = nil
            }

            try configuration.writeToJSONFile(in: localFileSystem, at: path)
        }
    }
}

// MARK: -

private extension Decodable {
    static func readFromJSONFile(in fileSystem: FileSystem, at path: AbsolutePath) throws -> Self {
        let content = try fileSystem.readFileContents(path)

        let decoder = JSONDecoder()

        return try decoder.decode(Self.self, from: Data(content.contents))
    }
}

private extension Encodable {
    func writeToJSONFile(in fileSystem: FileSystem, at path: AbsolutePath) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]

        let data = try encoder.encode(self)

        try fileSystem.writeFileContents(path, bytes: ByteString(data), atomically: true)
    }
}

private extension SwiftTool {
    func getRegistryConfigurationPath(fileSystem: FileSystem = localFileSystem, global: Bool) throws -> AbsolutePath {
        let filename = "registries.json"
        if global {
            return try fileSystem.getOrCreateSwiftPMConfigDirectory().appending(component: filename)
        } else {
            let directory = try configFilePath()
            if !fileSystem.exists(directory) {
                try fileSystem.createDirectory(directory, recursive: true)
            }

            return directory.appending(component: filename)
        }
    }
}
