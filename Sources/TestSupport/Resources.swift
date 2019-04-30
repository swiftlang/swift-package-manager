/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Build
import Foundation
import Commands
import PackageLoading
import Workspace

#if os(macOS)
private func bundleRoot() -> AbsolutePath {
    for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
        return AbsolutePath(bundle.bundlePath).parentDirectory
    }
    fatalError()
}
#endif

public class Resources: ManifestResourceProvider {

    public var swiftCompiler: AbsolutePath {
        return toolchain.manifestResources.swiftCompiler
    }

    public var libDir: AbsolutePath {
        return toolchain.manifestResources.libDir
    }

  #if os(macOS)
    public var sdkPlatformFrameworksPath: AbsolutePath {
        return Destination.sdkPlatformFrameworkPath()!
    }
  #endif

    let toolchain: UserToolchain

    public static let `default` = Resources()

    private init() {
        toolchain = try! UserToolchain(destination: Destination.hostDestination())
    }
}
