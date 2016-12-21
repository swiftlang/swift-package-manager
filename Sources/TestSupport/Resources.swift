/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

#if os(macOS)
import Foundation.NSBundle
import class Foundation.ProcessInfo
#endif

import Basic
import POSIX

import PackageLoading

#if os(macOS)
private func bundleRoot() -> AbsolutePath {
    for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
        return AbsolutePath(bundle.bundlePath).parentDirectory
    }
    fatalError()
}
#endif

public struct Resources: ManifestResourceProvider {

    /// Shared resources instance.
    public static let sharedResources = Resources()

#if os(macOS)
  #if Xcode
    public let swiftCompilerPath: AbsolutePath = {
        let swiftc: AbsolutePath
        if let base = getenv("XCODE_DEFAULT_TOOLCHAIN_OVERRIDE")?.chuzzle() {
            swiftc = AbsolutePath(base).appending(components: "usr", "bin", "swiftc")
        } else if let override = getenv("SWIFT_EXEC")?.chuzzle() {
            swiftc = AbsolutePath(override)
        } else {
            // Add the toolchains override from build time logs if present.
            // This lets us use toolchain selection from Xcode preferences menu.
            var env = ProcessInfo.processInfo.environment
            let toolchainsLog = bundleRoot().appending(component: "toolchains-build-time-value.log")
            if localFileSystem.exists(toolchainsLog) {
                env["TOOLCHAINS"] = try! localFileSystem.readFileContents(toolchainsLog).asString!
            }
            swiftc = try! AbsolutePath(popen(["xcrun", "--find", "swiftc"], environment: env).chuzzle() ?? "BADPATH")
        }
        print("bundle: " + bundleRoot().asString)
        print("Using swift: " + swiftc.asString)
        precondition(swiftc != AbsolutePath("/usr/bin/swiftc"))
        return swiftc
    }()
  #else
    public let swiftCompilerPath = bundleRoot().appending(component: "swiftc")
  #endif
    public let libraryPath = bundleRoot()
#else
    public let libraryPath = AbsolutePath(CommandLine.arguments.first!, relativeTo: currentWorkingDirectory).parentDirectory
    public let swiftCompilerPath = AbsolutePath(CommandLine.arguments.first!, relativeTo: currentWorkingDirectory).parentDirectory.appending(component: "swiftc")
#endif

    private init() {}
}
