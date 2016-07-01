/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageModel
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
                defer { _ = try? Utility.removeFileTree(prefix) }
                let _ = try describe(prefix.appending("foo"), .debug, [], [], [], Xcc: [], Xld: [], Xswiftc: [], toolchain: InvalidToolchain())
                XCTFail("This call should throw")
            }
        } catch Build.Error.noModules {
            XCTAssert(true, "This error should be thrown")
        } catch {
            XCTFail("No other error should be thrown")
        }
    }

    func testDescribingNoProductsThrows() {
        do {
            struct InvalidToolchain: Toolchain {
                var platformArgsClang: [String] { fatalError() }
                var platformArgsSwiftc: [String] { fatalError() }
                var sysroot: String?  { fatalError() }
                var SWIFT_EXEC: String { return "" }
                var clang: String { fatalError() }
            }

            try POSIX.mkdtemp("spm-tests") { prefix in
                defer { _ = try? Utility.removeFileTree(prefix) }
                let _ = try describe(Path.join(prefix, "foo"), .debug, [CModule(name: "MyCModule", path: "")], [], [], Xcc: [], Xld: [], Xswiftc: [], toolchain: InvalidToolchain())
                XCTFail("This call should throw")
            }
        } catch Build.Error.noProducts {
            XCTAssert(true, "This error should be thrown")
        } catch {
            print(error)
            XCTFail("No other error should be thrown")
        }
    }

    static var allTests = [
        ("testDescribingNoModulesThrows", testDescribingNoModulesThrows),
        ("testDescribingNoProductsThrows", testDescribingNoProductsThrows),
    ]
}
