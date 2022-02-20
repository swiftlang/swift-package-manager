/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import ArgumentParser
import Basics
import Build
import PackageGraph
import SPMBuildCore
import TSCBasic

import enum TSCUtility.Diagnostics
import func TSCUtility.getClangVersion
import struct TSCUtility.Version

extension BuildSubset {
    var argumentName: String {
        switch self {
        case .allExcludingTests:
            fatalError("no corresponding argument")
        case .allIncludingTests:
            return "--build-tests"
        case .product:
            return "--product"
        case .target:
            return "--target"
        }
    }
}

struct BuildToolOptions: ParsableArguments {
    /// Returns the build subset specified with the options.
    func buildSubset(observabilityScope: ObservabilityScope) -> BuildSubset? {
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
            observabilityScope.emit(.mutuallyExclusiveArgumentsError(arguments: allSubsets.map{ $0.argumentName }))
            return nil
        }

        return allSubsets.first ?? .allExcludingTests
    }

    /// If the test should be built.
    @Flag(help: "Build both source and test targets")
    var buildTests: Bool = false

    /// If the binary output path should be printed.
    @Flag(name: .customLong("show-bin-path"), help: "Print the binary output path")
    var shouldPrintBinPath: Bool = false

    /// Specific target to build.
    @Option(help: "Build the specified target")
    var target: String?

    /// Specific product to build.
    @Option(help: "Build the specified product")
    var product: String?
}

/// swift-build tool namespace
public struct SwiftBuildTool: SwiftCommand {
    public static var configuration = CommandConfiguration(
        commandName: "build",
        _superCommandName: "swift",
        abstract: "Build sources into binary products",
        discussion: "SEE ALSO: swift run, swift package, swift test",
        version: SwiftVersion.currentVersion.completeDisplayString,
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)])

    @OptionGroup(_hiddenFromHelp: true)
    var swiftOptions: SwiftToolOptions

    @OptionGroup()
    var options: BuildToolOptions

    public func run(_ swiftTool: SwiftTool) throws {
        if options.shouldPrintBinPath {
            try print(swiftTool.buildParameters().buildPath.description)
            return
        }

        #if os(Linux)
        // Emit warning if clang is older than version 3.6 on Linux.
        // See: <rdar://problem/28108951> SR-2299 Swift isn't using Gold by default on stock 14.04.
        checkClangVersion(observabilityScope: swiftTool.observabilityScope)
        #endif

        guard let subset = options.buildSubset(observabilityScope: swiftTool.observabilityScope) else {
            throw ExitCode.failure
        }
        let buildSystem = try swiftTool.createBuildSystem(
            explicitProduct: options.product,
            // command result output goes on stdout
            // ie "swift build" should output to stdout
            customOutputStream: TSCBasic.stdoutStream
        )
        do {
            try buildSystem.build(subset: subset)
        } catch _ as Diagnostics {
            throw ExitCode.failure
        }
    }

    private func checkClangVersion(observabilityScope: ObservabilityScope) {
        // We only care about this on Ubuntu 14.04
        guard let uname = try? Process.checkNonZeroExit(args: "lsb_release", "-r").spm_chomp(),
              uname.hasSuffix("14.04"),
              let clangVersionOutput = try? Process.checkNonZeroExit(args: "clang", "--version").spm_chomp(),
              let clang = getClangVersion(versionOutput: clangVersionOutput) else {
            return
        }

        if clang < Version(3, 6, 0) {
            observabilityScope.emit(warning: "minimum recommended clang is version 3.6, otherwise you may encounter linker errors.")
        }
    }

    public init() {}
}

extension Basics.Diagnostic {
    static func mutuallyExclusiveArgumentsError(arguments: [String]) -> Self {
        .error(arguments.map{ "'\($0)'" }.spm_localizedJoin(type: .conjunction) + " are mutually exclusive")
    }
}
