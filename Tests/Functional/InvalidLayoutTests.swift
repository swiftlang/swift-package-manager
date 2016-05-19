/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Utility

class InvalidLayoutsTestCase: XCTestCase {

    func testMultipleRoots() {
        fixture(name: "InvalidLayouts/MultipleRoots1") { prefix in
            XCTAssertBuildFails(prefix)
        }
        fixture(name: "InvalidLayouts/MultipleRoots2") { prefix in
            XCTAssertBuildFails(prefix)
        }
    }

    func testInvalidLayout1() {
        /*
         Package
         ├── main.swift   <-- invalid
         └── Sources
             └── File2.swift
        */
        fixture(name: "InvalidLayouts/Generic1") { prefix in
            XCTAssertBuildFails(prefix)
            try Utility.removeFileTree("\(prefix)/main.swift")
            XCTAssertBuilds(prefix)
        }
    }

    func testInvalidLayout2() {
        /*
         Package
         ├── main.swift  <-- invalid
         └── Bar
             └── Sources
                 └── File2.swift
        */
        fixture(name: "InvalidLayouts/Generic2") { prefix in
            XCTAssertBuildFails(prefix)
            try Utility.removeFileTree("\(prefix)/main.swift")
            XCTAssertBuilds(prefix)
        }
    }

    func testInvalidLayout3() {
        /*
         Package
         └── Sources
             ├── main.swift  <-- Invalid
             └── Bar
                 └── File2.swift
        */
        fixture(name: "InvalidLayouts/Generic3") { prefix in
            XCTAssertBuildFails(prefix)
            try Utility.removeFileTree("\(prefix)/Sources/main.swift")
            XCTAssertBuilds(prefix)
        }
    }

    func testInvalidLayout4() {
        /*
         Package
         ├── main.swift  <-- Invalid
         └── Sources
             └── Bar
                 └── File2.swift
        */
        fixture(name: "InvalidLayouts/Generic4") { prefix in
            XCTAssertBuildFails(prefix)
            try Utility.removeFileTree("\(prefix)/main.swift")
            XCTAssertBuilds(prefix)
        }
    }

    func testInvalidLayout5() {
        /*
         Package
         ├── File1.swift
         └── Foo
             └── Foo.swift  <-- Invalid
        */
        fixture(name: "InvalidLayouts/Generic5") { prefix in

            XCTAssertBuildFails(prefix)

            // for the simplest layout it is invalid to have any
            // subdirectories. It is the compromise you make.
            // the reason for this is mostly performance in
            // determineTargets() but also we are saying: this
            // layout is only for *very* simple projects.

            try Utility.removeFileTree("\(prefix)/Foo/Foo.swift")
            try Utility.removeFileTree("\(prefix)/Foo")
            XCTAssertBuilds(prefix)
        }
    }
}
