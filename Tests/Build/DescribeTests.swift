/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Build
import Utility
import POSIX

final class DescribeTests: XCTestCase {
    func testDescribingNoModulesThrows() {
        do {
            struct InvalidToolchain: Toolchain {
                var platformArgsClang: [String] { fatalError() }
                var platformArgsSwiftc: [String] { fatalError() }
                var sysroot: String?  { fatalError() }
                var SWIFT_EXEC: String { fatalError() }
                var clang: String { fatalError() }
            }

            try POSIX.mkdtemp("spm-tests") { prefix in
                defer { _ = try? FileManager.default().removeItem(atPath: prefix) }
                let _ = try describe(Path.join(prefix, "foo"), .debug, [], [], [], Xcc: [], Xld: [], Xswiftc: [], toolchain: InvalidToolchain())
                XCTFail("This call should throw")
            }
        } catch Build.Error.noModules {
            XCTAssert(true, "This error should be thrown")
        } catch {
            XCTFail("No other error should be thrown")
        }
    }

    static var allTests = [
        ("testDescribingNoModulesThrows", testDescribingNoModulesThrows),
    ]
}
