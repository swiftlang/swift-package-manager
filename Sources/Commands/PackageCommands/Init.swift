//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics

@_spi(SwiftPMInternal)
import CoreCommands

import PackageModel
import Workspace
import SPMBuildCore

extension SwiftPackageCommand {
    struct Init: SwiftCommand {
        public static let configuration = CommandConfiguration(
            abstract: "Initialize a new package")

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions
        
        @Option(
            name: .customLong("type"),
            help: ArgumentHelp("Package type:", discussion: """
                library           - A package with a library.
                executable        - A package with an executable.
                tool              - A package with an executable that uses
                                    Swift Argument Parser. Use this template if you
                                    plan to have a rich set of command-line arguments.
                build-tool-plugin - A package that vends a build tool plugin.
                command-plugin    - A package that vends a command plugin.
                macro             - A package that vends a macro.
                empty             - An empty package with a Package.swift manifest.
                """))
        var initMode: InitPackage.PackageType = .library

        /// Which testing libraries to use (and any related options.)
        @OptionGroup()
        var testLibraryOptions: TestLibraryOptions

        @Option(name: .customLong("name"), help: "Provide custom package name")
        var packageName: String?

        // This command should support creating the supplied --package-path if it isn't created.
        var createPackagePath = true

        func run(_ swiftCommandState: SwiftCommandState) throws {
            guard let cwd = swiftCommandState.fileSystem.currentWorkingDirectory else {
                throw InternalError("Could not find the current working directory")
            }

            let packageName = self.packageName ?? cwd.basename

            // Testing is on by default, with XCTest only enabled explicitly.
            // For macros this is reversed, since we don't support testing
            // macros with Swift Testing yet.
            var supportedTestingLibraries = Set<TestingLibrary>()
            if testLibraryOptions.isExplicitlyEnabled(.xctest, swiftCommandState: swiftCommandState) ||
                (initMode == .macro && testLibraryOptions.isEnabled(.xctest, swiftCommandState: swiftCommandState)) {
                supportedTestingLibraries.insert(.xctest)
            }
            if testLibraryOptions.isExplicitlyEnabled(.swiftTesting, swiftCommandState: swiftCommandState) ||
                (initMode != .macro && testLibraryOptions.isEnabled(.swiftTesting, swiftCommandState: swiftCommandState)) {
                supportedTestingLibraries.insert(.swiftTesting)
            }

            let initPackage = try InitPackage(
                name: packageName,
                packageType: initMode,
                supportedTestingLibraries: supportedTestingLibraries,
                destinationPath: cwd,
                installedSwiftPMConfiguration: swiftCommandState.getHostToolchain().installedSwiftPMConfiguration,
                fileSystem: swiftCommandState.fileSystem
            )
            initPackage.progressReporter = { message in
                print(message)
            }
            try initPackage.writePackageStructure()
        }
    }
}

extension InitPackage.PackageType: ExpressibleByArgument {}
