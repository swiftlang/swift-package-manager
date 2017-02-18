/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

#if os(macOS)
import Foundation.NSBundle
#endif

import Basic
import POSIX
import Utility

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
#if os(macOS)
  #if Xcode
    public let swiftCompilerPath: AbsolutePath = {
        let swiftc: AbsolutePath
        if let base = getenv("XCODE_DEFAULT_TOOLCHAIN_OVERRIDE")?.chuzzle() {
            swiftc = AbsolutePath(base).appending(components: "usr", "bin", "swiftc")
        } else if let override = getenv("SWIFT_EXEC")?.chuzzle() {
            swiftc = AbsolutePath(override)
        } else {
            swiftc = try! AbsolutePath(Process.checkNonZeroExit(args: "xcrun", "--find", "swiftc").chuzzle() ?? "BADPATH")
        }
        precondition(swiftc != AbsolutePath("/usr/bin/swiftc"))
        return swiftc
    }()
  #else
    public let swiftCompilerPath = bundleRoot().appending(component: "swiftc")
  #endif
    public let baselibPath = bundleRoot()
#else
    public let baselibPath = AbsolutePath(CommandLine.arguments.first!, relativeTo: currentWorkingDirectory).parentDirectory
    public let swiftCompilerPath = AbsolutePath(CommandLine.arguments.first!, relativeTo: currentWorkingDirectory).parentDirectory.appending(component: "swiftc")
#endif

    public var libraryPath: AbsolutePath {
      #if Xcode
        // FIXME: This needs to select right version package description in Xcode.
        // But we can't do that from Xcode, we should just use the bootstrapped fake toolchain.
        return baselibPath
      #else
        return baselibPath.parentDirectory.appending(components: "lib", "swift", "pm")
      #endif
    }

    public init() {}
}
