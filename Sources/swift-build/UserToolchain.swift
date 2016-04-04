/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import protocol Build.Toolchain
import struct Utility.Path
import enum Multitool.Error
import POSIX

struct UserToolchain: Toolchain {
    let SWIFT_EXEC: String
    let clang: String
    let sysroot: String?

#if os(OSX)
    /**
      On OS X we do not support running in situations where xcrun fails.
     */
    init() throws {
        SWIFT_EXEC = try getenv("SWIFT_EXEC") ?? POSIX.popen(["xcrun", "--find", "swiftc"]).chomp()
        clang = try getenv("CC") ?? POSIX.popen(["xcrun", "--find", "clang"]).chomp()
        sysroot = try getenv("SYSROOT") ?? POSIX.popen(["xcrun", "--sdk", "macosx", "--show-sdk-path"]).chomp()

        guard !SWIFT_EXEC.isEmpty && !clang.isEmpty && !sysroot!.isEmpty else {
            throw Multitool.Error.InvalidToolchain
        }
    }

    var platformArgs: [String] {
        return ["-target", "x86_64-apple-macosx10.10", "-sdk", sysroot!]
    }

#else

    init() throws {
        do {
            SWIFT_EXEC = getenv("SWIFT_EXEC")
                // see if user has put something earlier in the path
                ?? (try? POSIX.popen(["which", "swiftc"]))?.chomp().abspath()
                // use the swiftc installed alongside ourselves
                ?? Path.join(Process.arguments[0], "../swiftc").abspath()
            clang = try getenv("CC") ?? popen(["which", "clang"]).chomp().abspath()
            sysroot = nil
        } catch POSIX.Error.ExitStatus {
            throw Multitool.Error.InvalidToolchain
        }
        guard !SWIFT_EXEC.isEmpty && !clang.isEmpty else {
            throw Multitool.Error.InvalidToolchain
        }

    }

    let platformArgs: [String] = []
#endif
}
