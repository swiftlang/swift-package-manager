/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCUtility
import TSCBasic
import PackageGraph
import SPMBuildCore
import Build

/// swift-build tool namespace
public class SwiftBuildTool: SwiftTool<BuildToolOptions> {

   public convenience init(args: [String]) {
       self.init(
            toolName: "build",
            usage: "[options]",
            overview: "Build sources into binary products",
            args: args,
            seeAlso: type(of: self).otherToolNames()
        )
    }

    override func runImpl() throws {
        switch try options.mode() {
        case .build:
          #if os(Linux)
            // Emit warning if clang is older than version 3.6 on Linux.
            // See: <rdar://problem/28108951> SR-2299 Swift isn't using Gold by default on stock 14.04.
            checkClangVersion()
          #endif

            guard let subset = options.buildSubset(diagnostics: diagnostics) else { return }
            let buildSystem = try createBuildSystem()
            try buildSystem.build(subset: subset)

        case .binPath:
            try print(buildParameters().buildPath.description)

        case .version:
            print(Versioning.currentVersion.completeDisplayString)
        }
    }

    override class func defineArguments(parser: ArgumentParser, binder: ArgumentBinder<BuildToolOptions>) {
        binder.bind(
            option: parser.add(option: buildTestsOptionName, kind: Bool.self,
                usage: "Build both source and test targets"),
            to: { $0.buildTests = $1 })

        binder.bind(
            option: parser.add(option: productOptionName, kind: String.self,
                usage: "Build the specified product"),
            to: { $0.product = $1 })

        binder.bind(
            option: parser.add(option: targetOptionName, kind: String.self,
                usage: "Build the specified target"),
            to: { $0.target = $1 })

        binder.bind(
            option: parser.add(option: "--show-bin-path", kind: Bool.self,
               usage: "Print the binary output path"),
            to: { $0.shouldPrintBinPath = $1 })
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

public class BuildToolOptions: ToolOptions {
    /// Returns the mode in which the build tool should run.
    func mode() throws -> BuildToolMode {
        if shouldPrintVersion {
            return .version
        }
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

    /// If the test should be built.
    var buildTests = false

    /// If the binary output path should be printed.
    var shouldPrintBinPath = false

    /// Specific target to build.
    var target: String?

    /// Specific product to build.
    var product: String?
}

public enum BuildToolMode {
    /// Build the package.
    case build

    /// Print the binary output path.
    case binPath

    /// Print the version.
    case version
}

fileprivate let buildTestsOptionName = "--build-tests"
fileprivate let productOptionName = "--product"
fileprivate let targetOptionName = "--target"

fileprivate extension BuildSubset {
    var argumentName: String {
        switch self {
        case .allExcludingTests:
            fatalError("no corresponding argument")
        case .allIncludingTests:
            return buildTestsOptionName
        case .product:
            return productOptionName
        case .target:
            return targetOptionName
        }
    }
}

extension SwiftBuildTool: ToolName {
    static var toolName: String {
        return "swift build"
    }
}

extension Diagnostic.Message {
    //FIXME: Can we move this functionality into the argument parser?
    /// Diagnostic error when a command is run with several arguments that are mutually exclusive.
    static func mutuallyExclusiveArgumentsError(arguments: [String]) -> Diagnostic.Message {
        .error(arguments.map{ "'\($0)'" }.spm_localizedJoin(type: .conjunction) + " are mutually exclusive")
    }
}
