//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageLoading
import XCTest

final class PkgConfigAllowlistTests: XCTestCase {
    func testSimpleFlags() throws {
        let cFlags = ["-I/usr/local/Cellar/gtk+3/3.18.9/include/gtk-3.0"]
        let libs = ["-L/usr/local/Cellar/gtk+3/3.18.9/lib", "-lgtk-3", "-w"]
        XCTAssertTrue(try allowlist(pcFile: "dummy", flags: (cFlags, libs)).disallowed.isEmpty)
    }

    func testFlagsWithInvalidFlags() throws {
        let cFlags = ["-I/usr/local/Cellar/gtk+3/3.18.9/include/gtk-3.0", "-L/hello"]
        let libs = ["-L/usr/local/Cellar/gtk+3/3.18.9/lib", "-lgtk-3", "-module-name", "name", "-werror"]
        let disallowed = try allowlist(pcFile: "dummy", flags: (cFlags, libs)).disallowed
        XCTAssertEqual(disallowed, ["-L/hello", "-module-name", "name", "-werror"])
    }

    func testFlagsWithValueInNextFlag() throws {
        let cFlags = ["-I/usr/local", "-I", "/usr/local/Cellar/gtk+3/3.18.9/include/gtk-3.0", "-L/hello"]
        let libs = ["-L", "/usr/lib", "-L/usr/local/Cellar/gtk+3/3.18.9/lib", "-lgtk-3", "-module-name", "-lcool", "ok", "name"]
        let disallowed = try allowlist(pcFile: "dummy", flags: (cFlags, libs)).disallowed
        XCTAssertEqual(disallowed, ["-L/hello", "-module-name", "ok", "name"])
    }

    func testRemoveDefaultFlags() throws {
        let cFlags = ["-I/usr/include", "-I", "/usr/include" , "-I", "/usr/include/Cellar/gtk+3/3.18.9/include/gtk-3.0", "-L/hello", "-I", "/usr/include"]
        let libs = ["-L", "/usr/lib", "-L/usr/lib/Cellar/gtk+3/3.18.9/lib", "-L/usr/lib", "-L/usr/lib", "-lgtk-3", "-module-name", "-lcool", "ok", "name", "-L", "/usr/lib"]
        let result = try removeDefaultFlags(cFlags: cFlags, libs: libs)

        XCTAssertEqual(result.0, ["-I", "/usr/include/Cellar/gtk+3/3.18.9/include/gtk-3.0", "-L/hello"])
        XCTAssertEqual(result.1, ["-L/usr/lib/Cellar/gtk+3/3.18.9/lib", "-lgtk-3", "-module-name", "-lcool", "ok", "name"])
    }

    func testPathSDKPaths() throws {
        let flags = ["-I/opt/homebrew/Cellar/cairo/1.16.0_5/include/cairo", "-I/Library/Developer/CommandLineTools/SDKs/MacOSX13.sdk/usr/include/ffi"]
        let sdk = AbsolutePath("/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX13.3.sdk")
        let result = try patchSDKPaths(in: flags, to: sdk)

        XCTAssertEqual(result, ["-I/opt/homebrew/Cellar/cairo/1.16.0_5/include/cairo", "-I\(sdk)/usr/include/ffi"])
    }
}
