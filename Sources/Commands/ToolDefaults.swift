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
//    static let SWIFT_EXEC = AbsolutePath(getenv("SWIFT_EXEC")!, relativeTo: currentWorkingDirectory)
//    static let llbuild = AbsolutePath(getenv("SWIFT_EXEC")!, relativeTo: currentWorkingDirectory).parentDirectory.appending(component: "swift-build-tool")
    // FIXME: This probably isn't much better, but it does solve the issue on my machine.
    static var SWIFT_EXEC: AbsolutePath {
        if let env = getenv("SWIFT_EXEC") {
            return AbsolutePath(env, relativeTo: currentWorkingDirectory)
        } else {
            do {
                try setenv("SWIFT_EXEC", value:"/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swiftc")
            } catch let error {
                fatalError("getenv(\"SWIFT_EXEC\") returned nil, and we then caught \"\(error)\" while calling setenv(\"SWIFT_EXEC\", value:\"/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swiftc\") so that subsequent calls to getenv(\"SWIFT_EXEC\") could return a value, so that we can have a path for SWIFT_EXEC. The error is fatal to prevent an infinite loop.")
            }
            return self.SWIFT_EXEC
        }
    }

    static var llbuild: AbsolutePath {
        if let env = getenv("SWIFT_EXEC") {
            return AbsolutePath(env, relativeTo: currentWorkingDirectory).parentDirectory.appending(component: "swift-build-tool")
        } else {
            do {
                try setenv("SWIFT_EXEC", value:"/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swiftc")
            } catch let error {
                fatalError("getenv(\"SWIFT_EXEC\") returned nil, and we then caught \"\(error)\" while calling setenv(\"SWIFT_EXEC\", value:\"/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swiftc\") so that subsequent calls to getenv(\"SWIFT_EXEC\") could return a value, so that we can have a path for llbuild. The error is fatal to prevent an infinite loop.")
            }
            return self.llbuild
        }
    }
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
