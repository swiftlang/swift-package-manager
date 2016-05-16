/*
 This source file is part of the Swift.org open source project
 
 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
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
           let errorString = "NonWhitelistedFlags(\"Non whitelisted flags found: [\\\"-L/hello\\\", \\\"-module-name\\\", \\\"name\\\"] in pc file dummy\")"
           XCTAssertEqual("\(error)", errorString)
        }
    }

    func testFlagsWithValueInNextFlag() {
        let cFlags = ["-I/usr/local", "-I", "/usr/local/Cellar/gtk+3/3.18.9/include/gtk-3.0", "-L/hello"]
        let libs = ["-L", "/usr/lib", "-L/usr/local/Cellar/gtk+3/3.18.9/lib", "-lgtk-3", "-module-name", "-lcool", "ok", "name"]
        do {
            try whitelist(pcFile: "dummy", flags: (cFlags, libs))
        } catch {
           let errorString = "NonWhitelistedFlags(\"Non whitelisted flags found: [\\\"-L/hello\\\", \\\"-module-name\\\", \\\"ok\\\", \\\"name\\\"] in pc file dummy\")"
           XCTAssertEqual("\(error)", errorString)
        }
    }
}

extension PkgConfigWhitelistTests {
    static var allTests : [(String, (PkgConfigWhitelistTests) -> () throws -> Void)] {
        return [
            ("testSimpleFlags", testSimpleFlags),
            ("testFlagsWithInvalidFlags", testFlagsWithInvalidFlags),
            ("testFlagsWithValueInNextFlag", testFlagsWithValueInNextFlag),
        ]
    }
}
