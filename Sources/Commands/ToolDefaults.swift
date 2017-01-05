/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageLoading
import POSIX

struct ToolDefaults: ManifestResourceProvider {
    // We have to do things differently depending on whether we're running in
    // Xcode or in other cases, unfortunately.
    
    // First we form the absolute path of the directory that contains the main
    // executable.
    static let execBinDir = AbsolutePath(argv0, relativeTo: currentWorkingDirectory).parentDirectory
  #if Xcode
    // when in Xcode we are built with same toolchain as we will run
    // this is not a production ready mode

    // FIXME: This isn't correct; we need to handle a missing SWIFT_EXEC.
    static let SWIFT_EXEC = AbsolutePath(getenv("SWIFT_EXEC")!, relativeTo: currentWorkingDirectory)
    static let llbuild = AbsolutePath(getenv("SWIFT_EXEC")!, relativeTo: currentWorkingDirectory).parentDirectory.appending(component: "swift-build-tool")
    static let libdir = execBinDir
  #else
    static let SWIFT_EXEC = execBinDir.appending(component: "swiftc")
    static let llbuild = execBinDir.appending(component: "swift-build-tool")
    static let libdir = execBinDir.parentDirectory.appending(components: "lib", "swift", "pm")
  #endif

    var swiftCompilerPath: AbsolutePath {
        return ToolDefaults.SWIFT_EXEC
    }

    var libraryPath: AbsolutePath {
        return ToolDefaults.libdir
    }
}
