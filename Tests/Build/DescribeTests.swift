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
                var platformArgs: [String] { fatalError() }
                var sysroot: String?  { fatalError() }
                var SWIFT_EXEC: String { fatalError() }
                var clang: String { fatalError() }
            }

            try POSIX.mkdtemp("spm-tests") { prefix in
                defer { _ = try? rmtree(prefix) }
                let _ = try describe(Path.join(prefix, "foo"), .Debug, [], [], [], Xcc: [], Xld: [], Xswiftc: [], toolchain: InvalidToolchain())
                XCTFail("This call should throw")
            }
        } catch Build.Error.NoModules {
            XCTAssert(true, "This error should be thrown")
        } catch {
            XCTFail("No other error should be thrown")
        }
    }
}

extension DescribeTests {
    static var allTests: [(String, (DescribeTests) -> () throws -> Void)] {
        return [
            ("testDescribingNoModulesThrows", testDescribingNoModulesThrows),
        ]
    }
}
