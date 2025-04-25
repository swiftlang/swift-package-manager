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

import Foundation

import struct Basics.AbsolutePath
import let Basics.localFileSystem
import enum Basics.Sandbox
import struct Basics.SourceControlURL

#if canImport(SwiftBuild)

import enum SwiftBuild.ProjectModel

extension PackagePIFBuilder {
    /// Contains all of the information resulting from applying a build tool plugin to a package target thats affect how
    /// a target is built.
    ///
    /// This includes any commands that should be incorporated into the build graph and all derived source files that
    /// should be compiled
    /// (i.e., those from prebuild commands as well as from the build commands).
    public struct BuildToolPluginInvocationResult: Equatable {
        /// Absolute paths of output files of any prebuild commands.
        public let prebuildCommandOutputPaths: [AbsolutePath]

        /// Build commands to incorporate into the dependency graph.
        public let buildCommands: [CustomBuildCommand]

        /// Absolute paths of all derived source files that should be compiled as sources of the target.
        /// This includes the outputs of any prebuild commands as well as all the outputs referenced in all the build
        /// commands.
        public var allDerivedOutputPaths: [AbsolutePath] {
            self.prebuildCommandOutputPaths + self.buildCommands.flatMap(\.absoluteOutputPaths)
        }

        public init(
            prebuildCommandOutputPaths: [AbsolutePath],
            buildCommands: [CustomBuildCommand]
        ) {
            self.prebuildCommandOutputPaths = prebuildCommandOutputPaths
            self.buildCommands = buildCommands
        }
    }

    /// A command provided by a build tool plugin.
    /// Build tool plugins are evaluated after package graph resolution (and subsequently, when conditions change).
    ///
    /// There are *two* basic kinds of build tool commands: prebuild commands and regular build commands.
    public struct CustomBuildCommand: Equatable {
        public var displayName: String?
        public var executable: String
        public var arguments: [String]
        public var environment: [String: String]
        public var workingDir: AbsolutePath?
        public var inputPaths: [AbsolutePath] = []

        /// Output paths can contain references with un-resolved paths (e.g. "$(DERIVED_FILE_DIR)/myOutput.txt")
        public var outputPaths: [String] = []
        public var absoluteOutputPaths: [AbsolutePath] {
            self.outputPaths.compactMap { try? AbsolutePath(validating: $0) }
        }

        public var sandboxProfile: SandboxProfile? = nil

        public init(
            displayName: String?,
            executable: String,
            arguments: [String],
            environment: [String: String],
            workingDir: AbsolutePath?,
            inputPaths: [AbsolutePath],
            outputPaths: [String],
            sandboxProfile: SandboxProfile?
        ) {
            self.displayName = displayName
            self.executable = executable
            self.arguments = arguments
            self.environment = environment
            self.workingDir = workingDir
            self.inputPaths = inputPaths
            self.outputPaths = outputPaths
            self.sandboxProfile = sandboxProfile
        }
    }

    /// Represents a libSwiftPM sandbox profile that can be applied to a given command line.
    public struct SandboxProfile: Equatable {
        public var strictness: Sandbox.Strictness
        public var writableDirectories: [AbsolutePath]
        public var readOnlyDirectories: [AbsolutePath]

        public init(
            strictness: Sandbox.Strictness,
            writableDirectories: [AbsolutePath],
            readOnlyDirectories: [AbsolutePath]
        ) {
            self.strictness = strictness
            self.writableDirectories = writableDirectories
            self.readOnlyDirectories = readOnlyDirectories
        }

        init(writableDirectories: [AbsolutePath] = [], readOnlyDirectories: [AbsolutePath] = []) {
            self.strictness = .writableTemporaryDirectory
            self.writableDirectories = writableDirectories
            self.readOnlyDirectories = readOnlyDirectories
        }

        public var writableDirectoryPathStrings: [String] {
            self.writableDirectories.map(\.pathString)
        }

        public var readOnlyDirectoryPathStrings: [String] {
            self.readOnlyDirectories.map(\.pathString)
        }

        /// Applies the sandbox profile to the given command line, and return the modified command line.
        public func apply(to command: [String]) throws -> [String] {
            try Sandbox.apply(
                command: command,
                fileSystem: localFileSystem,
                strictness: self.strictness,
                writableDirectories: self.writableDirectories,
                readOnlyDirectories: self.readOnlyDirectories
            )
        }
    }
}

#endif
