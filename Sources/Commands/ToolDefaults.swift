/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageLoading
import PackageModel
import POSIX

struct ToolDefaults: ManifestResourceProvider {
  #if Xcode
    // when in Xcode we are built with same toolchain as we will run
    // this is not a production ready mode

    // FIXME: This isn't correct; we need to handle a missing SWIFT_EXEC.
    static let SWIFT_EXEC = AbsolutePath(getenv("SWIFT_EXEC")!.abspath)
    static let llbuild = AbsolutePath(getenv("SWIFT_EXEC")!.abspath).appending("../swift-build-tool")
    static let libdir = AbsolutePath(argv0.abspath).parentDirectory
  #else
    static let SWIFT_EXEC = AbsolutePath(argv0.abspath).appending("../swiftc")
    static let llbuild = AbsolutePath(argv0.abspath).appending("../swift-build-tool")
    static let libdir = AbsolutePath(argv0.abspath).appending("../../lib/swift/pm")
  #endif

    var swiftCompilerPath: AbsolutePath {
        return ToolDefaults.SWIFT_EXEC
    }

    var libraryPath: AbsolutePath {
        return ToolDefaults.libdir
    }
}
