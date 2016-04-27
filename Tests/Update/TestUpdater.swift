/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Update
import struct PackageDescription.Version
import XCTest


//TODO detect circular dependencies


class UpdateTestCase: XCTestCase {
    func testEmptyGraph() throws {
        let updater = Updater(dependencies: [])
        while let turn = try updater.crank() {
            switch turn {
            default:
                XCTFail()
            }
        }
    }

    func testBump() throws {

        // a~>1 where a = 1.0 and a can be 1.1

        let r2 = Version(1,0,0)...Version(2,0,0)

        let updater = Updater(dependencies: [("a", r2)])
        let ex = (expectation(withDescription: ".Fetch"), expectation(withDescription: ".ReadManifest"), expectation(withDescription: ".Update"))

        while let turn = try updater.crank() {
            switch turn {
            case .Fetch(let url):
                XCTAssertEqual(url, "a")
                ex.0.fulfill()
            case .ReadManifest(let read):
                try read { url, range in
                    ex.1.fulfill()
                    XCTAssertEqual(url, "a")
                    XCTAssertEqual(range, r2)
                    return ([], Version(1,0,0))
                }
            case .Update(let url, let range):
                XCTAssertEqual(url, "a")
                XCTAssertEqual(range, r2)

                // this is where we would bump a, the test verifies
                // the updater validated that a bump of a is in `range`

                ex.2.fulfill()
            }
        }

        waitForExpectations(withTimeout: 0)
    }


    func testConstraints() throws {

        // root -> a -> b~1.1
        // root -> b~>1

        let r1 = Version(1,0,0)...Version(1,0,0)
        let r2 = Version(1,0,0)...Version(2,0,0)
        let r3 = Version(1,0,0)...Version(1,1,0)

        let updater = Updater(dependencies: [("a", r1), ("b", r2)])
        let ex = (expectation(withDescription: ""), expectation(withDescription: ""))

        while let turn = try updater.crank() {
            switch turn {
            case .Fetch(let url):
                switch url {
                case "a", "b":
                    break
                default:
                    XCTFail()
                }
            case .ReadManifest(let read):
                try read { url, range in
                    switch url {
                    case "a":
                        XCTAssertEqual(range, r1)
                        return ([("b", r3)], Version(1,0,0))
                    case "b":
                        return ([], Version(1,0,0))
                    default:
                        fatalError()
                    }
                }
            case .Update(let url, let range):
                switch url {
                case "a":
                    XCTAssertEqual(range, r1)
                    ex.0.fulfill()
                case "b":
                    XCTAssertEqual(range, r3)
                    ex.1.fulfill()
                default:
                    XCTFail()
                }
            }
        }

        waitForExpectations(withTimeout: 0)
    }

    func testUnresolvableGraph() throws {

        // root -> a -> b~2
        // root -> b~>1

        let r1 = Version(1,0,0)...Version(1,0,0)
        let r2 = Version(1,0,0)...Version(1,1,0)
        let r3 = Version(2,0,0)...Version(2,0,0)

        let updater = Updater(dependencies: [("a", r1), ("b", r2)])
        let ex = expectation(withDescription: "")

        do {
            while let turn = try updater.crank() {
                switch turn {
                case .Fetch(let url):
                    switch url {
                    case "a", "b":
                        break
                    default:
                        XCTFail()
                    }
                case .ReadManifest(let read):
                    try read { url, range in
                        switch url {
                        case "a":
                            XCTAssertEqual(range, r1)
                            return ([("b", r3)], Version(1,0,0))
                        case "b":
                            return ([], Version(1,0,0))
                        default:
                            fatalError()
                        }
                    }
                case .Update:
                    XCTFail()
                }
            }
        } catch Update.Error.GraphCannotBeSatisfied(let url) {
            XCTAssertEqual(url, "b")
            ex.fulfill()
        }

        waitForExpectations(withTimeout: 0)
    }
}
