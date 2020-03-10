/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import ArgumentParser
import TSCUtility
import TSCBasic
import PackageGraph
import SPMBuildCore
import Build

public struct BuildToolOptions: ParsableArguments {
    enum BuildToolMode {
        /// Build the package.
        case build

        /// Print the binary output path.
        case binPath
    }
    
    /// Returns the mode in which the build tool should run.
    func mode() throws -> BuildToolMode {
        if shouldPrintBinPath {
            return .binPath
        }
        // Get the build configuration or assume debug.
        return .build
    }

    /// Returns the build subset specified with the options.
    func buildSubset(diagnostics: DiagnosticsEngine) -> BuildSubset? {
        var allSubsets: [BuildSubset] = []

        if let productName = product {
            allSubsets.append(.product(productName))
        }

        if let targetName = target {
            allSubsets.append(.target(targetName))
        }

        if buildTests {
            allSubsets.append(.allIncludingTests)
        }

        guard allSubsets.count < 2 else {
            diagnostics.emit(.mutuallyExclusiveArgumentsError(arguments: allSubsets.map{ $0.argumentName }))
            return nil
        }

        return allSubsets.first ?? .allExcludingTests
    }

    @OptionGroup()
    var swiftOptions: SwiftToolOptions
    
    /// If the test should be built.
    @Flag(help: "Build both source and test targets")
    var buildTests: Bool

    /// If the binary output path should be printed.
    @Flag(name: .customLong("show-bin-path"), help: "Print the binary output path")
    var shouldPrintBinPath: Bool

    /// Specific target to build.
    @Option(help: "Build the specified target")
    var target: String?

    /// Specific product to build.
    @Option(help: "Build the specified product)
    var product: String?
}

/// swift-build tool namespace
public class SwiftBuildTool: SwiftTool<BuildToolOptions> {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build sources into binary products")

    @OptionGroup()
    var options: BuildToolOptions

    func runImpl() throws {
        let swiftTool = try SwiftTool(options: options.swiftOptions)

        switch try options.mode() {
        case .build:
          #if os(Linux)
            // Emit warning if clang is older than version 3.6 on Linux.
            // See: <rdar://problem/28108951> SR-2299 Swift isn't using Gold by default on stock 14.04.
            checkClangVersion()
          #endif

            guard let subset = options.buildSubset(diagnostics: diagnostics) else { return }
            let buildSystem = try swiftTool.createBuildSystem()
            try buildSystem.build(subset: subset)

        case .binPath:
            try print(swiftTool.buildParameters().buildPath.description)
        }
    }

    private func checkClangVersion() {
        // We only care about this on Ubuntu 14.04
        guard let uname = try? Process.checkNonZeroExit(args: "lsb_release", "-r").spm_chomp(),
              uname.hasSuffix("14.04"),
              let clangVersionOutput = try? Process.checkNonZeroExit(args: "clang", "--version").spm_chomp(),
              let clang = getClangVersion(versionOutput: clangVersionOutput) else {
            return
        }

        if clang < Version(3, 6, 0) {
            print("warning: minimum recommended clang is version 3.6, otherwise you may encounter linker errors.")
        }
    }
}

extension Diagnostic.Message {
    //FIXME: Can we move this functionality into the argument parser?
    /// Diagnostic error when a command is run with several arguments that are mutually exclusive.
    static func mutuallyExclusiveArgumentsError(arguments: [String]) -> Diagnostic.Message {
        .error(arguments.map{ "'\($0)'" }.spm_localizedJoin(type: .conjunction) + " are mutually exclusive")
    }
}
