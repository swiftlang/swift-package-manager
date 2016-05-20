/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import POSIX

import protocol Build.Toolchain
import struct Utility.Path

#if os(OSX)
    private let whichClangArgs = ["xcrun", "--find", "clang"]
#else
    private let whichClangArgs = ["which", "clang"]
#endif

struct UserToolchain: Toolchain {
    let SWIFT_EXEC: String
    let clang: String
    let sysroot: String?

#if os(OSX)
    var platformArgs: [String] {
        return ["-target", "x86_64-apple-macosx10.10", "-sdk", sysroot!]
    }
#else
    let platformArgs: [String] = []
#endif

    init() throws {
        do {
            SWIFT_EXEC = getenv("SWIFT_EXEC")
                // use the swiftc installed alongside ourselves
                ?? Path.join(Process.arguments[0], "../swiftc").abspath

            clang = try getenv("CC") ?? POSIX.popen(whichClangArgs).chomp()

            #if os(OSX)
                sysroot = try getenv("SYSROOT") ?? POSIX.popen(["xcrun", "--sdk", "macosx", "--show-sdk-path"]).chomp()
            #else
                sysroot = nil
            #endif

            guard !SWIFT_EXEC.isEmpty && !clang.isEmpty && (sysroot == nil || !sysroot!.isEmpty) else {
                throw Error.InvalidToolchain
            }
        } catch POSIX.Error.ExitStatus {
            throw Error.InvalidToolchain
        }
    }
}
