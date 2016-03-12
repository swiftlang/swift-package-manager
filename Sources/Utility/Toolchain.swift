/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -------------------------------------------------------------------------
 This file defines support functions for resources tied to the installed
 location of the containing product binary.
 */

import func POSIX.getenv
import func POSIX.popen

public protocol Installation {
    static func which(cmd: String) -> String
}

public struct Toolchain: Installation {
    public static func which(cmd: String) -> String {
        if let exepath = Process.arguments.first {
            if let path = try? Path.join(exepath, "..", cmd).abspath() where path.isFile {
                return path
            }
        }

    #if os(OSX)
        if let cmdpath = (try? popen(["xcrun", "--find", cmd]))?.chuzzle() {
            return cmdpath
        }
    #endif
        
        return cmd
    }

    //TODO better
    public static var prefix: String {
        return swiftc.parentDirectory.parentDirectory.parentDirectory
    }

    /// the location of swiftc relative to our installation
    public static let swiftc = getenv("SWIFT_EXEC") ?? Toolchain.which("swiftc")

    /// the location of swift_build_tool relatve to our installation
    public static let swift_build_tool = getenv("SWIFT_BUILD_TOOL") ?? Toolchain.which("swift-build-tool")
	
    /// the location of clang relatve to our installation
    public static let clang = getenv("CC") ?? Toolchain.which("clang")
}

#if os(OSX)
extension Toolchain {
    public static let sysroot = getenv("SYSROOT") ?? (try? POSIX.popen(["xcrun", "--sdk", "macosx", "--show-sdk-path"]))?.chuzzle()
    public static let platformPath = (try? POSIX.popen(["xcrun", "--sdk", "macosx", "--show-sdk-platform-path"]))?.chuzzle()
}
#endif


