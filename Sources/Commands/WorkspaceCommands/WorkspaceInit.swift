//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import CoreCommands
import Workspace

extension SwiftWorkspaceCommand {

    /// Scaffold a new SwiftPM workspace at the current working
    /// directory: writes `Workspace.swift` and, for each declared
    /// member, creates its directory and `Package.swift` unless one
    /// already exists.
    struct Init: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "init",
            abstract: "Initialize a new SwiftPM workspace.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Option(
            name: .customLong("members"),
            parsing: .upToNextOption,
            help: "Space-separated list of member paths, each optionally suffixed with ':<type>' (defaults to 'library').",
        )
        var members: [String] = []

        // This command supports creating the supplied `--package-path` if it isn't created.
        var createPackagePath = true

        func run(_ swiftCommandState: SwiftCommandState) throws {
            guard let cwd = swiftCommandState.fileSystem.currentWorkingDirectory else {
                throw InternalError("Could not find the current working directory")
            }
            let parsedMembers = try self.members.map(Self.parseMember)
            let init_ = InitWorkspace(
                fileSystem: swiftCommandState.fileSystem,
                destinationPath: cwd,
                options: .init(members: parsedMembers),
                progressReporter: { message in print(message) },
            )
            try init_.write()
        }

        /// Parses a `--members` token of the form `path` or
        /// `path:type` — where `type` matches one of the `InitPackage`
        /// package types (`library`, `executable`, `empty`, etc.). Bare
        /// `path` defaults to `library`.
        static func parseMember(_ token: String) throws -> InitWorkspace.Member {
            let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
            let path = parts[0]
            guard parts.count == 2 else {
                return .init(path: path, packageType: .library)
            }
            let typeString = parts[1]
            guard let type = InitPackage.PackageType(rawValue: typeString) else {
                throw WorkspaceInitParseError.unknownMemberType(
                    token: token,
                    typeString: typeString,
                    supportedTypes: InitPackage.PackageType.allCases.map { $0.rawValue },
                )
            }
            return .init(path: path, packageType: type)
        }
    }
}

/// Errors raised while parsing arguments to `swift workspace init`.
enum WorkspaceInitParseError: Error, CustomStringConvertible {
    /// The `:type` suffix of a `--members` token did not match any
    /// known `InitPackage.PackageType` raw value.
    case unknownMemberType(token: String, typeString: String, supportedTypes: [String])

    var description: String {
        switch self {
        case .unknownMemberType(let token, let typeString, let supportedTypes):
            return "unknown member type '\(typeString)' in '--members \(token)'; expected one of: \(supportedTypes.joined(separator: ", "))"
        }
    }
}
