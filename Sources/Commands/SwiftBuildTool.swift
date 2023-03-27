//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import Build
import CoreCommands
import PackageGraph
import SPMBuildCore
import TSCBasic
import XCBuildSupport

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

        if let product {
            allSubsets.append(.product(product))
        }

        if let target {
            allSubsets.append(.target(target))
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

    /// Whether to output a graphviz file visualization of the combined job graph for all targets
    @Flag(name: .customLong("print-manifest-job-graph"),
          help: "Write the command graph for the build manifest as a graphviz file")
    var printManifestGraphviz: Bool = false

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
        version: SwiftVersion.current.completeDisplayString,
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)])

    @OptionGroup()
    public var globalOptions: GlobalOptions

    @OptionGroup()
    var options: BuildToolOptions

    public func run(_ swiftTool: SwiftTool) throws {
        if options.shouldPrintBinPath {
            return try print(swiftTool.buildParameters().buildPath.description)
        }

        if options.printManifestGraphviz {
            // FIXME: Doesn't seem ideal that we need an explicit build operation, but this concretely uses the `LLBuildManifest`.
            guard let buildOperation = try swiftTool.createBuildSystem(explicitBuildSystem: .native) as? BuildOperation else {
                throw StringError("asked for native build system but did not get it")
            }
            let buildManifest = try buildOperation.getBuildManifest()
            var serializer = DOTManifestSerializer(manifest: buildManifest)
            // print to stdout
            let outputStream = stdoutStream
            serializer.writeDOT(to: outputStream)
            outputStream.flush()
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
        guard let uname = try? TSCBasic.Process.checkNonZeroExit(args: "lsb_release", "-r").spm_chomp(),
              uname.hasSuffix("14.04"),
              let clangVersionOutput = try? TSCBasic.Process.checkNonZeroExit(args: "clang", "--version").spm_chomp(),
              let clang = getClangVersion(versionOutput: clangVersionOutput) else {
            return
        }

        if clang < Version(3, 6, 0) {
            observabilityScope.emit(warning: "minimum recommended clang is version 3.6, otherwise you may encounter linker errors.")
        }
    }

    public init() {}
}

public extension _SwiftCommand {
    func buildSystemProvider(_ swiftTool: SwiftTool) throws -> BuildSystemProvider {
        return try swiftTool.defaultBuildSystemProvider
    }
}
