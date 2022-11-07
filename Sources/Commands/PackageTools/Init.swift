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
import Workspace

extension SwiftPackageTool {
    struct Init: SwiftCommand {
        public static let configuration = CommandConfiguration(
            abstract: "Initialize a new package")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions
        
        @Option(
            name: .customLong("type"),
            help: ArgumentHelp("Package type: empty | library | executable | system-module | manifest", discussion: """
                empty - Create an empty package
                library - Create a package that contains a library
                executable - Create a package that contains a binary executable
                system-module - Create a package that contains a system module
                manifest - Create a Package.swift file
                """))
        var initMode: InitPackage.PackageType = .library

        @Option(name: .customLong("name"), help: "Provide custom package name")
        var packageName: String?

        func run(_ swiftTool: SwiftTool) throws {
            guard let cwd = swiftTool.fileSystem.currentWorkingDirectory else {
                throw InternalError("Could not find the current working directory")
            }

            let packageName = self.packageName ?? cwd.basename
            let initPackage = try InitPackage(
                name: packageName,
                packageType: initMode,
                destinationPath: cwd,
                fileSystem: swiftTool.fileSystem
            )
            initPackage.progressReporter = { message in
                print(message)
            }
            try initPackage.writePackageStructure()
        }
    }
}

extension InitPackage.PackageType: ExpressibleByArgument {}
