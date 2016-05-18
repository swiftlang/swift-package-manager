/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageModel
import XCTest

class ValidSourcesTests: XCTestCase {
    func testDotFilesAreIgnored() throws {
        do {
            try fixture(files: [".Bar.swift", "Foo.swift"]) { (package, modules) in
                XCTAssertEqual(modules.count, 1)
                guard let swiftModule = modules.first as? SwiftModule else { return XCTFail() }
                XCTAssertEqual(swiftModule.sources.paths.count, 1)
                XCTAssertEqual(swiftModule.sources.paths.first?.basename, "Foo.swift")
                XCTAssertEqual(swiftModule.name, package.name)
            }
        } catch {
            XCTFail("\(error)")
        }
    }
}

extension ValidSourcesTests {
    static var allTests : [(String, (ValidSourcesTests) -> () throws -> Void)] {
        return [
            ("testDotFilesAreIgnored", testDotFilesAreIgnored),
        ]
    }
}
