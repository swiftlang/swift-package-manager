/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import PackageLoading
import XCTest

final class PkgConfigWhitelistTests: XCTestCase {
    func testSimpleFlags() {
        let cFlags = ["-I/usr/local/Cellar/gtk+3/3.18.9/include/gtk-3.0"]
        let libs = ["-L/usr/local/Cellar/gtk+3/3.18.9/lib", "-lgtk-3"]
        do {
            try whitelist(pcFile: "dummy", flags: (cFlags, libs))
        } catch {
            XCTFail("Unexpected failure \(error)")
        }
    }

    func testFlagsWithInvalidFlags() {
        let cFlags = ["-I/usr/local/Cellar/gtk+3/3.18.9/include/gtk-3.0", "-L/hello"]
        let libs = ["-L/usr/local/Cellar/gtk+3/3.18.9/lib", "-lgtk-3", "-module-name", "name"]
        do {
            try whitelist(pcFile: "dummy", flags: (cFlags, libs))
        } catch {
           let errorString = "nonWhitelistedFlags(\"Non whitelisted flags found: [\\\"-L/hello\\\", \\\"-module-name\\\", \\\"name\\\"] in pc file dummy\")"
           XCTAssertEqual("\(error)", errorString)
        }
    }

    func testFlagsWithValueInNextFlag() {
        let cFlags = ["-I/usr/local", "-I", "/usr/local/Cellar/gtk+3/3.18.9/include/gtk-3.0", "-L/hello"]
        let libs = ["-L", "/usr/lib", "-L/usr/local/Cellar/gtk+3/3.18.9/lib", "-lgtk-3", "-module-name", "-lcool", "ok", "name"]
        do {
            try whitelist(pcFile: "dummy", flags: (cFlags, libs))
        } catch {
           let errorString = "nonWhitelistedFlags(\"Non whitelisted flags found: [\\\"-L/hello\\\", \\\"-module-name\\\", \\\"ok\\\", \\\"name\\\"] in pc file dummy\")"
           XCTAssertEqual("\(error)", errorString)
        }
    }

    func testRemoveDefaultFlags() {
        let cFlags = ["-I/usr/include", "-I", "/usr/include" , "-I", "/usr/include/Cellar/gtk+3/3.18.9/include/gtk-3.0", "-L/hello", "-I", "/usr/include"]
        let libs = ["-L", "/usr/lib", "-L/usr/lib/Cellar/gtk+3/3.18.9/lib", "-L/usr/lib", "-L/usr/lib", "-lgtk-3", "-module-name", "-lcool", "ok", "name", "-L", "/usr/lib"]
        let result = removeDefaultFlags(cFlags: cFlags, libs: libs)

        XCTAssertEqual(result.0, ["-I", "/usr/include/Cellar/gtk+3/3.18.9/include/gtk-3.0", "-L/hello"])
        XCTAssertEqual(result.1, ["-L/usr/lib/Cellar/gtk+3/3.18.9/lib", "-lgtk-3", "-module-name", "-lcool", "ok", "name"])
    }

    static var allTests = [
        ("testSimpleFlags", testSimpleFlags),
        ("testFlagsWithInvalidFlags", testFlagsWithInvalidFlags),
        ("testFlagsWithValueInNextFlag", testFlagsWithValueInNextFlag),
        ("testRemoveDefaultFlags", testRemoveDefaultFlags),
    ]
}
