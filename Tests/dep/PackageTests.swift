/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
import XCTestCaseProvider
import struct dep.Package
import struct sys.Path
import func POSIX.rename


class PackageTests: XCTestCase, XCTestCaseProvider {

    var allTests : [(String, () -> Void)] {
        return [
            ("testInitializer", testInitializer),
            ("testModuleTypes", testModuleTypes),
        ]
    }

    func testInitializer() {
        fixture(name: "Miscellaneous/PackageType") { prefix in

            do {
                // valid path, but no manifest so check throw is correct
                let foo1 = try Package(path: "foo-1.0.0")
                XCTAssertNil(foo1)
                // invalid path will return nil
                let foo2 = try Package(path: "foo")
                XCTAssertNil(foo2)
            }

        //////
            XCTAssertBuilds(prefix, "App")

            let basepath = Path.join(prefix, "App", "Packages")
            var oldpath = Path.join(basepath, "Module-1.2.3")

            func test(newname: String, line: UInt) throws {

                let newpath = Path.join(basepath, newname)
                try rename(old: oldpath, new: newpath)
                let pkg = try Package(path: newpath)

                XCTAssertNotNil(pkg, "Package(path: \(newname))", line: line)

                oldpath = newpath
            }

            try test("Module-1.2.3-alpha", line: __LINE__)
            try test("Module-1.2.3-beta1.foo", line: __LINE__)
            try test("Module-1.2.3-beta1.foo+23", line: __LINE__)
            try test("Module-1.2.3+23", line: __LINE__)
        }
    }

    func testModuleTypes() {
        fixture(name: "Miscellaneous/PackageType") { prefix in
            XCTAssertBuilds(prefix, "App")
            let pkg1 = try Package(path: Path.join(prefix, "App/Packages/Module-1.2.3"))
            let pkg2 = try Package(path: Path.join(prefix, "App/Packages/ModuleMap-1.2.3"))
            XCTAssertEqual(pkg1?.type, .Module)
            XCTAssertEqual(pkg2?.type, .ModuleMap)
        }
    }

}
