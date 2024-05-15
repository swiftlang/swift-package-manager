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
import CoreCommands
import PackageLoading
import PackageModel
import Workspace

// This is named as `ToolsVersionCommand` instead of `ToolsVersion` to avoid naming conflicts, as the latter already
// exists to denote the version itself.
struct ToolsVersionCommand: SwiftCommand {
    static let configuration = CommandConfiguration(
        commandName: "tools-version",
        abstract: "Manipulate tools version of the current package")

    @OptionGroup(visibility: .hidden)
    var globalOptions: GlobalOptions

    @Flag(help: "Set tools version of package to the current tools version in use")
    var setCurrent: Bool = false

    @Option(help: "Set tools version of package to the given value")
    var set: String?

    enum ToolsVersionMode {
        case display
        case set(String)
        case setCurrent
    }

    var toolsVersionMode: ToolsVersionMode {
        // TODO: enforce exclusivity
        if let set {
            return .set(set)
        } else if setCurrent {
            return .setCurrent
        } else {
            return .display
        }
    }

    func run(_ swiftCommandState: SwiftCommandState) throws {
        let pkg = try swiftCommandState.getPackageRoot()

        switch toolsVersionMode {
        case .display:
            let manifestPath = try ManifestLoader.findManifest(packagePath: pkg, fileSystem: swiftCommandState.fileSystem, currentToolsVersion: .current)
            let version = try ToolsVersionParser.parse(manifestPath: manifestPath, fileSystem: swiftCommandState.fileSystem)
            print("\(version)")

        case .set(let value):
            guard let toolsVersion = ToolsVersion(string: value) else {
                // FIXME: Probably lift this error definition to ToolsVersion.
                throw ToolsVersionParser.Error.malformedToolsVersionSpecification(.versionSpecifier(.isMisspelt(value)))
            }
            try ToolsVersionSpecificationWriter.rewriteSpecification(
                manifestDirectory: pkg,
                toolsVersion: toolsVersion,
                fileSystem: swiftCommandState.fileSystem
            )

        case .setCurrent:
            // Write the tools version with current version but with patch set to zero.
            // We do this to avoid adding unnecessary constraints to patch versions, if
            // the package really needs it, they can do it using --set option.
            try ToolsVersionSpecificationWriter.rewriteSpecification(
                manifestDirectory: pkg,
                toolsVersion: ToolsVersion.current.zeroedPatch,
                fileSystem: swiftCommandState.fileSystem
            )
        }
    }
}
