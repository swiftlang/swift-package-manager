/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Build
import Get
import PackageLoading
import PackageModel
import Utility

import enum Build.Configuration
import protocol Build.Toolchain

/// swift-build tool namespace
public class SwiftBuildTool: SwiftTool<BuildToolOptions> {

   public convenience init(args: [String]) {
       self.init(
            toolName: "build",
            usage: "[options]",
            overview: "Build sources into binary products",
            args: args
        )
    }

    override func runImpl() throws {
        switch try options.mode() {
        case .build(let conf, let toolchain):
            #if os(Linux)
            // Emit warning if clang is older than version 3.6 on Linux.
            // See: <rdar://problem/28108951> SR-2299 Swift isn't using Gold by default on stock 14.04.
            checkClangVersion()
            #endif
            let graph = try loadPackage()
            // If we don't have any modules in root package, we're done.
            guard !graph.rootPackages[0].modules.isEmpty else { break }
            let yaml = try describe(buildPath, conf, graph, flags: options.buildFlags, toolchain: toolchain)
            try build(yamlPath: yaml, target: options.buildTests ? "test" : nil)

        case .clean:
            print("warning: swift build --clean is deprecated. Use 'swift package clean' instead. (SR-2082)")
            try clean()

        case .version:
            print(Versioning.currentVersion.completeDisplayString)
        }
    }

    override class func defineArguments(parser: ArgumentParser, binder: ArgumentBinder<BuildToolOptions>) {
        binder.bind(
            option: parser.add(option: "--build-tests", kind: Bool.self),
            to: { $0.buildTests = $1 })

        binder.bind(
            option: parser.add(option: "--clean", kind: Bool.self),
            to: { $0.clean = $1 })

        binder.bind(
            option: parser.add(option: "--configuration", shortName: "-c", kind: Build.Configuration.self,
                usage: "Build with configuration (debug|release) [default: debug]"),
            to: { $0.config = $1 })
    }

    private func checkClangVersion() {
        // We only care about this on Ubuntu 14.04
        guard let uname = try? popen(["lsb_release", "-r"]).chomp(),
              uname.hasSuffix("14.04"),
              let clangVersionOutput = try? popen(["clang", "--version"]).chomp(),
              let clang = getClangVersion(versionOutput: clangVersionOutput) else {
            return
        }

        if clang.major <= 3 && clang.minor < 6 {
            print("warning: minimum recommended clang is version 3.6, otherwise you may encounter linker errors.")
        }
    }
}

public class BuildToolOptions: ToolOptions {
    /// Returns the mode in which the build tool should run.
    func mode() throws -> BuildToolMode {
        if printVersion {
            return .version
        }
        if clean {
            return .clean
        }
        // Get the build configuration or assume debug.
        return .build(config, try UserToolchain())
    }

    /// If the test should be built.
    var buildTests = false
    
    /// If should clean the build artefacts.
    var clean = false

    /// Build configuration.
    var config: Build.Configuration = .debug
}

public enum BuildToolMode {
    /// Build using the configuration and toolchain.
    case build(Configuration, Toolchain)

    /// Clean the build artefacts and exit.
    case clean

    /// Print the version.
    case version
}

extension Build.Configuration: StringEnumArgument {}
