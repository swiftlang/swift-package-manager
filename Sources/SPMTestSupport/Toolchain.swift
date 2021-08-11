/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import PackageModel
import Workspace
import TSCBasic

#if os(macOS)
private func macOSBundleRoot() -> AbsolutePath {
    for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
        return AbsolutePath(bundle.bundlePath).parentDirectory
    }
    fatalError()
}
#endif

private func resolveBinDir() -> AbsolutePath {
#if os(macOS)
    return macOSBundleRoot()
#else
    return AbsolutePath(CommandLine.arguments[0], relativeTo: localFileSystem.currentWorkingDirectory!).parentDirectory
#endif
}

extension ToolchainConfiguration {
    public static var `default`: Self {
        get {
            let toolchain = UserToolchain.default
            return .init(
                swiftCompiler: toolchain.configuration.swiftCompiler,
                swiftCompilerFlags: [],
                libDir: toolchain.configuration.libDir,
                binDir: toolchain.configuration.binDir
            )
        }
    }

#if os(macOS)
    public var sdkPlatformFrameworksPath: AbsolutePath {
        return Destination.sdkPlatformFrameworkPaths()!.fwk
    }
#endif

}

extension UserToolchain {
    public static var `default`: Self {
        get {
            let binDir = resolveBinDir()
            return try! .init(destination: Destination.hostDestination(binDir))
        }
    }
}
