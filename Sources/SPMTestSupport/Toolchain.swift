//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

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

extension UserToolchain {

#if os(macOS)
    public var sdkPlatformFrameworksPath: AbsolutePath {
        return Destination.sdkPlatformFrameworkPaths()!.fwk
    }
#endif

}

extension Destination {
    public static var `default`: Self {
        get {
            let binDir = resolveBinDir()
            return try! Destination.hostDestination(binDir)
        }
    }
}

extension UserToolchain {
    public static var `default`: Self {
        get {
            return try! .init(destination: Destination.default)
        }
    }
}

extension UserToolchain {
    /// Helper function to determine if async await actually works in the current environment.
    public func supportsSwiftConcurrency() -> Bool {
      #if os(macOS)
        if #available(macOS 12.0, *) {
            // On macOS 12 and later, concurrency is assumed to work.
            return true
        }
        else {
            // On macOS 11 and earlier, we don't know if concurrency actually works because not all SDKs and toolchains have the right bits.  We could examine the SDK and the various libraries, but the most accurate test is to just try to compile and run a snippet of code that requires async/await support.  It doesn't have to actually do anything, it's enough that all the libraries can be found (but because the library reference is weak we do need the linkage reference to `_swift_task_create` and the like).
            do {
                try testWithTemporaryDirectory { tmpPath in
                    let inputPath = tmpPath.appending(component: "foo.swift")
                    try localFileSystem.writeFileContents(inputPath, string: "public func foo() async {}\nTask { await foo() }")
                    let outputPath = tmpPath.appending(component: "foo")
                    let toolchainPath = self.swiftCompilerPath.parentDirectory.parentDirectory
                    let backDeploymentLibPath = toolchainPath.appending(components: "lib", "swift-5.5", "macosx")
                    try Process.checkNonZeroExit(arguments: ["/usr/bin/xcrun", "--toolchain", toolchainPath.pathString, "swiftc", inputPath.pathString, "-Xlinker", "-rpath", "-Xlinker", backDeploymentLibPath.pathString, "-o", outputPath.pathString])
                    try Process.checkNonZeroExit(arguments: [outputPath.pathString])
                }
            } catch {
                // On any failure we assume false.
                return false
            }
            // If we get this far we could compile and run a trivial executable that uses libConcurrency, so we can say that this toolchain supports concurrency on this host.
            return true
        }
      #else
        // On other platforms, concurrency is assumed to work since with new enough versions of the toolchain.
        return true
      #endif
    }
    
}
